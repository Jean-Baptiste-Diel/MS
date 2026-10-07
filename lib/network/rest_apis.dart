import 'package:booking_system_flutter/services/chat_unread_store.dart';
import 'package:booking_system_flutter/utils/log_redact.dart';
import 'package:nb_utils/nb_utils.dart' as nb_log show log;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/model/mison_notification_model.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:booking_system_flutter/model/base_response_model.dart';
import 'package:booking_system_flutter/model/booking_status_model.dart';
import 'package:booking_system_flutter/model/login_model.dart';
import 'package:booking_system_flutter/model/user_data_model.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/start_reminder.dart';
import 'package:booking_system_flutter/utils/order_events.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:nb_utils/nb_utils.dart';

import '../model/wallet_response.dart';
import '../model/mison_order_model.dart';
import '../model/mison_service_model.dart';
import '../utils/app_configuration.dart';
import '../utils/firebase_messaging_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

//region Auth Api
/// Inscription d'un nouvel utilisateur (client) via l'API Mison
/// POST /api/auth/register (multipart/form-data)
/// Retourne un message, l'utilisateur doit vérifier son compte avec l'OTP
Future<BaseResponseModel> createUser(
  Map request, {
  File? profilePicture,
  Uint8List? profilePictureBytes,
  String? profilePictureFileName,
  File? identityDocument,
  Uint8List? identityDocumentBytes,
  String? identityDocumentFileName,
}) async {
  Completer<BaseResponseModel> completer = Completer();

  MultipartRequest multiPartRequest =
      await getMultiPartRequest('auth/register');

  // Email optionnel : n'est envoyé que s'il est renseigné
  final String email = request['email']?.toString().trim() ?? '';
  if (email.isNotEmpty) multiPartRequest.fields['email'] = email;

  // Champs requis
  multiPartRequest.fields['password'] = request['password']?.toString() ?? '';
  multiPartRequest.fields['phone'] =
      request['contact_number']?.toString() ?? '';
  multiPartRequest.fields['first_name'] =
      request['first_name']?.toString() ?? '';
  multiPartRequest.fields['last_name'] = request['last_name']?.toString() ?? '';
  multiPartRequest.fields['type'] =
      request['user_account_type']?.toString() ?? 'PARTICULIER';

  // Ajouter company_name si type = ENTREPRISE
  if (request['company_name'] != null &&
      request['company_name'].toString().isNotEmpty) {
    multiPartRequest.fields['company_name'] =
        request['company_name'].toString();
  }

  // Ajouter photo de profil si fourni (mobile file ou web bytes)
  if (profilePicture != null && profilePicture.existsSync()) {
    multiPartRequest.files.add(
        await MultipartFile.fromPath('profile_picture', profilePicture.path));
  } else if (profilePictureBytes != null && profilePictureBytes.isNotEmpty) {
    String fileName = profilePictureFileName ?? 'profile_picture.jpg';
    multiPartRequest.files.add(MultipartFile.fromBytes(
        'profile_picture', profilePictureBytes,
        filename: fileName));
  }

  // Ajouter pièce d'identité unique si fournie
  if (identityDocument != null && identityDocument.existsSync()) {
    multiPartRequest.files.add(await MultipartFile.fromPath(
        'identity_document', identityDocument.path));
  } else if (identityDocumentBytes != null &&
      identityDocumentBytes.isNotEmpty) {
    String fileName = identityDocumentFileName ?? 'identity_document.jpg';
    multiPartRequest.files.add(MultipartFile.fromBytes(
        'identity_document', identityDocumentBytes,
        filename: fileName));
  }

  _log("Register Request: ${jsonEncode(multiPartRequest.fields)}");

  await sendMultiPartRequest(
    multiPartRequest,
    onSuccess: (response) {
      if (response is String && response.isJson()) {
        completer.complete(BaseResponseModel.fromJson(jsonDecode(response)));
      } else {
        completer.complete(BaseResponseModel(message: 'Inscription réussie'));
      }
    },
    onError: (error) {
      completer.completeError(error?.toString() ?? errorSomethingWentWrong);
    },
  );

  return completer.future;
}

/// Inscription d'un ouvrier via l'API Mison
/// POST /api/auth/register/artisan (multipart/form-data)
/// Champs requis: password, phone, first_name, last_name, service, profession_name, address
/// Champs optionnels: email, profile_picture (File ou bytes), experience_years, hourly_rate, daily_rate, city
/// Retourne un message, l'ouvrier doit vérifier son compte avec l'OTP
Future<BaseResponseModel> createArtisan(
  Map request, {
  File? profilePicture,
  Uint8List? profilePictureBytes,
  String? profilePictureFileName,
  File? identityDocument,
  Uint8List? identityDocumentBytes,
  String? identityDocumentFileName,
  File? identityDocumentBack,
  Uint8List? identityDocumentBackBytes,
  String? identityDocumentBackFileName,
  File? professionProof,
  Uint8List? professionProofBytes,
  String? professionProofFileName,
}) async {
  Completer<BaseResponseModel> completer = Completer();

  MultipartRequest multiPartRequest =
      await getMultiPartRequest('auth/register/artisan');

  // Récupération des champs avec les bons noms
  String email = request['email']?.toString().trim() ?? '';
  String password = request['password']?.toString() ?? '';
  String phone =
      request['phone']?.toString() ?? ''; // ✅ Changé: contact_number → phone
  String firstName = request['first_name']?.toString() ?? '';
  String lastName = request['last_name']?.toString() ?? '';
  String service =
      request['service']?.toString() ?? ''; // ✅ Changé: profession → service
  String professionName = request['profession_name']?.toString() ?? '';
  String address = request['address']?.toString() ?? '';

  // Validation des champs requis
  if (password.isEmpty ||
      phone.isEmpty ||
      firstName.isEmpty ||
      lastName.isEmpty ||
      service.isEmpty ||
      professionName.isEmpty ||
      address.isEmpty) {
    completer.completeError(language.requiredText);
    return completer.future;
  }

  // Profile picture (selfie) obligatoire pour ouvrier
  bool hasProfilePicture =
      (profilePicture != null && profilePicture.existsSync()) ||
          (profilePictureBytes != null && profilePictureBytes.isNotEmpty);
  if (!hasProfilePicture) {
    completer.completeError('La photo de profil est requise');
    return completer.future;
  }

  // Identity document (Recto) obligatoire
  bool hasIdentityDocument =
      (identityDocument != null && identityDocument.existsSync()) ||
          (identityDocumentBytes != null && identityDocumentBytes.isNotEmpty);
  if (!hasIdentityDocument) {
    completer.completeError('La pièce d\'identité (recto) est requise');
    return completer.future;
  }

  // Identity document (Verso) obligatoire
  bool hasIdentityDocumentBack =
      (identityDocumentBack != null && identityDocumentBack.existsSync()) ||
          (identityDocumentBackBytes != null && identityDocumentBackBytes.isNotEmpty);
  if (!hasIdentityDocumentBack) {
    completer.completeError('La pièce d\'identité (verso) est requise');
    return completer.future;
  }

  // Remplir les champs requis avec les bons noms
  if (email.isNotEmpty) multiPartRequest.fields['email'] = email;
  multiPartRequest.fields['password'] = password;
  multiPartRequest.fields['phone'] = phone;
  multiPartRequest.fields['first_name'] = firstName;
  multiPartRequest.fields['last_name'] = lastName;
  multiPartRequest.fields['service'] = service;
  multiPartRequest.fields['profession_name'] = professionName;
  multiPartRequest.fields['address'] = address;
  multiPartRequest.fields['experience_years'] = (request['experience_years'] ?? 0).toString();

  // Coordonnées GPS (optionnelles)
  multiPartRequest.fields['latitude'] = request['latitude']?.toString() ?? '';
  multiPartRequest.fields['longitude'] = request['longitude']?.toString() ?? '';

  // Champs complémentaires prestataire
  multiPartRequest.fields['age'] = request['age']?.toString() ?? '';
  multiPartRequest.fields['nationality'] = request['nationality']?.toString() ?? '';
  multiPartRequest.fields['education_level'] = request['education_level']?.toString() ?? '';
  multiPartRequest.fields['region'] = request['region']?.toString() ?? '';
  multiPartRequest.fields['department'] = request['department']?.toString() ?? '';
  multiPartRequest.fields['mobile_money_accounts'] = request['mobile_money_accounts']?.toString() ?? '';
  multiPartRequest.fields['join_whatsapp_community'] = request['join_whatsapp_community']?.toString() ?? '';
  multiPartRequest.fields['has_other_professions'] = request['has_other_professions']?.toString() ?? '';
  multiPartRequest.fields['other_professions'] = request['other_professions']?.toString() ?? '';

  // Ajouter photo de profil (profile_picture)
  if (profilePicture != null && profilePicture.existsSync()) {
    multiPartRequest.files.add(
        await MultipartFile.fromPath('profile_picture', profilePicture.path));
  } else if (profilePictureBytes != null && profilePictureBytes.isNotEmpty) {
    String fileName = profilePictureFileName ?? 'profile_picture.jpg';
    multiPartRequest.files.add(MultipartFile.fromBytes(
        'profile_picture', profilePictureBytes,
        filename: fileName));
  }

  // Pièce d'identité : recto (identity_document) et verso (identity_document_back),
  // chacun envoyé une seule fois.
  if (identityDocument != null && identityDocument.existsSync()) {
    multiPartRequest.files.add(await MultipartFile.fromPath(
        'identity_document', identityDocument.path));
  } else if (identityDocumentBytes != null &&
      identityDocumentBytes.isNotEmpty) {
    multiPartRequest.files.add(MultipartFile.fromBytes(
        'identity_document', identityDocumentBytes,
        filename: identityDocumentFileName ?? 'identity_document.jpg'));
  }
  if (identityDocumentBack != null && identityDocumentBack.existsSync()) {
    multiPartRequest.files.add(await MultipartFile.fromPath(
        'identity_document_back', identityDocumentBack.path));
  } else if (identityDocumentBackBytes != null &&
      identityDocumentBackBytes.isNotEmpty) {
    multiPartRequest.files.add(MultipartFile.fromBytes(
        'identity_document_back', identityDocumentBackBytes,
        filename: identityDocumentBackFileName ?? 'identity_document_back.jpg'));
  }

  // Ajouter preuve de profession (profession_proof) - optionnel
  if (professionProof != null && professionProof.existsSync()) {
    multiPartRequest.files.add(
        await MultipartFile.fromPath('profession_proof', professionProof.path));
  } else if (professionProofBytes != null && professionProofBytes.isNotEmpty) {
    String fileName = professionProofFileName ?? 'profession_proof.jpg';
    multiPartRequest.files.add(MultipartFile.fromBytes(
        'profession_proof', professionProofBytes,
        filename: fileName));
  }

  _log("Artisan Register Request Fields: ${jsonEncode(multiPartRequest.fields)}");
  _log("Artisan Register Request Files: ${multiPartRequest.files.length}");

  await sendMultiPartRequest(
    multiPartRequest,
    onSuccess: (response) {
      if (response is String && response.isJson()) {
        completer.complete(BaseResponseModel.fromJson(jsonDecode(response)));
      } else {
        completer.complete(
            BaseResponseModel(message: 'Inscription ouvrier réussie'));
      }
    },
    onError: (error) {
      completer.completeError(error?.toString() ?? errorSomethingWentWrong);
    },
  );

  return completer.future;
}

Future<LoginResponse> loginUser(Map request,
    {bool isSocialLogin = false}) async {
  try {
    LoginResponse res = LoginResponse.fromJson(await handleResponse(
        await buildHttpResponse(
            isSocialLogin ? 'auth/social-login' : 'auth/login',
            request: request,
            method: HttpMethodType.POST)));

    if (res.userData != null) {
      if (res.userData!.userType != USER_TYPE_USER &&
          res.userData!.userType != USER_TYPE_PROVIDER) {
        appStore.setLoading(false);
        throw language.lblNotValidUser;
      }
      if (res.userData!.status == 0) {
        appStore.setLoading(false);
        throw language.contactAdmin;
      }
    }
    return res;
  } on Exception catch (e) {
    throw e.toString();
  }
}

Future<LoginResponse> updateProfile(Map request) async {
  return LoginResponse.fromJson(await handleResponse(await buildHttpResponse(
      'update-profile',
      request: request,
      method: HttpMethodType.POST)));
}

Future<UserData> getUserDetail(int id, {bool forceUpdate = true}) async {
  DateTime currentTimeStamp = DateTime.timestamp();
  DateTime lastSyncedTimeStamp = DateTime.fromMillisecondsSinceEpoch(
      getIntAsync(LAST_USER_DETAILS_SYNCED_TIME));
  lastSyncedTimeStamp = lastSyncedTimeStamp.add(Duration(minutes: 5));

  if (!forceUpdate && lastSyncedTimeStamp.isAfter(currentTimeStamp)) {
    _log('User details was synced recently');

    /// Throw empty string so that in this case no toast message will be shown
    throw '';
  } else {
    var res = LoginResponse.fromJson(await handleResponse(
        await buildHttpResponse('user-detail?id=$id',
            method: HttpMethodType.GET)));

    if (res.userData != null) {
      await setValue(LAST_USER_DETAILS_SYNCED_TIME,
          DateTime.timestamp().millisecondsSinceEpoch);
      return res.userData!;
    } else {
      throw errorSomethingWentWrong;
    }
  }
}

/// Save user data from API response
Future<void> saveUserData(UserData data,
    {bool forceSyncAppConfigurations = true, String? refreshToken}) async {
  if (data.apiToken.validate().isNotEmpty)
    await appStore.setToken(data.apiToken!);
  if (refreshToken != null && refreshToken.isNotEmpty)
    await appStore.setRefreshToken(refreshToken);
  appStore.setLoggedIn(true);

  await appStore.setUserId(data.id.validate());
  await appStore.setUId(data.uid.validate());
  await appStore.setFirstName(data.firstName.validate());
  await appStore.setLastName(data.lastName.validate());
  await appStore.setUserEmail(data.email.validate());
  await appStore.setUserName(data.username.validate());
  await appStore.setCountryId(data.countryId.validate());
  await appStore.setStateId(data.stateId.validate());
  await appStore.setCityId(data.cityId.validate());
  await appStore.setContactNumber(data.contactNumber.validate());
  await appStore.setLoginType(data.loginType.validate(value: LOGIN_TYPE_USER));
  await appStore.setAddress(data.address.validate());

  await appStore.setUserProfile(data.profileImage.validate());
  await appStore.setReferralCode(data.referral_code.validate());
  if (data.userType.validate().isNotEmpty)
    await appStore.setUserType(data.userType.validate());
  await setValue(ACCOUNT_TYPE, data.userAccountType.validate());
  await setValue(COMPANY_NAME, data.companyName.validate());

  /// Subscribe Firebase Topic
  subscribeToFirebaseTopic();

  /// Token PushKit iOS — indispensable pour sonner app fermée
  syncVoipToken();

  /// Envoyer le FCM token au backend Mison
  FirebaseMessaging.instance.getToken().then((token) {
    _log('════════════════════════════════════════════');
    _log('FCM TOKEN: $token');
    _log('════════════════════════════════════════════');
    if (token != null) saveFcmTokenToBackend(token);
  }).catchError((e) { _log('FCM getToken error: $e'); return null; });

  // Sync new configurations for secret keys
  if (forceSyncAppConfigurations)
    await setValue(LAST_APP_CONFIGURATION_SYNCED_TIME, 0);
  getAppConfigurations();
}

Future<void> clearPreferences() async {
  ChatUnreadStore.clear();
  cachedDashboardResponse = null;
  cachedBookingList = null;
  cachedCategoryList = null;
  cachedBookingStatusDropdown = null;
  cachedHelpDeskListData = null;

  if (!getBoolAsync(IS_REMEMBERED)) {
    await appStore.setUserEmail('');
    await removeKey(IS_EMAIL_VERIFIED);
  }
  setValue(CURRENT_ADDRESS, '');
  await appStore.setCurrentLocation(false);

  /// Firebase Notification
  unsubscribeFirebaseTopic(appStore.userId);
  await removeKey(LOGIN_TYPE);

  // Changement de compte : rien de l'ancien compte (appel qui sonne, notification
  // non lue) ne doit rouvrir une de ses commandes une fois l'autre compte connecté.
  try {
    await FlutterCallkitIncoming.endAllCalls();
  } catch (_) {}
  try {
    await FlutterLocalNotificationsPlugin().cancelAll();
  } catch (_) {}
  await removeKey('outgoing_call_order_id');

  await appStore.setLoggedIn(false);
  await appStore.setFirstName('');
  await appStore.setLastName('');
  await appStore.setUserId(0);
  await appStore.setUserName('');
  await appStore.setContactNumber('');
  await appStore.setCountryId(0);
  await appStore.setStateId(0);
  await appStore.setUserProfile('');
  await appStore.setAddress('');
  await appStore.setCityId(0);
  await appStore.setUId('');
  await appStore.setLatitude(0.0);
  await appStore.setLongitude(0.0);
  await appStore.setToken('');
  await appStore.setRefreshToken('');
  await appStore.setLoginType('');
  await setValue(USER_PASSWORD, '');
  await removeKey(IS_SUBSCRIBED_FOR_PUSH_NOTIFICATION);

  try {
    FirebaseAuth.instance.signOut();
  } catch (e) {
    _log(e);
  }

  appStore.setUserWalletAmount();
}

Future<void> logout(BuildContext context) async {
  // Confirmation aux couleurs Mison
  if (!await showMisonLogoutSheet(context)) return;

  if (!await isNetworkAvailable()) {
    TopToast.show(message: errorInternetNotAvailable, type: TopToastType.error);
    return;
  }

  appStore.setLoading(true);
  logoutApi().catchError((e) => _log(e.toString()));

  await clearPreferences();
  if (cachedWalletHistoryList != null && cachedWalletHistoryList!.isNotEmpty) {
    cachedWalletHistoryList!.clear();
  }

  appStore.setLoading(false);
  TopToast.show(message: 'Vous êtes déconnecté.', type: TopToastType.success);
  SignInScreen().launch(context, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
}

Future<void> logoutApi() async {
  try {
    Map request = {'refresh': appStore.refreshToken};
    await handleResponse(await buildHttpResponse('auth/logout',
        request: request, method: HttpMethodType.POST));
  } catch (e) {
    // Continue logout even if API fails
    _log('Logout API error: $e');
  }
}

/// Change password - Requiert une session authentifiée
/// POST /api/auth/change-password avec { old_password, new_password }
Future<BaseResponseModel> changeUserPassword(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('auth/change-password',
          request: request, method: HttpMethodType.POST)));
}

/// Forgot password - Envoie un OTP par email
/// POST /api/auth/forgot-password avec { email }
Future<BaseResponseModel> forgotPassword(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('auth/forgot-password',
          request: request, method: HttpMethodType.POST)));
}

/// Reset password - Valide l'OTP et met à jour le mot de passe
/// POST /api/auth/reset-password avec { email, otp_code, new_password }
Future<BaseResponseModel> resetPassword(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('auth/reset-password',
          request: request, method: HttpMethodType.POST)));
}

/// Verify account with OTP
/// POST /api/auth/register/verify avec { email, otp_code }
Future<BaseResponseModel> verifyAccountOtp(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('auth/register/verify',
          request: request, method: HttpMethodType.POST)));
}

/// Vérifie si un email et/ou un numéro de téléphone existent déjà en base
/// GET /api/auth/check-availability?email=...&phone=...
/// Reponse back-end : { email?: { available: bool }, phone?: { available: bool } }
/// (une cle n'est presente que si le parametre correspondant a ete envoye)
/// Retourne { email_exists: bool, phone_exists: bool }
Future<Map<String, bool>> checkEmailPhoneAvailability({String? email, String? phone}) async {
  final Map<String, String> params = {};
  if (email != null && email.trim().isNotEmpty) params['email'] = email.trim();
  if (phone != null && phone.trim().isNotEmpty) params['phone'] = phone.trim();

  final String query = params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  final response = await handleResponse(await buildHttpResponse(
      'auth/check-availability${query.isNotEmpty ? '?$query' : ''}',
      method: HttpMethodType.GET));

  final emailData = response['email'];
  final phoneData = response['phone'];

  return {
    'email_exists': emailData is Map && emailData['available'] == false,
    'phone_exists': phoneData is Map && phoneData['available'] == false,
  };
}

/// Resend OTP
/// POST /api/auth/resend-otp?purpose=verification|password_reset avec { email }
Future<BaseResponseModel> resendOtp(Map request,
    {String purpose = 'verification'}) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('auth/resend-otp?purpose=$purpose',
          request: request, method: HttpMethodType.POST)));
}

/// Get current user profile
/// GET /api/auth/me
Future<UserData> getCurrentUserProfile() async {
  var response = await handleResponse(
      await buildHttpResponse('auth/me', method: HttpMethodType.GET));
  return UserData.fromMisonJson(response);
}

/// POST /api/auth/delete-account avec { password: PIN }
/// Anonymise le compte ; 409 si une commande est encore en cours.
Future<BaseResponseModel> deleteAccountCompletely(String pin) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('auth/delete-account',
          request: {'password': pin}, method: HttpMethodType.POST)));
}

//endregion

//endregion

//region Configurations Api
Future<void> getAppConfigurations(
    {bool isCurrentLocation = false, double? lat, double? long}) async {
  DateTime currentTimeStamp = DateTime.timestamp();
  DateTime lastSyncedTimeStamp = DateTime.fromMillisecondsSinceEpoch(
      getIntAsync(LAST_APP_CONFIGURATION_SYNCED_TIME));
  lastSyncedTimeStamp = lastSyncedTimeStamp.add(Duration(minutes: 5));

  if (lastSyncedTimeStamp.isAfter(currentTimeStamp)) {
    _log('App Configurations was synced recently');
  } else {
    // Utilisation de valeurs par défaut au lieu de l'appel API
    // TODO: Implémenter l'endpoint /api/configurations sur votre backend si vous avez besoin de configs dynamiques
    await setDefaultAppConfigurations();
    await setValue(LAST_APP_CONFIGURATION_SYNCED_TIME,
        DateTime.timestamp().millisecondsSinceEpoch);
  }
}

//endregion

Future<num> getUserWalletBalance() async {
  try {
    var res = WalletResponse.fromJson(await handleResponse(
        await buildHttpResponse('user-wallet-balance',
            method: HttpMethodType.GET)));

    return res.balance.validate();
  } catch (e) {
    appStore.setLoading(false);
    _log(e);
    return appStore.userWalletAmount;
  }
}

//endregion

//endregion

//region Category Api

//endregion

//endregion

//endregion

Future<BaseResponseModel> handymanRating(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('save-handyman-rating',
          request: request, method: HttpMethodType.POST)));
}
//endregion

Future<List<BookingStatusResponse>> bookingStatus(
    {required List<BookingStatusResponse> list}) async {
  Iterable res = await (handleResponse(
      await buildHttpResponse('booking-status', method: HttpMethodType.GET)));
  list = res.map((e) => BookingStatusResponse.fromJson(e)).toList();
  cachedBookingStatusDropdown = list;

  return list.validate();
}
//endregion

//endregion

//region Notification Api
/// GET /api/notifications - Historique des notifications Mison (+ non lues)
Future<MisonNotificationResponse> getMisonNotifications() async {
  final response = await buildHttpResponse('notifications', method: HttpMethodType.GET);
  final res = MisonNotificationResponse.fromJson(await handleResponse(response));
  appStore.setUnreadCount(res.unreadCount);
  return res;
}

/// POST /api/notifications/read - Marque une notification ([id]) ou toutes comme lues
Future<void> markMisonNotificationsRead({String? id}) async {
  final response = await buildHttpResponse(
    'notifications/read',
    method: HttpMethodType.POST,
    request: id != null ? {'id': id} : {},
  );
  await handleResponse(response);
}

//endregion

//endregion

//endregion

Future<BaseResponseModel> addWishList(request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('save-favourite',
          method: HttpMethodType.POST, request: request)));
}

Future<BaseResponseModel> removeWishList(request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('delete-favourite',
          method: HttpMethodType.POST, request: request)));
}

//endregion

//endregion

//endregion

//region Get My post job

//endregion

//endregion

//endregion

//endregion

//endregion

//endregion
// region Loyalty
Future<BaseResponseModel> checkReferralCode(String referralCode) async {
  String encodedCode = Uri.encodeComponent(referralCode.trim());
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('check-referral?referral_code=$encodedCode',
          method: HttpMethodType.POST)));
}

//endregion

// region Mison API - Orders & Services
// Documentation: BACKEND_API_README.md
// Base URL: https://api.mison.app/api/

/// GET /api/services - Liste des services disponibles
MisonServicesResponse? _cachedServices;
DateTime? _servicesCachedAt;

/// Dernière liste reçue, gardée sur le téléphone : affichée hors connexion
/// (les images suivent, via le cache disque de CachedNetworkImage).
const _kServicesCacheKey = 'mison_services_cache';

Future<MisonServicesResponse> getMisonServices({bool forceRefresh = false}) async {
  final now = DateTime.now();
  if (!forceRefresh &&
      _cachedServices != null &&
      _servicesCachedAt != null &&
      now.difference(_servicesCachedAt!) < const Duration(minutes: 10)) {
    return _cachedServices!;
  }
  try {
    final response = await buildHttpResponse('services', method: HttpMethodType.GET);
    final body = await handleResponse(response);
    _cachedServices = MisonServicesResponse.fromJson(body);
    _servicesCachedAt = now;
    if ((_cachedServices!.data ?? []).isNotEmpty) setValue(_kServicesCacheKey, jsonEncode(body));
    return _cachedServices!;
  } catch (e) {
    if (_cachedServices != null) return _cachedServices!;
    // Hors connexion (ou serveur injoignable) : la liste enregistrée.
    final saved = getStringAsync(_kServicesCacheKey);
    if (saved.isNotEmpty) {
      try {
        _cachedServices = MisonServicesResponse.fromJson(jsonDecode(saved) as Map<String, dynamic>);
        return _cachedServices!;
      } catch (_) {}
    }
    throw e;
  }
}

/// GET /api/orders - Liste des commandes du client authentifié
/// @param status - Filtre optionnel: PENDING, ASSIGNED, ACCEPTED, IN_PROGRESS, COMPLETED, CANCELLED, REJECTED
Future<MisonOrderResponse> getMisonOrders({String? status}) async {
  try {
    String endpoint = 'orders';
    if (status != null && status.isNotEmpty) {
      endpoint += '?status=$status';
    }
    final response = await buildHttpResponse(endpoint, method: HttpMethodType.GET);
    final result = MisonOrderResponse.fromJson(await handleResponse(response));
    // Prestataire : rappel « Commencer » tant qu'il est arrivé sans commencer
    // (liste complète seulement, pour retirer aussi les rappels périmés).
    if (status == null || status.isEmpty) StartReminder.syncOrders(result.data ?? []);
    return result;
  } catch (e) {
    throw e;
  }
}

/// GET /api/orders/{id} - Détails d'une commande spécifique
/// GET / POST /api/artisans/availability — bouton « Disponible / Indisponible »
/// de l'accueil du prestataire. Retourne l'état enregistré sur le serveur.
Future<bool> getArtisanAvailability() async {
  final body = await handleResponse(await buildHttpResponse('artisans/availability', method: HttpMethodType.GET));
  return body['data']?['is_available'] != false;
}

Future<bool> setArtisanAvailability(bool isAvailable) async {
  final body = await handleResponse(await buildHttpResponse(
    'artisans/availability',
    request: {'is_available': isAvailable},
    method: HttpMethodType.POST,
  ));
  _orderChanged(); // commandes disponibles affichées / masquées
  return body['data']?['is_available'] != false;
}

/// POST /api/artisans/location — position du prestataire libre (app ouverte),
/// affichée aux clients qui cherchent un prestataire.
Future<void> postArtisanLocation(double latitude, double longitude) async {
  await handleResponse(await buildHttpResponse(
    'artisans/location',
    request: {'latitude': latitude, 'longitude': longitude},
    method: HttpMethodType.POST,
  ));
}

/// GET /api/orders/{id}/nearby-artisans — écran de recherche du client :
/// positions approximatives des prestataires disponibles autour de lui.
Future<Map<String, dynamic>> getOrderNearbyArtisans(String orderId) async {
  final response = await buildHttpResponse('orders/$orderId/nearby-artisans', method: HttpMethodType.GET);
  final body = await handleResponse(response);
  return (body is Map && body['data'] is Map) ? Map<String, dynamic>.from(body['data']) : <String, dynamic>{};
}

/// Action réussie sur une commande (bouton) : toutes les pages ouvertes
/// (détail, « Mes commandes », pages et accueil du prestataire) se mettent à
/// jour tout de suite, sans attendre la notification ni l'actualisation
/// automatique. [orderId] null : toutes les commandes sont concernées.
void _orderChanged([String? orderId]) => OrderEvents.emit(orderId);

Future<MisonOrderDetailResponse> getMisonOrderDetail(String orderId) async {
  try {
    final response = await buildHttpResponse('orders/$orderId', method: HttpMethodType.GET);
    final result = MisonOrderDetailResponse.fromJson(await handleResponse(response));
    StartReminder.syncOrder(result.data);
    return result;
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/cancel - Annuler une commande
/// [reason] : motif facultatif choisi par le client (envoyé seulement s'il est renseigné).
Future<void> cancelMisonOrder(String orderId, {String? reason}) async {
  try {
    final response = await buildHttpResponse(
      'orders/$orderId/cancel',
      method: HttpMethodType.POST,
      request: (reason != null && reason.isNotEmpty) ? {'reason': reason} : null,
    );
    await handleResponse(response);
    _orderChanged(orderId);
  } catch (e) {
    throw e;
  }
}

/// POST /api/auth/fcm-token - Enregistrer le token FCM de l'appareil
/// Le backend utilise ce token pour envoyer des notifications push ciblées
Future<void> saveFcmTokenToBackend(String fcmToken) async {
  try {
    await buildHttpResponse(
      'auth/fcm-token',
      method: HttpMethodType.POST,
      request: {'fcm_token': fcmToken},
    );
  } catch (e) {
    _log('saveFcmToken error: $e');
  }
}

/// POST /api/orders - Créer une nouvelle commande
/// @param request - Contient service (UUID), description, service_date (ISO8601), service_address
Future<MisonOrderDetailResponse> createMisonOrder(MisonCreateOrderRequest request) async {
  try {
    final response = await buildHttpResponse(
      'orders',
      request: request.toJson(),
      method: HttpMethodType.POST,
    );
    final created = MisonOrderDetailResponse.fromJson(await handleResponse(response));
    _orderChanged(created.data?.id);
    return created;
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/accept - Artisan accepte une commande (PENDING → ACCEPTED)
Future<MisonActionResponse> artisanAcceptOrder(String orderId) async {
  try {
    final response = await buildHttpResponse(
      'orders/$orderId/accept',
      method: HttpMethodType.POST,
    );
    final result = MisonActionResponse.fromJson(await handleResponse(response));
    _orderChanged(orderId);
    return result;
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/artisan-decision - Décision de l'artisan sur une commande (REJECT)
Future<MisonActionResponse> artisanDecisionMisonOrder(String orderId, String decision) async {
  try {
    final request = MisonArtisanDecisionRequest(decision: decision);
    final response = await buildHttpResponse(
      'orders/$orderId/artisan-decision',
      request: request.toJson(),
      method: HttpMethodType.POST,
    );
    final result = MisonActionResponse.fromJson(await handleResponse(response));
    _orderChanged(orderId);
    return result;
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/rate - Noter une commande complétée
/// @param orderId - UUID de la commande
/// @param rating - Note de 1 à 5
/// @param review - Commentaire libre, facultatif (peut être vide)
Future<MisonActionResponse> rateMisonOrder(String orderId, int rating, String review) async {
  try {
    final request = MisonRateOrderRequest(rating: rating, review: review);
    final response = await buildHttpResponse(
      'orders/$orderId/rate',
      request: request.toJson(),
      method: HttpMethodType.POST,
    );
    final result = MisonActionResponse.fromJson(await handleResponse(response));
    _orderChanged(orderId);
    return result;
  } catch (e) {
    throw e;
  }
}

/// GET /api/worker-requests - Liste des demandes d'ouvrier du client authentifié
Future<MisonWorkerRequestResponse> getWorkerRequests() async {
  try {
    final response = await buildHttpResponse('worker-requests', method: HttpMethodType.GET);
    return MisonWorkerRequestResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
  }
}

/// POST /api/worker-requests/{id}/cancel - Annuler une demande d'ouvrier
Future<void> cancelWorkerRequest(String requestId) async {
  try {
    final response = await buildHttpResponse('worker-requests/$requestId/cancel', method: HttpMethodType.POST);
    await handleResponse(response);
    _orderChanged();
  } catch (e) {
    throw e;
  }
}

/// POST /api/worker-requests - Créer une demande d'ouvrier
Future<MisonOrderDetailResponse> createWorkerRequest(MisonWorkerRequestModel request) async {
  try {
    final response = await buildHttpResponse(
      'worker-requests',
      request: request.toJson(),
      method: HttpMethodType.POST,
    );
    _log('createWorkerRequest → ${request.toJson()}');
    final res = MisonOrderDetailResponse.fromJson(await handleResponse(response));
    _log('createWorkerRequest ← ${res.message}');
    _orderChanged();
    return res;
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/request-invoice - Demande de facture : postée dans le
/// chat support du client, qui y recevra la facture.
Future<MisonActionResponse> requestOrderInvoice(String orderId) async {
  final response = await buildHttpResponse('orders/$orderId/request-invoice', method: HttpMethodType.POST);
  return MisonActionResponse.fromJson(await handleResponse(response));
}

/// POST /api/orders/{id}/call-log - Fin d'un appel (envoyée par l'appelant) :
/// l'appel s'affiche dans la conversation. [outcome] : completed / missed / declined.
Future<void> logOrderCall(String orderId, {required String outcome, int durationSeconds = 0}) async {
  try {
    final response = await buildHttpResponse('orders/$orderId/call-log',
        method: HttpMethodType.POST,
        request: {'outcome': outcome, 'duration_seconds': durationSeconds});
    await handleResponse(response);
  } catch (e) {
    _log('logOrderCall: $e');
  }
}

/// POST /api/orders/{id}/depart - L'ouvrier part chez le client (mini-carte)
Future<MisonActionResponse> artisanDepart(String orderId) async {
  final response = await buildHttpResponse('orders/$orderId/depart', method: HttpMethodType.POST);
  final result = MisonActionResponse.fromJson(await handleResponse(response));
    _orderChanged(orderId);
    return result;
}

/// POST /api/orders/{id}/arrive - L'ouvrier est arrivé chez le client
Future<MisonActionResponse> artisanArrive(String orderId) async {
  final response = await buildHttpResponse('orders/$orderId/arrive', method: HttpMethodType.POST);
  final result = MisonActionResponse.fromJson(await handleResponse(response));
    _orderChanged(orderId);
    return result;
}

/// POST /api/orders/{id}/start - Artisan démarre une commande (ACCEPTED → IN_PROGRESS)
Future<MisonActionResponse> artisanStartOrder(String orderId) async {
  try {
    final response = await buildHttpResponse(
      'orders/$orderId/start',
      method: HttpMethodType.POST,
    );
    final result = MisonActionResponse.fromJson(await handleResponse(response));
    StartReminder.cancel(orderId); // prestation commencée : plus de rappel
    _orderChanged(orderId);
    return result;
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/complete - Artisan termine une commande (IN_PROGRESS → COMPLETED)
Future<MisonActionResponse> artisanCompleteOrder(String orderId) async {
  try {
    final response = await buildHttpResponse(
      'orders/$orderId/complete',
      method: HttpMethodType.POST,
    );
    final result = MisonActionResponse.fromJson(await handleResponse(response));
    _orderChanged(orderId);
    return result;
  } catch (e) {
    throw e;
  }
}

/// GET /api/artisans - Liste des artisans disponibles
Future<MisonArtisanListResponse> getMisonArtisans() async {
  try {
    final response = await buildHttpResponse('artisans', method: HttpMethodType.GET);
    return MisonArtisanListResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/set-realization-fee - Le prestataire définit les frais de prestation (IN_PROGRESS → AWAITING_REALIZATION_PAYMENT)
Future<MisonActionResponse> setRealizationFee(String orderId, num amount) async {
  try {
    final response = await buildHttpResponse(
      'orders/$orderId/set-realization-fee',
      method: HttpMethodType.POST,
      request: {'realization_fee': amount},
    );
    final result = MisonActionResponse.fromJson(await handleResponse(response));
    _orderChanged(orderId);
    return result;
  } catch (e) {
    throw e;
  }
}

/// POST /api/payments/checkout - Client initie un paiement Wave pour une commande
Future<MisonActionResponse> paymentCheckout(String orderId) async {
  try {
    final response = await buildHttpResponse(
      'payments/checkout',
      method: HttpMethodType.POST,
      // Wave n'accepte que des URL https : /payment/success et /payment/error
      // du back-end redirigent vers mison://payment/… pour rouvrir l'app.
      // DOMAIN_URL = le serveur que l'app utilise (dev ou prod).
      // Le back-end y ajoute ?order_id=….
      request: {
        'order_id': orderId,
        'success_url': '$DOMAIN_URL/payment/success',
        'error_url': '$DOMAIN_URL/payment/error',
      },
    );
    return MisonActionResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
  }
}

/// POST /api/payments/checkout/orange - Initie un paiement Orange Money
Future<MisonActionResponse> paymentCheckoutOrange(String orderId) async {
  try {
    final response = await buildHttpResponse(
      'payments/checkout/orange',
      method: HttpMethodType.POST,
      request: {
        'order_id': orderId,
        'success_url': 'mison://payment/success?order_id=$orderId',
        'cancel_url': 'mison://payment/error?order_id=$orderId',
      },
    );
    return MisonActionResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/call-token - Initie ou rejoint un appel VoIP Agora
/// [notify] : false quand on rejoint un appel entrant — évite de refaire
/// sonner l'appelant.
Future<MisonCallTokenResponse> getCallToken(String orderId, {bool notify = true}) async {
  try {
    final response = await buildHttpResponse(
      'orders/$orderId/call-token',
      method: HttpMethodType.POST,
      request: {'notify': notify},
    );
    return MisonCallTokenResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
  }
}

/// Renvoie le token FCM courant au backend.
/// Appelé au démarrage : un token régénéré (réinstallation, restauration,
/// mise à jour système) rend l'ancien inutilisable côté serveur.
Future<void> refreshPushTokens() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) await saveFcmTokenToBackend(token);
  } catch (e) {
    _log('refreshPushTokens error: $e');
  }
}

/// POST /api/auth/voip-token - Token PushKit iOS
/// Nécessaire pour recevoir un appel quand l'app est fermée sur iOS.
Future<void> saveVoipTokenToBackend(String voipToken) async {
  try {
    await buildHttpResponse(
      'auth/voip-token',
      method: HttpMethodType.POST,
      request: {'voip_token': voipToken},
    );
  } catch (e) {
    _log('saveVoipToken error: $e');
  }
}

//endregion Mison API

/// Journaux de ce fichier : données sensibles toujours masquées (jetons,
/// codes, noms, numéros), voir log_redact.dart.
void _log(Object? value) => nb_log.log(redactForLog(value));
