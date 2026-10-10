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

// Pending CallKit accept when navigator wasn't ready yet (app waking from background).
String? _pendingCallOrderId;
String? _pendingCallChannel;

void _openCallScreen(String orderId, String channel) {
  // Safety net: this device initiated the call — don't open the callee screen.
  if (MisonCallScreen.isOutgoing(orderId)) return;

  final nav = navigatorKey.currentState;
  if (nav != null) {
    nav.push(MaterialPageRoute(
      builder: (_) => MisonIncomingCallScreen(
        orderId: orderId,
        channel: channel,
        autoAccept: true,
      ),
    ));
  } else {
    // Navigator not ready yet — store and retry once the first frame is rendered.
    _pendingCallOrderId = orderId;
    _pendingCallChannel = channel;
  }
}

/// iPhone, app fermée : décroché depuis l'écran d'appel, l'événement
/// « accepté » est perdu (Flutter n'écoutait pas encore). Appelé une fois les
/// tableaux de bord affichés : ouvre l'appel s'il vient d'être accepté.
bool _coldStartCallChecked = false;

Future<void> openColdStartAcceptedCall() async {
  if (_coldStartCallChecked) return;
  _coldStartCallChecked = true;
  if (Platform.isAndroid) return _openAndroidAcceptedCall();
  try {
    final data = await const MethodChannel('mison/accepted_call').invokeMapMethod<String, dynamic>('getAcceptedCall');
    final extra = (data?['extra'] as Map?)?.cast<String, dynamic>() ?? {};
    final orderId = extra['order_id']?.toString() ?? '';
    if (orderId.isEmpty) return;
    // Déjà ouvert par l'événement (app seulement en arrière-plan) : rien à faire.
    if (MisonCallSession.current.value?.orderId == orderId) return;
    _openCallScreen(orderId, extra['channel']?.toString() ?? '');
  } catch (e) {
    log('openColdStartAcceptedCall: $e');
  }
}

/// Android, app fermée : « Accepter » sur l'écran d'appel lance l'app, mais
/// l'événement part avant que Flutter écoute. Le module garde l'appel accepté
/// en mémoire (isAccepted) : on le retrouve ici et on rejoint l'appel
/// directement, sans repasser par « Appel entrant ».
Future<void> _openAndroidAcceptedCall() async {
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is! List) return;
    for (final call in calls) {
      if (call is! Map || call['isAccepted'] != true) continue;
      final extra = (call['extra'] as Map?)?.cast<String, dynamic>() ?? {};
      final orderId = extra['order_id']?.toString() ?? '';
      if (orderId.isEmpty) continue;
      // Déjà ouvert par l'événement (app seulement en arrière-plan).
      if (MisonCallSession.current.value?.orderId == orderId) return;
      _openCallScreen(orderId, extra['channel']?.toString() ?? '');
      return;
    }
  } catch (e) {
    log('openAndroidAcceptedCall: $e');
  }
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

/// Called from _MyAppState.initState() to flush any pending CallKit accept.
void flushPendingCall() {
  final orderId = _pendingCallOrderId;
  final channel = _pendingCallChannel;
  if (orderId != null) {
    _pendingCallOrderId = null;
    _pendingCallChannel = null;
    _openCallScreen(orderId, channel ?? '');
  }
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
        _openCallScreen(orderId, channel);
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
