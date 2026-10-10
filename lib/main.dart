import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart' show MethodChannel;
import 'package:booking_system_flutter/component/ongoing_call_banner.dart';
import 'package:booking_system_flutter/services/mison_call_session.dart';
import 'package:booking_system_flutter/utils/call_status.dart';
import 'package:booking_system_flutter/app_theme.dart';
import 'package:booking_system_flutter/firebase_options.dart';
import 'package:booking_system_flutter/locale/app_localizations.dart';
import 'package:booking_system_flutter/locale/language_en.dart';
import 'package:booking_system_flutter/locale/languages.dart';
import 'package:booking_system_flutter/model/booking_detail_model.dart';
import 'package:booking_system_flutter/model/get_my_post_job_list_response.dart';
import 'package:booking_system_flutter/model/material_you_model.dart';
import 'package:booking_system_flutter/model/notification_model.dart';
import 'package:booking_system_flutter/model/provider_info_response.dart';
import 'package:booking_system_flutter/model/remote_config_data_model.dart';
import 'package:booking_system_flutter/model/service_data_model.dart';
import 'package:booking_system_flutter/model/service_detail_response.dart';
import 'package:booking_system_flutter/model/user_data_model.dart';
import 'package:booking_system_flutter/model/user_wallet_history.dart';
import 'package:booking_system_flutter/screens/blog/model/blog_detail_response.dart';
import 'package:booking_system_flutter/screens/blog/model/blog_response_model.dart';
import 'package:booking_system_flutter/screens/helpDesk/model/help_desk_response.dart';
import 'package:booking_system_flutter/screens/referral_loyalty_points/model/loyalty_history_model.dart';
import 'package:booking_system_flutter/screens/splash_screen.dart';
import 'package:booking_system_flutter/services/auth_services.dart';
import 'package:booking_system_flutter/services/chat_services.dart';
import 'package:booking_system_flutter/services/user_services.dart';
import 'package:booking_system_flutter/store/app_configuration_store.dart';
import 'package:booking_system_flutter/store/app_store.dart';
import 'package:booking_system_flutter/store/filter_store.dart';
import 'package:booking_system_flutter/store/roles_and_permission_store.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/services/deep_link_service.dart';
import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/screens/call/mison_incoming_call_screen.dart';
import 'package:booking_system_flutter/utils/firebase_messaging_utils.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/network/network_utils.dart' show isNotFoundError;
import 'package:booking_system_flutter/model/mison_order_model.dart' show MisonCallTokenResponse;
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';

import 'model/bank_list_response.dart';
import 'model/booking_data_model.dart';
import 'model/booking_status_model.dart';
import 'model/category_model.dart';
import 'model/coupon_list_model.dart';
import 'model/dashboard_model.dart';
import 'model/shop_model.dart';

//region Handle Background Firebase Message
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try { await Firebase.initializeApp(); } catch (_) {}
  if (message.data['type'] == 'INCOMING_CALL') {
    final orderId  = message.data['order_id']?.toString()  ?? '';
    final channel  = message.data['channel']?.toString()   ?? '';
    final caller   = message.data['caller_name']?.toString() ?? 'Appel entrant';

    // Refus depuis la notification / CallKit et annulation par l'appelant,
    // même app fermée : ce handler est le seul code Dart qui tourne alors.
    watchIncomingCall(orderId);

    // iOS: AppDelegate handles CallKit natively — MethodChannel unreliable
    // from a terminated-app Dart background isolate.
    if (Platform.isIOS) return;

    // Skip if this device initiated the call (background isolate can't access
    // the in-memory Set, so we check the SharedPreferences value instead).
    // Le marqueur n'est valable que 2 min : un appel sortant mal terminé ne doit
    // pas empêcher ce téléphone de sonner ensuite pour la même commande.
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload(); // valeur écrite par l'app au premier plan
      final at = p.getInt(kOutgoingCallAtKey) ?? 0;
      final recent = DateTime.now().millisecondsSinceEpoch - at < kOutgoingCallValidity.inMilliseconds;
      if (p.getString('outgoing_call_order_id') == orderId && recent) return;
    } catch (_) {}

    await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
      id: newCallKitId(),
      nameCaller: caller,
      appName: 'MISON',
      type: 0, // audio
      textAccept: 'Accepter',
      textDecline: 'Refuser',
      duration: 30000,
      ios: const IOSParams(
        iconName: '',
        handleType: 'generic',
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        supportsDTMF: false,
        ringtonePath: '',
        configureAudioSession: false,
      ),
      android: const AndroidParams(
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0F1B2D',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Appels entrants',
        missedCallNotificationChannelName: 'Appels manqués',
      ),
      extra: {'order_id': orderId, 'channel': channel},
    ));
  }
}

/// Appelé quand l'utilisateur tape la notification d'appel Android (background/terminée).
@pragma('vm:entry-point')
void onNotificationTap(NotificationResponse details) {
  if (details.payload == null) return;
  try {
    final data = jsonDecode(details.payload!);
    if (data is! Map) return;
    if (data['type'] == 'INCOMING_CALL') {
      final orderId = data['order_id']?.toString() ?? '';
      final channel = data['channel']?.toString() ?? '';
      if (orderId.isEmpty) return;
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => MisonIncomingCallScreen(orderId: orderId, channel: channel),
      ));
      return;
    }
    // Notification affichée app ouverte : même routage qu'un appui sur une
    // notification système (détail de commande, chat, support…).
    handleNotificationClick(RemoteMessage(data: Map<String, dynamic>.from(data)));
  } catch (_) {}
}

// ── Appel décroché depuis l'écran d'appel du téléphone ──────────────────────
// (CallKit sur iPhone, écran / notification d'appel sur Android)
//
// L'appel est rejoint TOUT DE SUITE, sans attendre l'interface : sur un iPhone
// verrouillé ou une app lancée en arrière-plan par l'appel, Flutter ne dessine
// rien, et l'ancien écran intermédiaire (« Connexion à l'appel… ») ne
// s'ouvrait qu'au déverrouillage — l'appel ne se lançait pas. L'écran d'appel
// s'affiche dès que l'app est visible (ou via la barre « Appel en cours »).

/// Appels du téléphone (identifiant CallKit) déjà rejoints : un même décroché
/// peut arriver par l'événement ET par la vérification au démarrage.
final Set<String> _joinedCallKitIds = {};

/// Écran d'appel à ouvrir dès que la navigation est prête.
MisonCallSession? _pendingCallScreen;

Future<void> _joinAcceptedCall({
  required String callKitId,
  required String orderId,
  required String channel,
  String callerName = '',
}) async {
  if (orderId.isEmpty) return;
  // Ce téléphone a lancé l'appel : ce n'est pas lui qui décroche.
  if (MisonCallScreen.isOutgoing(orderId)) return;
  if (callKitId.isNotEmpty && !_joinedCallKitIds.add(callKitId)) return;
  // Reste d'un appel précédent sur la même commande : on repart à neuf.
  MisonCallSession.dropStaleFor(orderId);

  // Réseau parfois lent au réveil du téléphone : quelques essais.
  MisonCallTokenResponse? tokenData;
  for (var attempt = 0; attempt < 3 && tokenData == null; attempt++) {
    try {
      // notify:false — on rejoint un appel déjà en cours, inutile de refaire
      // sonner l'appelant.
      tokenData = await getCallToken(orderId, notify: false);
    } catch (e) {
      log('joinAcceptedCall: $e');
      if (isNotFoundError(e)) break; // appel destiné à un autre compte
      await Future.delayed(Duration(seconds: attempt + 1));
    }
  }
  if (tokenData == null || (tokenData.appId ?? '').isEmpty || (tokenData.token ?? '').isEmpty) {
    endCallKitForOrder(orderId);
    try {
      TopToast.show(message: "Impossible de rejoindre l'appel", type: TopToastType.error);
    } catch (_) {}
    return;
  }

  final session = MisonCallSession.start(
    orderId: orderId,
    otherPartyName: callerName.isNotEmpty ? callerName : 'Appel MISON',
    appId: tokenData.appId!,
    channel: tokenData.channel ?? channel,
    token: tokenData.token!,
    uid: tokenData.uid ?? 2,
    isCaller: false,
  );
  _showCallScreen(session);
}

void _showCallScreen(MisonCallSession session) {
  if (session.ended || MisonCallScreen.visibleCount.value > 0) return;
  final nav = navigatorKey.currentState;
  if (nav == null) {
    _pendingCallScreen = session; // ouvert au premier affichage de l'app
    return;
  }
  _pendingCallScreen = null;
  nav.push(MaterialPageRoute(
    builder: (_) => MisonCallScreen(
      orderId: session.orderId,
      otherPartyName: session.otherPartyName,
      appId: session.appId,
      channel: session.channel,
      token: session.token,
      uid: session.uid,
      isCaller: session.isCaller,
    ),
  ));
}

/// Décroché pendant que l'app était fermée : l'événement « accepté » est parti
/// avant que Flutter écoute. Le module d'appel garde l'appel accepté : on le
/// retrouve et on le rejoint.
Future<void> _joinColdStartAcceptedCall() async {
  try {
    if (Platform.isIOS) {
      final data = await const MethodChannel('mison/accepted_call').invokeMapMethod<String, dynamic>('getAcceptedCall');
      if (data == null) return;
      final id = data['id']?.toString() ?? '';
      // Appel déjà terminé depuis : rien à rejoindre.
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active is List && !active.any((c) => c is Map && c['id']?.toString() == id)) return;
      final extra = (data['extra'] as Map?)?.cast<String, dynamic>() ?? {};
      await _joinAcceptedCall(
        callKitId: id,
        orderId: extra['order_id']?.toString() ?? '',
        channel: extra['channel']?.toString() ?? '',
        callerName: data['nameCaller']?.toString() ?? '',
      );
      return;
    }
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is! List) return;
    for (final call in calls) {
      if (call is! Map || call['isAccepted'] != true) continue;
      final extra = (call['extra'] as Map?)?.cast<String, dynamic>() ?? {};
      final orderId = extra['order_id']?.toString() ?? '';
      if (orderId.isEmpty) continue;
      await _joinAcceptedCall(
        callKitId: call['id']?.toString() ?? '',
        orderId: orderId,
        channel: extra['channel']?.toString() ?? '',
        callerName: call['nameCaller']?.toString() ?? '',
      );
      return;
    }
  } catch (e) {
    log('joinColdStartAcceptedCall: $e');
  }
}

/// Appelé une fois les tableaux de bord affichés : affiche l'écran de l'appel
/// décroché app fermée (déjà rejoint au démarrage), ou le rejoint si besoin.
MisonCallSession? _dashboardShownSession;

Future<void> openColdStartAcceptedCall() async {
  final session = MisonCallSession.current.value;
  if (session != null && !session.ended && !session.isCaller) {
    // Une seule fois par appel : un appel réduit ne doit pas se rouvrir à
    // chaque retour sur l'accueil.
    if (session == _dashboardShownSession) return;
    _dashboardShownSession = session;
    _showCallScreen(session);
    return;
  }
  await _joinColdStartAcceptedCall();
}

/// Appels qui sonnent encore (pas encore décrochés) au démarrage de l'app.
Future<void> _watchRingingCalls() async {
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is! List) return;
    for (final call in calls) {
      if (call is! Map) continue;
      // iOS : « accepted », Android : « isAccepted ».
      if (call['accepted'] == true || call['isAccepted'] == true) continue;
      final extra = (call['extra'] as Map?)?.cast<String, dynamic>() ?? {};
      final orderId = extra['order_id']?.toString() ?? '';
      if (orderId.isNotEmpty) watchIncomingCall(orderId);
    }
  } catch (e) {
    log('watchRingingCalls: $e');
  }
}

/// Appelé au premier affichage de l'app : ouvre l'écran d'un appel décroché
/// avant que la navigation soit prête.
void flushPendingCall() {
  final session = _pendingCallScreen;
  _pendingCallScreen = null;
  if (session != null) _showCallScreen(session);
}

/// Android 14+ : demande l'autorisation d'afficher un appel en plein écran.
Future<void> _ensureFullScreenCallPermission() async {
  if (!Platform.isAndroid) return;
  try {
    final canUse = await FlutterCallkitIncoming.canUseFullScreenIntent();
    if (canUse == false) await FlutterCallkitIncoming.requestFullIntentPermission();
  } catch (e) {
    log('fullScreenIntent permission error: $e');
  }
}

/// Enregistre le token PushKit iOS auprès du backend.
///
/// C'est ce token qui permet de faire sonner un appel alors que
/// l'application est complètement fermée — une notification FCM classique
/// n'y suffit pas sur iOS.
Future<void> syncVoipToken() async {
  if (!Platform.isIOS) return;
  try {
    final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    final value = token?.toString() ?? '';
    if (value.isNotEmpty) await saveVoipTokenToBackend(value);
  } catch (e) {
    log('syncVoipToken error: $e');
  }
}

/// Écoute les actions CallKit (accepter / refuser depuis l'écran de verrouillage)
/// et la mise à jour du token VoIP.
void _listenCallKitEvents() {
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
    if (event == null) return;

    if (event.event == Event.actionDidUpdateDevicePushTokenVoip) {
      final token = event.body['deviceTokenVoIP']?.toString() ?? event.body.toString();
      if (token.isNotEmpty && appStore.isLoggedIn) saveVoipTokenToBackend(token);
      return;
    }

    final extra   = (event.body['extra'] as Map?)?.cast<String, dynamic>() ?? {};
    final orderId = extra['order_id']?.toString() ?? '';
    final channel = extra['channel']?.toString()  ?? '';
    if (orderId.isEmpty) return;

    switch (event.event) {
      case Event.actionCallIncoming:
        // L'écran d'appel du téléphone sonne (iPhone : notification VoIP) :
        // si l'appelant raccroche, la sonnerie doit s'arrêter aussitôt.
        if (!MisonCallScreen.isOutgoing(orderId)) MisonCallSession.dropStaleFor(orderId);
        watchIncomingCall(orderId);
      case Event.actionCallAccept:
        _joinAcceptedCall(
          callKitId: event.body['id']?.toString() ?? '',
          orderId: orderId,
          channel: channel,
          callerName: event.body['nameCaller']?.toString() ?? '',
        );
      case Event.actionCallDecline:
      case Event.actionCallTimeout:
        // Sonné sans réponse ≠ refusé : l'appelant voit « n'a pas répondu ».
        if (event.event == Event.actionCallTimeout) {
          markCallMissed(orderId);
        } else {
          markCallDeclined(orderId);
        }
        endCallKitForOrder(orderId);
      case Event.actionCallEnded:
        // « Raccrocher » depuis la notification Android ou l'interface CallKit :
        // sans ça, seul l'affichage se fermait et l'appel continuait.
        MisonCallSession.hangUpFromSystem(orderId);
        endCallKitForOrder(orderId);
      default:
        break;
    }
  });
}

//endregion
//region Mobx Stores
AppStore appStore = AppStore();
FilterStore filterStore = FilterStore();
AppConfigurationStore appConfigurationStore = AppConfigurationStore();
RolesAndPermissionStore rolesAndPermissionStore = RolesAndPermissionStore();
//endregion

//region Global Variables
BaseLanguage language = LanguageEn();

/// Badge notifications non-lues pour l'ouvrier. Persisté en SharedPrefs.
final ValueNotifier<int> artisanNotifBadge = ValueNotifier<int>(0);
//endregion

//region Services
UserService userService = UserService();
AuthService authService = AuthService();
ChatServices chatServices = ChatServices();
RemoteConfigDataModel remoteConfigDataModel = RemoteConfigDataModel();
//endregion

//region Cached Response Variables for Dashboard Tabs
DashboardResponse? cachedDashboardResponse;
List<BookingData>? cachedBookingList;
List<CategoryData>? cachedCategoryList;
List<BookingStatusResponse>? cachedBookingStatusDropdown;
List<PostJobData>? cachedPostJobList;
List<WalletDataElement>? cachedWalletHistoryList;

List<ServiceData> cachedServiceFavList = [];
List<ShopModel> cachedShopList = [];
List<UserData>? cachedProviderFavList;
List<UserData>? cachedHandymanList;
List<BlogData>? cachedBlogList;
List<RatingData>? cachedRatingList;
List<HelpDeskListData>? cachedHelpDeskListData;
List<NotificationData>? cachedNotificationList;
CouponListResponse? cachedCouponListResponse;
List<BankHistory>? cachedBankList;
List<LoyaltyHistoryItem>? cachedLoyaltyHistoryList;
int? cachedLoyaltyPoints;
List<(int blogId, BlogDetailResponse list)?> cachedBlogDetail = [];
List<(int serviceId, ServiceDetailResponse list)?> listOfCachedData = [];
List<(int providerId, ProviderInfoResponse list)?> cachedProviderList = [];
List<(int categoryId, List<CategoryData> list)?> cachedSubcategoryList = [];
List<(int bookingId, BookingDetailResponse list)?> cachedBookingDetailList = [];
UserData? cachedUserDetail;
//endregion

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // je vais les configurer apres : ch sall
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: "XXX",
        authDomain: "XXX.firebaseapp.com",
        projectId: "XXX",
        storageBucket: "XXX.appspot.com",
        messagingSenderId: "XXX",
        appId: "XXX",
      ),
    );
  } else {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
/*   await Firebase.initializeApp().then((value) {
    /// Firebase Notification
    initFirebaseMessaging();
    if (kReleaseMode) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    }
  }); */

  passwordLengthGlobal = 6;
  appButtonBackgroundColorGlobal = primaryColor;
  defaultAppButtonTextColorGlobal = Colors.white;
  defaultRadius = 12;
  defaultBlurRadius = 10;
  defaultSpreadRadius = 1;
  defaultAppButtonElevation = 0;
  pageRouteTransitionDurationGlobal = 400.milliseconds;
  textBoldSizeGlobal = 16;
  textPrimarySizeGlobal = 16;
  textSecondarySizeGlobal = 14;

  await initialize();
  localeLanguageList = languageList();

  appStore.setDarkMode(false);

  defaultToastBackgroundColor =
      appStore.isDarkMode ? Colors.white : Colors.black;
  defaultToastTextColor = appStore.isDarkMode ? Colors.black : Colors.white;

  // Background handler — doit être enregistré le plus tôt possible
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // iOS foreground : afficher alert/badge/son même quand l'app est ouverte
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Channel Android haute importance (avant tout affichage de notif)
  await createNotificationChannel();

  // Enregistre le callback de tap sur notifications locales (appels entrants).
  // Doit être fait avant runApp pour couvrir le cas app terminée.
  await FlutterLocalNotificationsPlugin().initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_ic_notification'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: onNotificationTap,
    onDidReceiveBackgroundNotificationResponse: onNotificationTap,
  );

  // Listener foreground enregistré UNE FOIS ici, avant runApp
  registerForegroundMessageListener();
  // CallKit events (accepter/refuser depuis l'écran verrouillé) + token VoIP
  _listenCallKitEvents();
  // App réveillée par un appel (iPhone : notification VoIP, app fermée) :
  // l'événement « sonne » est parti avant ce listener. On suit quand même
  // l'appel, pour arrêter la sonnerie si l'appelant raccroche.
  _watchRingingCalls();
  // Décroché pendant que l'app était fermée : on rejoint l'appel tout de
  // suite, sans attendre l'interface (iPhone verrouillé : rien ne s'affiche).
  _joinColdStartAcceptedCall();
  // Android 14+ : sans cette autorisation, l'écran d'appel plein écran ne
  // s'affiche pas quand le téléphone est verrouillé.
  await _ensureFullScreenCallPermission();

  // Initialize deep link service
  DeepLinkService().init();

  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => flushPendingCall());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Quand l'app revient au premier plan après un background FCM, les listes
  /// de commandes (ouvrier et client) sont rafraîchies automatiquement.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      emitOrderListRefresh(badge: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RestartAppWidget(
        child: SafeArea(
      top: false,
      child: Observer(
        builder: (_) => FutureBuilder<Color>(
          future: getMaterialYouData(),
          builder: (_, snap) {
            return Observer(
              builder: (_) => MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                home: SplashScreen(),
                theme: AppTheme.lightTheme(color: snap.data),
                darkTheme: AppTheme.darkTheme(color: snap.data),
                themeMode: ThemeMode.light,
                title: APP_NAME,
                supportedLocales: LanguageDataModel.languageLocales(),
                localizationsDelegates: [
                  AppLocalizations(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (context, child) {
                  return MediaQuery(
                    // Barre « Appel en cours » quand l'écran d'appel est réduit.
                    child: OngoingCallBanner(child: child!),
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(1.0)),
                  );
                },
                localeResolutionCallback: (locale, supportedLocales) => locale,
                locale: Locale(appStore.selectedLanguageCode),
              ),
            );
          },
        ),
      ),
    ));
  }
}
