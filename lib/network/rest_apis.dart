import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/mock_data.dart';
import 'package:booking_system_flutter/model/base_response_model.dart';
import 'package:booking_system_flutter/model/booking_data_model.dart';
import 'package:booking_system_flutter/model/booking_detail_model.dart';
import 'package:booking_system_flutter/model/booking_list_model.dart';
import 'package:booking_system_flutter/model/booking_status_model.dart';
import 'package:booking_system_flutter/model/category_model.dart';
import 'package:booking_system_flutter/model/city_list_model.dart';
import 'package:booking_system_flutter/model/country_list_model.dart';
import 'package:booking_system_flutter/model/dashboard_model.dart';
import 'package:booking_system_flutter/model/get_my_post_job_list_response.dart';
import 'package:booking_system_flutter/model/login_model.dart';
import 'package:booking_system_flutter/model/notification_model.dart';
import 'package:booking_system_flutter/model/post_job_detail_response.dart';
import 'package:booking_system_flutter/model/provider_info_response.dart';
import 'package:booking_system_flutter/model/provider_list_model.dart';
import 'package:booking_system_flutter/model/service_data_model.dart';
import 'package:booking_system_flutter/model/service_detail_response.dart';
import 'package:booking_system_flutter/model/service_response.dart';
import 'package:booking_system_flutter/model/service_review_response.dart';
import 'package:booking_system_flutter/model/shop_model.dart';
import 'package:booking_system_flutter/model/state_list_model.dart';
import 'package:booking_system_flutter/model/user_data_model.dart';
import 'package:booking_system_flutter/model/user_wallet_history.dart';
import 'package:booking_system_flutter/model/verify_transaction_response.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/model_keys.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:nb_utils/nb_utils.dart';

import '../model/bank_list_response.dart';
import '../model/coupon_list_model.dart';
import '../model/payment_gateway_response.dart';
import '../model/payment_list_reasponse.dart';
import '../model/update_location_response.dart';
import '../model/wallet_response.dart';
import '../model/zone_model.dart';
import '../model/mison_order_model.dart';
import '../model/mison_service_model.dart';
import '../screens/referral_loyalty_points/model/loyalty_history_model.dart';
import '../utils/app_configuration.dart';
import '../utils/firebase_messaging_utils.dart';

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

  // Champs requis
  multiPartRequest.fields['email'] = request['email']?.toString() ?? '';
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

  log("Register Request: ${jsonEncode(multiPartRequest.fields)}");

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

/// Inscription d'un artisan via l'API Mison
/// POST /api/auth/register/artisan (multipart/form-data)
/// Champs requis: email, password, phone, first_name, last_name
/// Champs optionnels: profile_picture (File ou bytes), profession, experience_years, hourly_rate, daily_rate, bio, address, city
/// Retourne un message, l'artisan doit vérifier son compte avec l'OTP
Future<BaseResponseModel> createArtisan(
  Map request, {
  File? profilePicture,
  Uint8List? profilePictureBytes,
  String? profilePictureFileName,
  File? identityDocument,
  Uint8List? identityDocumentBytes,
  String? identityDocumentFileName,
  File? professionProof,
  Uint8List? professionProofBytes,
  String? professionProofFileName,
}) async {
  Completer<BaseResponseModel> completer = Completer();

  MultipartRequest multiPartRequest =
      await getMultiPartRequest('auth/register/artisan');

  // Récupération des champs avec les bons noms
  String email = request['email']?.toString() ?? '';
  String password = request['password']?.toString() ?? '';
  String phone =
      request['phone']?.toString() ?? ''; // ✅ Changé: contact_number → phone
  String firstName = request['first_name']?.toString() ?? '';
  String lastName = request['last_name']?.toString() ?? '';
  String service =
      request['service']?.toString() ?? ''; // ✅ Changé: profession → service
  String experienceYears = request['experience_years']?.toString() ?? '';
  String bio = request['bio']?.toString() ?? '';
  String address = request['address']?.toString() ?? '';

  // Champs optionnels
  String hourlyRate = request['hourly_rate']?.toString() ?? '';
  String dailyRate = request['daily_rate']?.toString() ?? '';

  // Validation des champs requis
  if (email.isEmpty ||
      password.isEmpty ||
      phone.isEmpty ||
      firstName.isEmpty ||
      lastName.isEmpty ||
      service.isEmpty ||
      experienceYears.isEmpty ||
      bio.isEmpty ||
      address.isEmpty) {
    completer.completeError(language.requiredText);
    return completer.future;
  }

  // Profile picture (selfie) obligatoire pour artisan
  bool hasProfilePicture =
      (profilePicture != null && profilePicture.existsSync()) ||
          (profilePictureBytes != null && profilePictureBytes.isNotEmpty);
  if (!hasProfilePicture) {
    completer.completeError('La photo de profil est requise');
    return completer.future;
  }

  // Identity document (single file) obligatoire
  bool hasIdentityDocument =
      (identityDocument != null && identityDocument.existsSync()) ||
          (identityDocumentBytes != null && identityDocumentBytes.isNotEmpty);
  if (!hasIdentityDocument) {
    completer.completeError('La pièce d\'identité est requise');
    return completer.future;
  }

  // Remplir les champs requis avec les bons noms
  multiPartRequest.fields['email'] = email;
  multiPartRequest.fields['password'] = password;
  multiPartRequest.fields['phone'] = phone; // ✅ phone au lieu de contact_number
  multiPartRequest.fields['first_name'] = firstName;
  multiPartRequest.fields['last_name'] = lastName;
  multiPartRequest.fields['service'] =
      service; // ✅ service au lieu de profession
  multiPartRequest.fields['experience_years'] = experienceYears;
  multiPartRequest.fields['bio'] = bio;
  multiPartRequest.fields['address'] = address;

  // Ajouter les champs optionnels
  if (hourlyRate.isNotEmpty) {
    multiPartRequest.fields['hourly_rate'] = hourlyRate;
  }
  if (dailyRate.isNotEmpty) {
    multiPartRequest.fields['daily_rate'] = dailyRate;
  }

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

  // Ajouter pièce d'identité (identity_document)
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

  log("Artisan Register Request Fields: ${jsonEncode(multiPartRequest.fields)}");
  log("Artisan Register Request Files: ${multiPartRequest.files.length}");

  await sendMultiPartRequest(
    multiPartRequest,
    onSuccess: (response) {
      if (response is String && response.isJson()) {
        completer.complete(BaseResponseModel.fromJson(jsonDecode(response)));
      } else {
        completer.complete(
            BaseResponseModel(message: 'Inscription artisan réussie'));
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
      if (res.userData!.userType != USER_TYPE_USER) {
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
    log('User details was synced recently');

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
  await setValue(ACCOUNT_TYPE, data.userAccountType.validate());
  await setValue(COMPANY_NAME, data.companyName.validate());

  /// Subscribe Firebase Topic
  subscribeToFirebaseTopic();

  // Sync new configurations for secret keys
  if (forceSyncAppConfigurations)
    await setValue(LAST_APP_CONFIGURATION_SYNCED_TIME, 0);
  getAppConfigurations();
}

Future<void> clearPreferences() async {
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
    print(e);
  }

  appStore.setUserWalletAmount();
}

Future<void> logout(BuildContext context) async {
  return showInDialog(
    context,
    contentPadding: EdgeInsets.zero,
    builder: (p0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(logout_image, width: context.width(), fit: BoxFit.cover),
          32.height,
          Text(language.lblLogoutTitle, style: boldTextStyle(size: 18)),
          16.height,
          Text(language.lblLogoutSubTitle, style: secondaryTextStyle()),
          28.height,
          Row(
            children: [
              AppButton(
                elevation: 0,
                shapeBorder: RoundedRectangleBorder(
                  borderRadius: radius(defaultAppButtonRadius),
                  side: BorderSide(color: viewLineColor),
                ),
                child: Text(language.lblNo, style: boldTextStyle()),
                onTap: () {
                  finish(context);
                },
              ).expand(),
              16.width,
              AppButton(
                child:
                    Text(language.lblYes, style: boldTextStyle(color: white)),
                color: primaryColor,
                elevation: 0,
                onTap: () async {
                  finish(context);

                  if (await isNetworkAvailable()) {
                    appStore.setLoading(true);

                    logoutApi().then((value) async {
                      //
                    }).catchError((e) {
                      log(e.toString());
                    });

                    await clearPreferences();
                    if (cachedWalletHistoryList != null &&
                        cachedWalletHistoryList!.isNotEmpty)
                      cachedWalletHistoryList!.clear();

                    appStore.setLoading(false);
                    toast("Your Account has logged out successfully");
                    SignInScreen().launch(context,
                        isNewTask: true,
                        pageRouteAnimation: PageRouteAnimation.Fade);
                  } else {
                    toast(errorInternetNotAvailable);
                  }
                },
              ).expand(),
            ],
          ),
        ],
      ).paddingSymmetric(horizontal: 16, vertical: 24);
    },
  );
}

Future<void> logoutApi() async {
  try {
    Map request = {'refresh': appStore.refreshToken};
    await handleResponse(await buildHttpResponse('auth/logout',
        request: request, method: HttpMethodType.POST));
  } catch (e) {
    // Continue logout even if API fails
    log('Logout API error: $e');
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

Future<BaseResponseModel> deleteAccountCompletely() async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('delete-user-account',
          request: {}, method: HttpMethodType.POST)));
}

Future<VerificationModel> verifyUserEmail(String userEmail) async {
  Map<String, dynamic> request = {'email': userEmail};
  return VerificationModel.fromJson(await handleResponse(
      await buildHttpResponse('user-email-verify',
          request: request, method: HttpMethodType.POST)));
}

//endregion

//region Country Api
Future<List<CountryListResponse>> getCountryList() async {
  Iterable res = await (handleResponse(
      await buildHttpResponse('country-list', method: HttpMethodType.POST)));
  return res.map((e) => CountryListResponse.fromJson(e)).toList();
}

Future<List<StateListResponse>> getStateList(Map request) async {
  Iterable res = await (handleResponse(await buildHttpResponse('state-list',
      request: request, method: HttpMethodType.POST)));
  return res.map((e) => StateListResponse.fromJson(e)).toList();
}

Future<List<CityListResponse>> getCityList(Map request) async {
  Iterable res = await (handleResponse(await buildHttpResponse('city-list',
      request: request, method: HttpMethodType.POST)));
  return res.map((e) => CityListResponse.fromJson(e)).toList();
}
//endregion

//region Configurations Api
Future<void> getAppConfigurations(
    {bool isCurrentLocation = false, double? lat, double? long}) async {
  DateTime currentTimeStamp = DateTime.timestamp();
  DateTime lastSyncedTimeStamp = DateTime.fromMillisecondsSinceEpoch(
      getIntAsync(LAST_APP_CONFIGURATION_SYNCED_TIME));
  lastSyncedTimeStamp = lastSyncedTimeStamp.add(Duration(minutes: 5));

  if (lastSyncedTimeStamp.isAfter(currentTimeStamp)) {
    log('App Configurations was synced recently');
  } else {
    // Utilisation de valeurs par défaut au lieu de l'appel API
    // TODO: Implémenter l'endpoint /api/configurations sur votre backend si vous avez besoin de configs dynamiques
    await setDefaultAppConfigurations();
    await setValue(LAST_APP_CONFIGURATION_SYNCED_TIME,
        DateTime.timestamp().millisecondsSinceEpoch);
  }
}

//endregion

//region User Api
Future<DashboardResponse> userDashboard(
    {bool isCurrentLocation = false, double? lat, double? long}) async {
  Completer<DashboardResponse> completer = Completer();

  // L'API Mison n'a pas d'endpoint dashboard-detail
  // On retourne une réponse minimale - les services sont chargés séparément via MisonServicesDashboardComponent
  await Future.delayed(const Duration(milliseconds: 100));
  
  final dashboardResponse = DashboardResponse(
    category: [],
    service: [],
    featuredServices: [],
    slider: [],
    promotionalBanner: [],
    provider: [],
    shops: [],
    notificationUnreadCount: 0,
    isEmailVerified: 1,
    referralRule: false,
  );
  
  appStore.setLoading(false);
  cachedDashboardResponse = dashboardResponse;
  setValue(IS_EMAIL_VERIFIED, dashboardResponse.isEmailVerified.getBoolInt());
  appStore.setUnreadCount(dashboardResponse.notificationUnreadCount.validate());
  getAppConfigurations();
  completer.complete(dashboardResponse);
  return completer.future;
}

Future<num> getUserWalletBalance() async {
  try {
    var res = WalletResponse.fromJson(await handleResponse(
        await buildHttpResponse('user-wallet-balance',
            method: HttpMethodType.GET)));

    return res.balance.validate();
  } catch (e) {
    appStore.setLoading(false);
    log(e);
    return appStore.userWalletAmount;
  }
}

Future<List<WalletDataElement>> getUserWalletHistory(
  int page, {
  var perPage = PER_PAGE_ITEM,
  required List<WalletDataElement> walletDataList,
  Function(bool)? lastPageCallBack,
  Function(num)? availableBalance,
}) async {
  appStore.setLoading(true);
  try {
    var res = UserWalletHistoryResponse.fromJson(await handleResponse(
        await buildHttpResponse(
            'wallet-history?per_page=$perPage&page=$page&orderby=desc',
            method: HttpMethodType.GET)));

    if (page == 1) walletDataList.clear();
    walletDataList.addAll(res.data.validate());
    if (res.availableBalance != null) {
      availableBalance?.call(res.availableBalance ?? 0);
    }
    lastPageCallBack?.call(res.data.validate().length != PER_PAGE_ITEM);
    cachedWalletHistoryList = walletDataList;
    appStore.setLoading(false);
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }

  return walletDataList;
}

Future<BaseResponseModel> walletTopUp(Map req) async {
  // Delay is for showing loader again after loader was hidden from payment gateway
  await 100.milliseconds.delay;
  appStore.setLoading(true);
  try {
    var res = BaseResponseModel.fromJson(await handleResponse(
        await buildHttpResponse('wallet-top-up',
            method: HttpMethodType.POST, request: req)));

    await appStore.setUserWalletAmount();

    toast(language.yourWalletIsUpdated);
    appStore.setLoading(false);

    return res;
  } catch (e) {
    log(e);
    appStore.setLoading(false);
    toast(e.toString());
    throw e;
  }
}
//endregion

//region Service Api
Future<ServiceDetailResponse> getServiceDetails({
  required int serviceId,
  int? customerId,
  bool fromBooking = false,
}) async {
  if (fromBooking) {
    toast(language.pleaseWait);
  }
  String params = '';
  if (appStore.isCurrentLocation &&
      getDoubleAsync(LATITUDE) > 0 &&
      getDoubleAsync(LONGITUDE) > 0) {
    params =
        "?latitude=${getDoubleAsync(LATITUDE)}&longitude=${getDoubleAsync(LONGITUDE)}";
  }
  Map request = {
    CommonKeys.serviceId: serviceId,
    if (appStore.isLoggedIn) CommonKeys.customerId: customerId
  };
  try {
    var res = ServiceDetailResponse.fromJson(await handleResponse(
        await buildHttpResponse(
            'service-detail${params.isNotEmpty ? params : ''}',
            request: request,
            method: HttpMethodType.POST)));

    appStore.setLoading(false);
    return res;
  } catch (e) {
    appStore.setLoading(false);

    throw e;
  }
}

Future<List<ServiceData>> searchServiceAPI({
  String categoryId = '',
  String providerId = '',
  String isPriceMin = '',
  String isPriceMax = '',
  String ratingId = '',
  String search = '',
  String latitude = '',
  String longitude = '',
  String isFeatured = '',
  String subCategory = '',
  int isZoneId = 0,
  int page = 1,
  required List<ServiceData> list,
  Function(bool)? lastPageCallBack,
  String shopId = '',
}) async {
  // Always get fallback location if current location is enabled
  String finalLatitude = latitude;
  String finalLongitude = longitude;

  if (appStore.isCurrentLocation &&
      getDoubleAsync(LATITUDE) > 0 &&
      getDoubleAsync(LONGITUDE) > 0) {
    finalLatitude = getDoubleAsync(LATITUDE).toString();
    finalLongitude = getDoubleAsync(LONGITUDE).toString();
  }

  // Construct query parameters
  String categoryIds = categoryId.isNotEmpty ? 'category_id=$categoryId&' : '';
  String searchPara = search.isNotEmpty ? 'search=$search&' : '';
  String providerIds = providerId.isNotEmpty ? 'provider_id=$providerId&' : '';
  String isPriceMinPara =
      isPriceMin.isNotEmpty ? 'is_price_min=$isPriceMin&' : '';
  String isPriceMaxPara =
      isPriceMax.isNotEmpty ? 'is_price_max=$isPriceMax&' : '';
  String ratingPara = ratingId.isNotEmpty ? 'is_rating=$ratingId&' : '';
  String latitudes = 'latitude=$finalLatitude&'; // Always included
  String longitudes = 'longitude=$finalLongitude&'; // Always included
  String isFeatures = isFeatured.isNotEmpty ? 'is_featured=$isFeatured&' : '';
  String subCategorys = subCategory.validate().isNotEmpty
      ? subCategory != "-1"
          ? 'subcategory_id=$subCategory&'
          : ''
      : '';
  String pages = 'page=$page&';
  String perPages = 'per_page=$PER_PAGE_ITEM';
  String customerId =
      appStore.isLoggedIn ? 'customer_id=${appStore.userId}&' : '';
  String shopIds = shopId.isNotEmpty ? 'shop_id=$shopId&' : '';
  String zoneId = (isZoneId > 0) ? "zone_id=$isZoneId&" : '';

  // Final API URL
  String apiUrl =
      'search-list?$categoryIds$customerId$providerIds$isPriceMinPara$isPriceMaxPara$ratingPara$subCategorys$searchPara$latitudes$longitudes$isFeatures$shopIds$zoneId$pages$perPages';

  // Only log in debug mode to avoid printing in production
  assert(() {
    debugPrint('Calling API: $apiUrl');
    return true;
  }());
  try {
    var res = ServiceResponse.fromJson(
        await handleResponse(await buildHttpResponse(apiUrl)));

    if (page == 1) list.clear();
    list.addAll(res.serviceList.validate());

    lastPageCallBack?.call(res.serviceList.validate().length != PER_PAGE_ITEM);
    cachedServiceFavList = list;
    appStore.setLoading(false);
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }

  return list;
}

//endregion

//region Category Api

Future<CategoryResponse> getCategoryList(String page) async {
  // Utiliser les données mockées si activé
  if (USE_MOCK_DATA) {
    await simulateNetworkDelay(null, milliseconds: 200);
    return getMockCategoryResponse();
  }
  return CategoryResponse.fromJson(await handleResponse(await buildHttpResponse(
      'category-list?page=$page&per_page=50',
      method: HttpMethodType.GET)));
}

Future<List<CategoryData>> getCategoryListWithPagination(int page,
    {var perPage = PER_PAGE_CATEGORY_ITEM,
    required List<CategoryData> categoryList,
    Function(bool)? lastPageCallBack}) async {
  // Utiliser les données mockées si activé
  if (USE_MOCK_DATA) {
    await simulateNetworkDelay(null, milliseconds: 200);
    if (page == 1) categoryList.clear();
    categoryList.addAll(getMockCategories());
    cachedCategoryList = categoryList;
    lastPageCallBack?.call(true); // Dernière page
    appStore.setLoading(false);
    return categoryList;
  }

  try {
    CategoryResponse res = CategoryResponse.fromJson(await handleResponse(
        await buildHttpResponse('category-list?per_page=$perPage&page=$page',
            method: HttpMethodType.GET)));

    if (page == 1) categoryList.clear();
    categoryList.addAll(res.categoryList.validate());

    cachedCategoryList = categoryList;

    lastPageCallBack
        ?.call(res.categoryList.validate().length != PER_PAGE_CATEGORY_ITEM);

    appStore.setLoading(false);
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }

  return categoryList;
}
//endregion

//region SubCategory Api
Future<CategoryResponse> getSubCategoryList({required int catId}) async {
  try {
    CategoryResponse res = CategoryResponse.fromJson(await handleResponse(
        await buildHttpResponse(
            'subcategory-list?category_id=$catId&per_page=all',
            method: HttpMethodType.GET)));
    appStore.setLoading(false);

    return res;
  } catch (e) {
    appStore.setLoading(false);

    throw e;
  }
}

Future<List<CategoryData>> getSubCategoryListAPI({required int catId}) async {
  try {
    CategoryResponse res = CategoryResponse.fromJson(await handleResponse(
        await buildHttpResponse(
            'subcategory-list?category_id=$catId&per_page=all',
            method: HttpMethodType.GET)));

    appStore.setLoading(false);

    CategoryData allValue = CategoryData(id: -1, name: language.lblAll);
    if (!res.categoryList!.any((element) => element.id == allValue.id)) {
      res.categoryList!.insert(0, allValue);
    }

    if (!cachedSubcategoryList.any((element) => element?.$1 == catId)) {
      cachedSubcategoryList.add((catId, res.categoryList.validate()));
    } else {
      int index =
          cachedSubcategoryList.indexWhere((element) => element?.$1 == catId);
      cachedSubcategoryList[index] = (catId, res.categoryList.validate());
    }

    return res.categoryList.validate();
  } catch (e) {
    appStore.setLoading(false);

    throw e;
  }
}
//endregion

//region Provider Api
Future<ProviderInfoResponse> getProviderDetail(
  int id, {
  int? userId,
  double? latitude,
  double? longitude,
}) async {
  String params = '';

  // Check if passed or stored lat/lng should be used
  double lat =
      latitude ?? (appStore.isCurrentLocation ? getDoubleAsync(LATITUDE) : 0);
  double lng =
      longitude ?? (appStore.isCurrentLocation ? getDoubleAsync(LONGITUDE) : 0);

  if (lat > 0 && lng > 0) {
    params = "&latitude=$lat&longitude=$lng";
  }

  try {
    final response = await buildHttpResponse(
      'user-detail?id=$id&login_user_id=$userId$params',
      method: HttpMethodType.GET,
    );

    ProviderInfoResponse res =
        ProviderInfoResponse.fromJson(await handleResponse(response));
    appStore.setLoading(false);

    // Cache response
    if (!cachedProviderList.any((element) => element?.$1 == id)) {
      cachedProviderList.add((id, res));
    } else {
      int index = cachedProviderList.indexWhere((element) => element?.$1 == id);
      cachedProviderList[index] = (id, res);
    }

    return res;
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
}

Future<List<UserData>> getHandyman(
    {int? page,
    String? userTypeHandyman = "handyman",
    required List<UserData> list,
    Function(bool)? lastPageCallback}) async {
  try {
    var res = ProviderListResponse.fromJson(
      await handleResponse(await buildHttpResponse(
          'user-list?user_type=$userTypeHandyman&per_page=$PER_PAGE_ITEM&page=$page',
          method: HttpMethodType.GET)),
    );

    if (page == 1) list.clear();

    list.addAll(res.providerList.validate());

    lastPageCallback?.call(res.providerList.validate().length != PER_PAGE_ITEM);

    if (userTypeHandyman == USER_TYPE_HANDYMAN)
      cachedHandymanList = res.providerList;
    else
      cachedProviderFavList = res.providerList;

    appStore.setLoading(false);
  } catch (e) {
    appStore.setLoading(false);

    throw e;
  }
  return list;
}

Future<ProviderListResponse> getProvider(
    {String? userType = "provider", required String type}) async {
  return ProviderListResponse.fromJson(await handleResponse(
      await buildHttpResponse(
          'user-list?user_type=$userType&type=$type&per_page=all',
          method: HttpMethodType.GET)));
}
//endregion

//region Handyman Api
Future<UserData> getHandymanDetail(int id) async {
  return UserData.fromJson(await handleResponse(await buildHttpResponse(
      'user-detail?id=$id',
      method: HttpMethodType.GET)));
}

Future<BaseResponseModel> handymanRating(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('save-handyman-rating',
          request: request, method: HttpMethodType.POST)));
}
//endregion

//region Booking Api
Future<List<BookingData>> getBookingList(
  int page, {
  var perPage = PER_PAGE_ITEM,
  String serviceId = '',
  String dateFrom = '',
  String dateTo = '',
  String providerId = '',
  String handymanId = '',
  String bookingStatus = '',
  String paymentStatus = '',
  String paymentType = '',
  String searchText = '',
  String shopId = '',
  required List<BookingData> bookings,
  Function(bool)? lastPageCallback,
}) async {
  // Utiliser les données mockées si activé
  if (USE_MOCK_DATA) {
    await simulateNetworkDelay(null, milliseconds: 300);
    if (page == 1) bookings.clear();

    // Filtrer par statut si spécifié
    List<BookingData> mockBookings = getMockBookingsByStatus(bookingStatus);
    bookings.addAll(mockBookings);
    cachedBookingList = bookings;
    lastPageCallback?.call(true); // Dernière page
    appStore.setLoading(false);
    return bookings;
  }

  try {
    BookingListResponse res;
    String shopIds = shopId.isNotEmpty ? 'shop_id=$shopId&' : '';
    String serviceIds = serviceId.isNotEmpty ? 'service_id=$serviceId&' : '';
    String dateStart = dateFrom.isNotEmpty ? 'date_from=$dateFrom&' : '';
    String dateEnd = dateTo.isNotEmpty ? '&date_to=$dateTo&' : '';
    String providerIds =
        providerId.isNotEmpty ? 'provider_id=$providerId&' : '';
    String handymanIds =
        handymanId.isNotEmpty ? 'handyman_id=$handymanId&' : '';
    String status = bookingStatus.isNotEmpty ? 'status=$bookingStatus&' : '';
    String paymentStatuss =
        paymentStatus.isNotEmpty ? 'payment_status=$paymentStatus&' : '';
    String paymentTypes =
        paymentType.isNotEmpty ? 'payment_type=$paymentType&' : '';

    String perPageItem = 'per_page=$perPage&';
    String pageCount = 'page=$page';

    if (status == BOOKING_TYPE_ALL) {
      res = BookingListResponse.fromJson(await handleResponse(
          await buildHttpResponse('booking-list?per_page=$perPage&page=$page',
              method: HttpMethodType.GET)));
    } else {
      res = BookingListResponse.fromJson(await handleResponse(
          await buildHttpResponse(
              'booking-list?$shopIds$serviceIds$dateStart$dateEnd$providerIds$handymanIds$status$paymentStatuss$paymentTypes$perPageItem$pageCount',
              method: HttpMethodType.GET)));
    }
    if (page == 1) bookings.clear();
    bookings.addAll(res.data.validate());
    lastPageCallback?.call(res.data.validate().length != PER_PAGE_ITEM);

    cachedBookingList = bookings;

    appStore.setLoading(false);

    return bookings;
  } catch (e) {
    appStore.setLoading(false);

    throw e;
  }
}

Future<BookingDetailResponse> getBookingDetail(Map<String, dynamic> request,
    {Function(String)? callbackForStatus}) async {
  // Utiliser les données mockées si activé
  if (USE_MOCK_DATA) {
    await simulateNetworkDelay(null, milliseconds: 300);
    int bookingId = request[CommonKeys.bookingId].toString().toInt();
    BookingDetailResponse mockResponse =
        getMockBookingDetailResponse(bookingId);
    callbackForStatus?.call(mockResponse.bookingDetail!.status.validate());

    if (!cachedBookingDetailList.any((element) => element?.$1 == bookingId)) {
      cachedBookingDetailList.add((bookingId, mockResponse));
    } else {
      int index = cachedBookingDetailList
          .indexWhere((element) => element?.$1 == bookingId);
      cachedBookingDetailList[index] = (bookingId, mockResponse);
    }

    appStore.setLoading(false);
    return mockResponse;
  }

  try {
    BookingDetailResponse bookingDetailResponse =
        BookingDetailResponse.fromJson(await handleResponse(
            await buildHttpResponse('booking-detail',
                request: request, method: HttpMethodType.POST)));
    callbackForStatus
        ?.call(bookingDetailResponse.bookingDetail!.status.validate());
    bookingDetailResponse.bookingDetail?.couponData =
        bookingDetailResponse.couponData;

    int bookingId = request[CommonKeys.bookingId].toString().toInt();

    if (!cachedBookingDetailList.any((element) => element?.$1 == bookingId)) {
      cachedBookingDetailList.add((bookingId, bookingDetailResponse));
    } else {
      int index = cachedBookingDetailList
          .indexWhere((element) => element?.$1 == bookingId);
      cachedBookingDetailList[index] = (bookingId, bookingDetailResponse);
    }

    appStore.setLoading(false);
    return bookingDetailResponse;
  } catch (e) {
    appStore.setLoading(false);

    throw e;
  }
}

Future<BaseResponseModel> updateBooking(Map request) async {
  BaseResponseModel baseResponse = BaseResponseModel.fromJson(
      await handleResponse(await buildHttpResponse('booking-update',
          request: request, method: HttpMethodType.POST)));
  LiveStream().emit(LIVESTREAM_UPDATE_BOOKING_LIST);

  return baseResponse;
}

Future<BookingDetailResponse> saveBooking(Map request) async {
  var res = await handleResponse(await buildHttpResponse('booking-save',
      request: request, method: HttpMethodType.POST));

  return await getBookingDetail({
    CommonKeys.bookingId: res[CommonKeys.bookingId],
    CommonKeys.customerId: appStore.userId,
  });
}

Future<UpdateLocationResponse> getProviderLocation(int bookingId) async {
  return UpdateLocationResponse.fromJson(
    await handleResponse(await buildHttpResponse(
            "get-location?booking_id=$bookingId",
            method: HttpMethodType.GET)
        .timeout(const Duration(seconds: GET_LOCATION_API_TIMEOUT_SECOND))),
  );
}

Future<List<BookingStatusResponse>> bookingStatus(
    {required List<BookingStatusResponse> list}) async {
  Iterable res = await (handleResponse(
      await buildHttpResponse('booking-status', method: HttpMethodType.GET)));
  list = res.map((e) => BookingStatusResponse.fromJson(e)).toList();
  cachedBookingStatusDropdown = list;

  return list.validate();
}
//endregion

//region Payment Api
Future<BaseResponseModel> savePayment(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('save-payment',
          request: request, method: HttpMethodType.POST)));
}

Future<List<PaymentSetting>> getPaymentGateways(
    {bool requireCOD = true,
    bool requireWallet = true,
    bool isAddWallet = false}) async {
  String isAddWalletStatus = isAddWallet ? '?is_add_wallet=$isAddWallet' : '';

  try {
    Iterable it = await handleResponse(await buildHttpResponse(
        'payment-gateways$isAddWalletStatus',
        method: HttpMethodType.GET));
    List<PaymentSetting> res =
        it.map((e) => PaymentSetting.fromJson(e)).toList();

    if (!requireCOD)
      res.removeWhere((element) => element.type == PAYMENT_METHOD_COD);

    if (requireWallet && appConfigurationStore.isEnableUserWallet) {
      res.add(PaymentSetting(
          title: language.wallet, type: PAYMENT_METHOD_FROM_WALLET, status: 1));
    } else {
      res.removeWhere((element) => element.type == PAYMENT_METHOD_FROM_WALLET);
    }

    if (!appConfigurationStore.onlinePaymentStatus) {
      res.removeWhere(
          (element) => onlinePaymentGateways.contains(element.type));
    }

    return res;
  } catch (e) {
    throw e;
  }
}

Future<List<PaymentData>> getPaymentList(int page, int id,
    List<PaymentData> list, Function(bool)? lastPageCallback) async {
  appStore.setLoading(true);
  var res = PaymentListResponse.fromJson(await handleResponse(
      await buildHttpResponse('payment-list?booking_id=$id',
          method: HttpMethodType.GET)));

  if (page == 1) list.clear();

  list.addAll(res.data.validate());
  appStore.setLoading(false);

  lastPageCallback?.call(res.data.validate().length != PER_PAGE_ITEM);

  return list;
}

//endregion

//region Notification Api
Future<List<NotificationData>> getNotification({Map? request}) async {
  try {
    NotificationListResponse res = NotificationListResponse.fromJson(
      await (handleResponse(await buildHttpResponse(
          'notification-list?customer_id=${appStore.userId}',
          request: request,
          method: HttpMethodType.POST))),
    );

    appStore.setLoading(false);
    cachedNotificationList = res.notificationData.validate();
    return res.notificationData.validate();
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
}
//endregion

//region Notification Api
Future<CouponListResponse> getCouponList(
    {required int serviceId, required num price}) async {
  try {
    CouponListResponse res = CouponListResponse.fromJson(
      await (handleResponse(await buildHttpResponse(
          'coupon-list?service_id=$serviceId&price=$price',
          method: HttpMethodType.GET))),
    );

    appStore.setLoading(false);
    cachedCouponListResponse = res;
    return res;
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
}
//endregion

//region Review Api
Future<BaseResponseModel> updateReview(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('save-booking-rating',
          request: request, method: HttpMethodType.POST)));
}

Future<List<RatingData>> serviceReviews(Map request) async {
  try {
    ServiceReviewResponse res = ServiceReviewResponse.fromJson(
        await handleResponse(await buildHttpResponse(
            'service-reviews?per_page=all',
            request: request,
            method: HttpMethodType.POST)));
    appStore.setLoading(false);
    return res.ratingList.validate();
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
}

Future<List<RatingData>> customerReviews() async {
  try {
    ServiceReviewResponse res = ServiceReviewResponse.fromJson(
        await handleResponse(await buildHttpResponse(
            'get-user-ratings?per_page=all',
            method: HttpMethodType.GET)));
    appStore.setLoading(false);
    cachedRatingList = res.ratingList;
    return res.ratingList.validate();
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
}

Future<List<RatingData>> handymanReviews(Map request) async {
  try {
    ServiceReviewResponse res = ServiceReviewResponse.fromJson(
        await handleResponse(await buildHttpResponse(
            'handyman-reviews?per_page=all',
            request: request,
            method: HttpMethodType.POST)));
    appStore.setLoading(false);
    return res.ratingList.validate();
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
}

Future<BaseResponseModel> deleteReview({required int id}) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('delete-booking-rating',
          request: {"id": id}, method: HttpMethodType.POST)));
}

Future<BaseResponseModel> deleteHandymanReview({required int id}) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('delete-handyman-rating',
          request: {"id": id}, method: HttpMethodType.POST)));
}
//endregion

//region WishList Api
Future<List<ServiceData>> getWishlist(int page,
    {var perPage = PER_PAGE_ITEM,
    required List<ServiceData> services,
    Function(bool)? lastPageCallBack}) async {
  try {
    ServiceResponse serviceResponse = ServiceResponse.fromJson(
        await (handleResponse(await buildHttpResponse(
            'user-favourite-service?per_page=$perPage&page=$page',
            method: HttpMethodType.GET))));

    if (page == 1) services.clear();
    services.addAll(serviceResponse.serviceList.validate());

    lastPageCallBack
        ?.call(serviceResponse.serviceList.validate().length != PER_PAGE_ITEM);

    cachedServiceFavList = services;
    appStore.setLoading(false);
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
  return services;
}

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

//region Provider WishList Api
Future<List<UserData>> getProviderWishlist(int page,
    {var perPage = PER_PAGE_ITEM,
    required List<UserData> providers,
    Function(bool)? lastPageCallBack}) async {
  try {
    ProviderListResponse res = ProviderListResponse.fromJson(
        await (handleResponse(await buildHttpResponse(
            'user-favourite-provider?per_page=$perPage&page=$page',
            method: HttpMethodType.GET))));

    if (page == 1) providers.clear();
    providers.addAll(res.providerList.validate());

    lastPageCallBack?.call(res.providerList.validate().length != PER_PAGE_ITEM);

    cachedProviderFavList = providers;
    appStore.setLoading(false);
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
  return providers;
}

Future<BaseResponseModel> addProviderWishList(request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('save-favourite-provider',
          method: HttpMethodType.POST, request: request)));
}

Future<BaseResponseModel> removeProviderWishList(request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('delete-favourite-provider',
          method: HttpMethodType.POST, request: request)));
}
//endregion

//region Get My Service List API
Future<ServiceResponse> getMyServiceList() async {
  return ServiceResponse.fromJson(await handleResponse(await buildHttpResponse(
      'service-list?customer_id=${appStore.userId.validate()}',
      method: HttpMethodType.GET)));
}
//endregion

//region Get My post job

Future<BaseResponseModel> savePostJob(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('save-post-job',
          request: request, method: HttpMethodType.POST)));
}

Future<BaseResponseModel> deletePostRequest({required num id}) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('post-job-delete/$id',
          request: {}, method: HttpMethodType.POST)));
}

Future<BaseResponseModel> deleteServiceRequest(int id) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('service-delete/$id',
          request: {}, method: HttpMethodType.POST)));
}

Future<List<PostJobData>> getPostJobList(int page,
    {var perPage = PER_PAGE_ITEM,
    required List<PostJobData> postJobList,
    Function(bool)? lastPageCallBack}) async {
  try {
    var res = GetPostJobResponse.fromJson(await handleResponse(
        await buildHttpResponse('get-post-job?per_page=$perPage&page=$page',
            method: HttpMethodType.GET)));

    if (page == 1) postJobList.clear();
    postJobList.addAll(res.myPostJobData.validate());

    lastPageCallBack
        ?.call(res.myPostJobData.validate().length != PER_PAGE_ITEM);
    cachedPostJobList = postJobList;
    appStore.setLoading(false);
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }

  return postJobList;
}

Future<PostJobDetailResponse> getPostJobDetail(Map request) async {
  try {
    var res = PostJobDetailResponse.fromJson(await handleResponse(
        await buildHttpResponse('get-post-job-detail',
            request: request, method: HttpMethodType.POST)));
    appStore.setLoading(false);

    return res;
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
}

//endregion

//region FlutterWave Verify Transaction API
Future<VerifyTransactionResponse> verifyPayment(
    {required String transactionId,
    required String flutterWaveSecretKey}) async {
  return VerifyTransactionResponse.fromJson(
    await handleResponse(await buildHttpResponse(
        "https://api.flutterwave.com/v3/transactions/$transactionId/verify",
        header: buildHeaderForFlutterWave(flutterWaveSecretKey))),
  );
}
//endregion

//region Sadad Payment Api
Future<String> sadadLogin(Map request) async {
  try {
    var res = await handleSadadResponse(
      await buildHttpResponse(
        '$SADAD_API_URL/api/userbusinesses/login',
        method: HttpMethodType.POST,
        request: request,
        header: buildHeaderForSadad(),
      ),
    );

    return res['accessToken'];
  } catch (e) {
    throw errorSomethingWentWrong;
  }
}

Future sadadCreateInvoice(
    {required Map<String, dynamic> request, required String sadadToken}) async {
  return await handleSadadResponse(
    await buildHttpResponse(
      '$SADAD_API_URL/api/invoices/createInvoice',
      method: HttpMethodType.POST,
      request: request,
      header: buildHeaderForSadad(sadadToken: sadadToken),
    ),
  );
}
//endregion

// region Send Invoice on Email
Future<BaseResponseModel> sentInvoiceOnMail(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('download-invoice',
          request: request, method: HttpMethodType.POST)));
}
//endregion

//region CommonFunctions
Future<Map<String, String>> getMultipartFields(
    {required Map<String, dynamic> val}) async {
  Map<String, String> data = {};

  val.forEach((key, value) {
    data[key] = '$value';
  });

  return data;
}

Future<List<MultipartFile>> getMultipartImages(
    {required List<File> files, required String name}) async {
  List<MultipartFile> multiPartRequest = [];

  await Future.forEach<File>(files, (element) async {
    int i = files.indexOf(element);

    multiPartRequest.add(await MultipartFile.fromPath(
        '${'$name' + i.toString()}', element.path));
  });

  return multiPartRequest;
}
//endregion

Future<BaseResponseModel> deleteImage(Map request) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('remove-file',
          request: request, method: HttpMethodType.POST)));
}

Future<BaseResponseModel> chooseDefaulBank({required int bankId}) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('default-bank?id=$bankId',
          request: {}, method: HttpMethodType.POST)));
}

Future<BaseResponseModel> deleteBank({int? bankId}) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('delete-bank/$bankId',
          request: {}, method: HttpMethodType.POST)));
}

Future<List<BankHistory>> getBankListDetail({
  required int userId,
  int? page,
  var perPage = PER_PAGE_ITEM,
  required List<BankHistory> list,
  Function(bool)? lastPageCallback,
}) async {
  BankListResponse res = BankListResponse.fromJson(
    await handleResponse(await buildHttpResponse(
        'user-bank-detail?per_page=$perPage&page=$page&user_id=$userId',
        method: HttpMethodType.GET)),
  );

  if (page == 1) list.clear();
  list.addAll(res.data.validate());

  cachedBankList = list;

  appStore.setLoading(false);

  lastPageCallback?.call(res.data.validate().length != PER_PAGE_ITEM);

  return list;
}

Future<BaseResponseModel> providerPayOut({required Map request}) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('provider-payout',
          request: request, method: HttpMethodType.POST)));
}

Future<BaseResponseModel> walletMoneyWithdrawal({required Map request}) async {
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('withdraw-money',
          request: request, method: HttpMethodType.POST)));
}

Future<List<ShopModel>> getShopList(
  int page, {
  var perPage = PER_PAGE_ITEM,
  required List<ShopModel> shopList,
  Function(bool)? lastPageCallBack,
  String search = "",
  String serviceIds = '',
  String providerIds = '',
}) async {
  try {
    String searchParam = search.isNotEmpty ? '&search=$search' : '';
    if (serviceIds.isNotEmpty) searchParam += '&service_id=$serviceIds';
    if (providerIds.isNotEmpty) searchParam += '&provider_id=$providerIds';
    String apiUrl = 'shop-list?per_page=$perPage&page=$page$searchParam';

    ShopResponse res = await ShopResponse.fromJson(await handleResponse(
        await buildHttpResponse(apiUrl, method: HttpMethodType.GET)));

    if (page == 1) shopList.clear();
    // No longer need to resolve location names as API provides them directly
    shopList.addAll(res.shopList.validate());
    cachedShopList = shopList;
    lastPageCallBack?.call(res.shopList.validate().length != PER_PAGE_ITEM);
    appStore.setLoading(false);
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
  return shopList;
}

Future<ShopDetailResponse> getShopDetail(int shopId) async {
  try {
    var res = ShopDetailResponse.fromJson(await handleResponse(
        await buildHttpResponse('shop-detail/$shopId',
            method: HttpMethodType.GET)));
    appStore.setLoading(false);
    return res;
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
}

Future<List<ShopModel>> getWishlistShops(int page,
    {var perPage = PER_PAGE_ITEM,
    required List<ShopModel> shops,
    Function(bool)? lastPageCallBack}) async {
  try {
    var res = ShopResponse.fromJson(await handleResponse(
        await buildHttpResponse('wishlist-shops?per_page=$perPage&page=$page',
            method: HttpMethodType.GET)));

    if (page == 1) shops.clear();
    shops.addAll(res.shopList.validate());
    lastPageCallBack?.call(res.shopList.validate().length != PER_PAGE_ITEM);
    appStore.setLoading(false);
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
  return shops;
}

Future<List<ZoneModel>> getZoneList({
  int page = 1,
  int perPage = PER_PAGE_ITEM,
  required List<ZoneModel> services,
  Function(bool)? lastPageCallback,
}) async {
  try {
    ProviderZoneResponse res;

    String req = '?page=$page&zone_id=1&per_page=$perPage';
    res = ProviderZoneResponse.fromJson(
      await handleResponse(
        await buildHttpResponse('zones$req', method: HttpMethodType.GET),
      ),
    );

    if (page == 1) services.clear();

    services.addAll(res.data.validate());

    lastPageCallback?.call(res.data.validate().length != perPage);

    appStore.setLoading(false);
    return services;
  } catch (e) {
    appStore.setLoading(false);
    throw e;
  }
}

//endregion
// region Loyalty
Future<BaseResponseModel> checkReferralCode(String referralCode) async {
  String encodedCode = Uri.encodeComponent(referralCode.trim());
  return BaseResponseModel.fromJson(await handleResponse(
      await buildHttpResponse('check-referral?referral_code=$encodedCode',
          method: HttpMethodType.POST)));
}

Future<List<LoyaltyHistoryItem>> getLoyaltyHistory({
  int page = 1,
  var perPage = PER_PAGE_ITEM,
  String filter = 'last_week',
  required List<LoyaltyHistoryItem> loyaltyHistoryList,
  Function(bool)? lastPageCallBack,
}) async {
  final filterQuery =
      filter.trim().isNotEmpty ? '&filter=${Uri.encodeComponent(filter)}' : '';
  final res = LoyaltyHistoryResponse.fromJson(await handleResponse(
    await buildHttpResponse(
        'loyalty-history?user_id=${appStore.userId}&per_page=$perPage&page=$page$filterQuery',
        method: HttpMethodType.GET),
  ));

  if (page == 1) loyaltyHistoryList.clear();
  loyaltyHistoryList.addAll(res.data);
  cachedLoyaltyHistoryList = loyaltyHistoryList;
  lastPageCallBack?.call(res.data.length != perPage);

  return loyaltyHistoryList;
}

Future<int?> getServiceEarnPoints(
    {required int serviceId,
    required num subTotal,
    required String type}) async {
  final endPoint =
      'get-earn-points?service_id=$serviceId&sub_total=$subTotal&type=$type';
  final res = await handleResponse(
      await buildHttpResponse(endPoint, method: HttpMethodType.GET));

  if (res is Map<String, dynamic>) {
    final value = res['earn_points'];
    if (value == null) return null;

    return int.tryParse(value.toString());
  }

  return null;
}
//endregion

// region Mison API - Orders & Services
// Documentation: BACKEND_API_README.md
// Base URL: https://api.mison.app/api/

/// GET /api/services - Liste des services disponibles
Future<MisonServicesResponse> getMisonServices() async {
  try {
    final response = await buildHttpResponse('services', method: HttpMethodType.GET);
    return MisonServicesResponse.fromJson(await handleResponse(response));
  } catch (e) {
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
    return MisonOrderResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
  }
}

/// GET /api/orders/{id} - Détails d'une commande spécifique
Future<MisonOrderDetailResponse> getMisonOrderDetail(String orderId) async {
  try {
    final response = await buildHttpResponse('orders/$orderId', method: HttpMethodType.GET);
    return MisonOrderDetailResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
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
    return MisonOrderDetailResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/artisan-decision - Décision de l'artisan sur une commande
/// @param orderId - UUID de la commande
/// @param decision - APPROVE ou REJECT
Future<MisonActionResponse> artisanDecisionMisonOrder(String orderId, String decision) async {
  try {
    final request = MisonArtisanDecisionRequest(decision: decision);
    final response = await buildHttpResponse(
      'orders/$orderId/artisan-decision',
      request: request.toJson(),
      method: HttpMethodType.POST,
    );
    return MisonActionResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
  }
}

/// POST /api/orders/{id}/rate - Noter une commande complétée
/// @param orderId - UUID de la commande
/// @param rating - Note de 1 à 5
/// @param review - Commentaire de la notation
Future<MisonActionResponse> rateMisonOrder(String orderId, int rating, String review) async {
  try {
    final request = MisonRateOrderRequest(rating: rating, review: review);
    final response = await buildHttpResponse(
      'orders/$orderId/rate',
      request: request.toJson(),
      method: HttpMethodType.POST,
    );
    return MisonActionResponse.fromJson(await handleResponse(response));
  } catch (e) {
    throw e;
  }
}

//endregion Mison API
