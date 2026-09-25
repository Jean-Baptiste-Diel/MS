import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:dio/dio.dart' as dio_package;

const kPendingApprovalError = 'PENDING_APPROVAL';

// ── Redirect to login ─────────────────────────────────────────────────────────

bool _isRedirectingToLogin = false;

Future<void> _redirectToLogin() async {
  if (_isRedirectingToLogin) return;
  _isRedirectingToLogin = true;

  await clearPreferences();

  final ctx = navigatorKey.currentContext;
  if (ctx != null) {
    TopToast.show(
      message: 'Session expirée, reconnectez-vous',
      type: TopToastType.error,
    );
    await Future.delayed(const Duration(milliseconds: 800));
    SignInScreen().launch(ctx, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
  }

  Future.delayed(const Duration(seconds: 3), () => _isRedirectingToLogin = false);
}

// ── Token refresh (mutex) ─────────────────────────────────────────────────────

bool _isRefreshing = false;
Completer<bool>? _refreshCompleter;

/// Rafraîchit l'access token via POST /auth/refresh.
/// Retourne true si le refresh a réussi, false si le refresh token est expiré.
/// Mutex : si un refresh est déjà en cours, les appelants concurrents attendent le même résultat.
Future<bool> _tryRefreshToken() async {
  if (_isRefreshing) {
    return _refreshCompleter!.future;
  }

  final refreshToken = appStore.refreshToken;
  if (refreshToken.isEmpty) return false;

  _isRefreshing = true;
  _refreshCompleter = Completer<bool>();

  try {
    final response = await http.post(
      Uri.parse('${BASE_URL}auth/refresh'),
      body: jsonEncode({'refresh': refreshToken}),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      },
    );

    if (response.statusCode == 200 && response.body.isJson()) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final newAccess = body['access'] as String?;
      final newRefresh = body['refresh'] as String?;

      if (newAccess != null && newAccess.isNotEmpty) {
        await appStore.setToken(newAccess);
        if (newRefresh != null && newRefresh.isNotEmpty) {
          await appStore.setRefreshToken(newRefresh);
        }
        log('Access token refreshed');
        _refreshCompleter!.complete(true);
        return true;
      }
    }

    // 401 ou 400 = refresh token expiré/blacklisté → rediriger vers login
    log('Refresh token invalide (status ${response.statusCode})');
    _refreshCompleter!.complete(false);
    return false;
  } catch (e) {
    log('Token refresh error: $e');
    _refreshCompleter!.complete(false);
    return false;
  } finally {
    _isRefreshing = false;
    _refreshCompleter = null;
  }
}

/// Point d'entrée public — utilisé par WebSocket / multipart qui gèrent eux-mêmes leurs 401.
/// Retourne true si le token a été rafraîchi, false si le refresh token est expiré.
Future<bool> refreshToken() => _tryRefreshToken();

Map<String, String> buildHeaderTokens() {
  Map<String, String> header = {};

  if (appStore.isLoggedIn) header.putIfAbsent(HttpHeaders.authorizationHeader, () => 'Bearer ${appStore.token}');
  header.putIfAbsent(HttpHeaders.contentTypeHeader, () => 'application/json');
  header.putIfAbsent(HttpHeaders.acceptHeader, () => 'application/json');
  header.putIfAbsent(CustomHeader.LanguageCode, () => appStore.selectedLanguageCode);
  header.addAll(defaultHeaders());

  log(jsonEncode(header));
  return header;
}

Uri buildBaseUrl(String endPoint) {
  Uri url = Uri.parse(endPoint);
  if (!endPoint.startsWith('http')) url = Uri.parse('$BASE_URL$endPoint');

  log('URL: ${url.toString()}');

  return url;
}

/// Endpoints `auth/` qui exigent une session : un 401 y signifie un jeton
/// expiré, il faut rafraîchir puis réessayer. Sans ça, le token FCM/VoIP n'est
/// jamais enregistré au démarrage et le téléphone ne sonne pas lors d'un appel.
const _authenticatedAuthEndpoints = {
  'auth/me',
  'auth/fcm-token',
  'auth/voip-token',
  'auth/change-password',
  // La déconnexion efface le token FCM côté serveur : elle doit aboutir même
  // si le jeton d'accès a expiré, sinon le téléphone reçoit encore les appels.
  'auth/logout',
};

/// Les autres endpoints `auth/` (login, register, OTP…) sont publics : un 401
/// y est une vraie erreur (ex: mauvais PIN), on ne rafraîchit pas.
bool _canRefreshOn401(String endPoint) {
  if (!endPoint.startsWith('auth/')) return true;
  final path = endPoint.split('?').first;
  return _authenticatedAuthEndpoints.contains(path);
}

Future<Response> buildHttpResponse(
  String endPoint, {
  HttpMethodType method = HttpMethodType.GET,
  Map? request,
  Map<String, String>? header,
  bool isRetry = false,
}) async {
  var headers = header ?? buildHeaderTokens();
  Uri url = buildBaseUrl(endPoint);
  Response response;

  try {
    if (method == HttpMethodType.POST) {
      log('Request: ${jsonEncode(request)}');
      response = await http.post(url, body: jsonEncode(request), headers: headers);
    } else if (method == HttpMethodType.DELETE) {
      response = await delete(url, headers: headers);
    } else if (method == HttpMethodType.PUT) {
      response = await put(url, body: jsonEncode(request), headers: headers);
    } else {
      response = await get(url, headers: headers);
    }

    apiPrint(
      url: url.toString(),
      endPoint: endPoint,
      headers: jsonEncode(headers),
      hasRequest: method == HttpMethodType.POST || method == HttpMethodType.PUT,
      request: jsonEncode(request),
      statusCode: response.statusCode,
      responseBody: response.body,
      methodtype: method.name,
    );

    if (appStore.isLoggedIn && response.statusCode == 401 && !endPoint.startsWith('http') && _canRefreshOn401(endPoint)) {
      if (isRetry) {
        // Le token rafraîchi est aussi rejeté → session invalide
        await _redirectToLogin();
        return response;
      }
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        return buildHttpResponse(endPoint, method: method, request: request, isRetry: true);
      } else {
        await _redirectToLogin();
        return response;
      }
    }

    return response;
  } on Exception {
    throw errorInternetNotAvailable;
  }
}

Future handleResponse(Response response, {HttpResponseType httpResponseType = HttpResponseType.JSON}) async {
  if (!await isNetworkAvailable()) {
    throw errorInternetNotAvailable;
  }
  if (response.statusCode == 400) {
    if (response.body.isJson()) {
      var body = jsonDecode(response.body);
      if (body is Map && body.containsKey('message')) {
        throw parseHtmlString(body['message']);
      } else {
        throw '${language.badRequest}';
      }
    }
  } else if (response.statusCode == 403) {
    if (response.body.isJson()) {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final msg = (body['message'] ?? '').toString().toLowerCase();
        if (msg.contains('approbation') || msg.contains('attente') || msg.contains('pending') || msg.contains('approval')) {
          throw kPendingApprovalError;
        }
        if (body.containsKey('message')) throw parseHtmlString(body['message']);
      }
    }
    throw '${language.forbidden}';
  } else if (response.statusCode == 404) {
    throw '${language.pageNotFound}';
  } else if (response.statusCode == 429) {
    throw '${language.tooManyRequests}';
  } else if (response.statusCode == 500) {
    throw '${language.internalServerError}';
  } else if (response.statusCode == 502) {
    throw '${language.badGateway}';
  } else if (response.statusCode == 503) {
    throw '${language.serviceUnavailable}';
  } else if (response.statusCode == 504) {
    throw '${language.gatewayTimeout}';
  }

  if (httpResponseType == HttpResponseType.JSON) {
    if (response.body.isJson()) {
      var body = jsonDecode(response.body);

      if (response.statusCode.isSuccessful()) {
        if (body is Map && body.containsKey('status') && body['status'] is bool && !body['status']) {
          throw parseHtmlString(body['message'] ?? errorSomethingWentWrong);
        } else {
          return body;
        }
      } else {
        throw parseHtmlString(body['message'] ?? errorSomethingWentWrong);
      }
    } else {
      throw errorSomethingWentWrong;
    }
  } else if (httpResponseType == HttpResponseType.BODY_BYTES) {
    return response.bodyBytes;
  } else if (httpResponseType == HttpResponseType.FULL_RESPONSE) {
    return response;
  } else if (httpResponseType == HttpResponseType.STRING) {
    return response.body;
  } else {
    throw errorSomethingWentWrong;
  }
}

Future<Map<String, dynamic>> handleSadadResponse(Response res) async {
  if (res.body.isJson()) {
    var body = jsonDecode(res.body);

    if (res.statusCode.isSuccessful()) {
      return body;
    } else {
      throw parseHtmlString(body['error']['message']);
    }
  } else {
    throw errorSomethingWentWrong;
  }
}


Future<MultipartRequest> getMultiPartRequest(String endPoint, {String? baseUrl}) async {
  String url = '${baseUrl ?? buildBaseUrl(endPoint).toString()}';
  return MultipartRequest('POST', Uri.parse(url));
}

Future<void> sendMultiPartRequest(MultipartRequest multiPartRequest, {Function(dynamic)? onSuccess, Function(dynamic)? onError}) async {
  try {
    http.Response response = await http.Response.fromStream(await multiPartRequest.send());
    apiPrint(
      url: multiPartRequest.url.toString(),
      headers: jsonEncode(multiPartRequest.headers),
      request: jsonEncode(multiPartRequest.fields),
      hasRequest: true,
      statusCode: response.statusCode,
      responseBody: response.body,
      methodtype: "MultiPart",
    );

    if (response.statusCode == 401) {
      final refreshed = await _tryRefreshToken();
      if (!refreshed) await _redirectToLogin();
      return;
    } else if (response.statusCode.isSuccessful()) {
      onSuccess?.call(response.body);
    } else {
      try {
        if (response.body.isJson()) {
          var body = jsonDecode(response.body);
          onError?.call(body['message'] ?? errorSomethingWentWrong);
        } else {
          onError?.call(errorSomethingWentWrong);
        }
      } on Exception catch (e) {
        log(e);
        onError?.call(errorSomethingWentWrong);
      }
    }
  } on SocketException catch (e) {
    log(e.toString());
    onError?.call(language.internetNotAvailable);
  } on Exception catch (e) {
    log(e.toString());
    onError?.call(errorSomethingWentWrong);
  }
}

void apiPrint({
  String url = "",
  String endPoint = "",
  String headers = "",
  String request = "",
  int statusCode = 0,
  String responseBody = "",
  String methodtype = "",
  bool hasRequest = false,
}) {
  log("┌───────────────────────────────────────────────────────────────────────────────────────────────────────");
  log("\u001b[93mUrl: \u001B[39m $url");
  log("\u001b[93mHeader: \u001B[39m \u001b[96m$headers\u001B[39m");
  if (request.isNotEmpty) log("\u001b[93mRequest: \u001B[39m \u001b[96m$request\u001B[39m");
  log('Response ($methodtype) $statusCode: $responseBody');
  log("└───────────────────────────────────────────────────────────────────────────────────────────────────────");
}

Map<String, String> buildHeaderForStripe(String stripeKeyPayment) {
  Map<String, String> header = defaultHeaders();

  header.putIfAbsent(HttpHeaders.contentTypeHeader, () => 'application/x-www-form-urlencoded');
  header.putIfAbsent(HttpHeaders.authorizationHeader, () => 'Bearer $stripeKeyPayment');

  return header;
}

Map<String, String> buildHeaderForSadad({String? sadadToken}) {
  Map<String, String> header = defaultHeaders();

  header.putIfAbsent(HttpHeaders.contentTypeHeader, () => 'application/json');
  if (sadadToken != null) header.putIfAbsent(HttpHeaders.authorizationHeader, () => sadadToken);

  return header;
}

Map<String, String> buildHeaderForFlutterWave(String flutterWaveSecretKey) {
  Map<String, String> header = defaultHeaders();

  header.putIfAbsent(HttpHeaders.authorizationHeader, () => "Bearer $flutterWaveSecretKey");

  return header;
}

Map<String, String> buildHeaderForAirtelMoney(String accessToken, String XCountry, String XCurrency) {
  Map<String, String> header = defaultHeaders();

  header.putIfAbsent(HttpHeaders.contentTypeHeader, () => 'application/json');
  header.putIfAbsent(HttpHeaders.authorizationHeader, () => 'Bearer $accessToken');
  header.putIfAbsent('X-Country', () => '$XCountry');
  header.putIfAbsent('X-Currency', () => '$XCurrency');

  return header;
}

Map<String, String> buildHeaderForAppConfiguration() {
  Map<String, String> header = defaultHeaders();

  // Check if the user is logged in
  if (appStore.isLoggedIn) {
    header.putIfAbsent('user_id', () => appStore.userId.toString()); // if user is logged in pass the user id
  }

  return header;
}

Map<String, String> defaultHeaders() {
  Map<String, String> header = {};

  header.putIfAbsent(HttpHeaders.cacheControlHeader, () => 'no-cache');
  header.putIfAbsent('Access-Control-Allow-Headers', () => '*');
  header.putIfAbsent('Access-Control-Allow-Origin', () => '*');

  return header;
}


Future<dynamic> getRemoteDataFromUrl({
  required String url,
  Map<String, String>? header,
  Map<String, dynamic>? request,
  bool isDownload = false,
}) async {

  try {
    dio_package.Response response;
    final dio_package.Dio dio = dio_package.Dio();
    if (request != null) {
      response = await dio.post(url.toString(), data: request, options: dio_package.Options(headers: header));
    } else {
      response = await dio.get(url.toString(), options: dio_package.Options(headers: header));
    }

    return response.data;
  } catch (e) {
    return null;
  }
}
