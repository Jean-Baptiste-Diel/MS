import 'package:booking_system_flutter/services/chat_unread_store.dart';
import 'package:booking_system_flutter/utils/log_redact.dart';
import 'package:nb_utils/nb_utils.dart' as nb_log show log;
import 'dart:convert';
import 'dart:io';

import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/order_events.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:booking_system_flutter/screens/support_chat/support_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../network/rest_apis.dart';
import '../screens/booking/mison_order_detail_screen.dart';
import '../screens/booking/mison_order_searching_screen.dart';
import '../screens/call/mison_call_screen.dart';
import '../screens/call/mison_incoming_call_screen.dart';
import '../services/mison_call_session.dart';
import '../screens/chat/mison_order_chat_screen.dart';
import 'constant.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

// Canal au son MISON. Android ne permet pas de changer le son d'un canal
// existant : nouvel identifiant (l'ancien « notification » est supprimé).
const _kChannelId = 'mison_notifications';
const _kChannelName = 'Notifications MISON';
const _kOldChannelId = 'notification';
const _kSound = RawResourceAndroidNotificationSound('mison_notification');
const _kIosSound = 'mison_notification.wav';
const _kCallChannelId = 'incoming_calls';
const _kCallChannelName = 'Appels entrants';
const _kCallNotifId = 9999;

/// Notification plein-écran pour appel entrant (background / écran verrouillé).
/// Sonne et affiche l'écran d'appel même quand l'app est en arrière-plan.
Future<void> showIncomingCallNotification({
  required String orderId,
  required String channel,
  required String callerName,
}) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@drawable/ic_stat_ic_notification');
    const darwin = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: false,
      requestAlertPermission: true,
    );
    await plugin.initialize(const InitializationSettings(android: android, iOS: darwin, macOS: darwin));

    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _kCallChannelId,
          _kCallChannelName,
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
          showBadge: true,
        ));

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kCallChannelId,
        _kCallChannelName,
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        autoCancel: false,
        ongoing: true,
        icon: '@drawable/ic_stat_ic_notification',
        category: AndroidNotificationCategory.call,
        actions: const [
          AndroidNotificationAction('decline', 'Refuser',
              cancelNotification: true, showsUserInterface: false),
          AndroidNotificationAction('accept', 'Accepter',
              cancelNotification: true, showsUserInterface: true),
        ],
      ),
      iOS: const DarwinNotificationDetails(sound: 'default'),
      macOS: const DarwinNotificationDetails(),
    );

    await plugin.show(
      _kCallNotifId,
      'Appel entrant',
      callerName,
      details,
      payload: jsonEncode({'type': 'INCOMING_CALL', 'order_id': orderId, 'channel': channel}),
    );
  } catch (e) {
    _log('[showIncomingCallNotification] $e');
  }
}

/// Annule la notification d'appel entrant (après acceptation ou refus).
Future<void> cancelIncomingCallNotification() async {
  try {
    await FlutterLocalNotificationsPlugin().cancel(_kCallNotifId);
  } catch (_) {}
}

/// Notification locale simple — sans RemoteMessage (utilisé pour le tracking artisan)
Future<void> showSimpleLocalNotification({
  required int id,
  required String title,
  required String body,
}) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@drawable/ic_stat_ic_notification');
    const darwin = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );
    await plugin.initialize(const InitializationSettings(android: android, iOS: darwin, macOS: darwin));
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId, _kChannelName,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        sound: _kSound,
        icon: '@drawable/ic_stat_ic_notification',
        autoCancel: true,
      ),
      iOS: DarwinNotificationDetails(sound: _kIosSound),
      macOS: DarwinNotificationDetails(),
    );
    await plugin.show(id, title, body, details);
  } catch (_) {}
}

/// Crée le channel Android haute importance une seule fois au démarrage.
Future<void> createNotificationChannel() async {
  if (!Platform.isAndroid) return;
  final plugin = FlutterLocalNotificationsPlugin();
  // Ancien canal (son par défaut) : retiré des réglages du téléphone.
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.deleteNotificationChannel(_kOldChannelId)
      .catchError((_) {});
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        _kChannelId,
        _kChannelName,
        importance: Importance.max,
        enableLights: true,
        playSound: true,
        sound: _kSound,
        showBadge: true,
      ));
}

Future<void> initFirebaseMessaging() async {
  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, provisional: false, sound: true);
  await registerNotificationListeners().catchError((e) {
    _log('Notification Listener REGISTRATION ERROR: $e');
  });
}

Future<bool> subscribeToFirebaseTopic() async {
  bool result = appStore.isSubscribedForPushNotification;
  if (appStore.isLoggedIn) {
    await initFirebaseMessaging();

    if (Platform.isIOS) {
      String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      if (apnsToken == null) {
        await 3.seconds.delay;
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      }

      _log('Apn Token=========${apnsToken}');
    }

    final fcmToken = await FirebaseMessaging.instance.getToken();
    _log('════════════════════════════════════════════');
    _log('FCM TOKEN: $fcmToken');
    _log('════════════════════════════════════════════');

    await FirebaseMessaging.instance.subscribeToTopic('user_${appStore.userId}').then((value) {
      result = true;
      _log("topic-----subscribed----> user_${appStore.userId}");
    });
    await FirebaseMessaging.instance.subscribeToTopic(USER_APP_TAG).then((value) {
      result = true;
      _log("topic-----subscribed----> $USER_APP_TAG");
    });
  }

  await appStore.setPushNotificationSubscriptionStatus(result);
  return result;
}

Future<bool> unsubscribeFirebaseTopic(int userId) async {
  bool result = appStore.isSubscribedForPushNotification;
  await FirebaseMessaging.instance.unsubscribeFromTopic('user_$userId').then((_) {
    result = false;
    _log("topic-----unsubscribed----> user_$userId");
  });
  await FirebaseMessaging.instance.unsubscribeFromTopic(USER_APP_TAG).then((_) {
    result = false;
    _log("topic-----unsubscribed----> $USER_APP_TAG");
  });

  await appStore.setPushNotificationSubscriptionStatus(result);
  return result;
}

/// Émet les événements LiveStream de rafraîchissement des listes de commandes.
/// [badge] : incrémente aussi le badge artisan si true.
/// Appeler depuis le thread principal (ou via Future.microtask).
void emitOrderListRefresh({bool badge = true}) {
  Future.microtask(() {
    OrderEvents.emit();
    try {
      if (appStore.userType == USER_TYPE_PROVIDER) {
        if (badge) {
          final n = artisanNotifBadge.value + 1;
          artisanNotifBadge.value = n;
          setValue(ARTISAN_NOTIF_BADGE_KEY, n);
        }
        LiveStream().emit(LIVESTREAM_ARTISAN_HOME_REFRESH, true);
        LiveStream().emit(LIVESTREAM_ARTISAN_ORDERS_REFRESH, true);
      } else {
        LiveStream().emit(LIVESTREAM_UPDATE_BOOKING_LIST, true);
        LiveStream().emit(LIVESTREAM_ORDERS_LIST_REFRESH, true);
      }
    } catch (_) {}
  });
}

/// Handler top-level — appelé depuis main() avant runApp() via [registerForegroundMessageListener].
void _handleForegroundMessage(RemoteMessage message) {
  _log('[FCM onMessage] ════ notification=${message.notification?.title} data=${message.data}');

  if (message.data['type'] == 'INCOMING_CALL') {
    final orderId = message.data['order_id']?.toString() ?? '';
    if (!MisonCallScreen.isOutgoing(orderId)) {
      MisonCallSession.dropStaleFor(orderId); // reste d'un appel précédent
      _openIncomingCall(message.data);
    }
    return; // un appel entrant ne modifie pas les données de commande
  }

  // Message du chat de commande : la notification suffit, l'écran de chat
  // reçoit le message par WebSocket s'il est ouvert.
  if (message.data['type'] == 'ORDER_CHAT_MESSAGE') {
    ChatUnreadStore.refresh();
    _showForegroundNotification(message);
    return;
  }
  if (message.data['type'] == 'SUPPORT_MESSAGE') ChatUnreadStore.refresh();

  // Commande prise par un autre prestataire (notification invisible) : elle
  // disparaît tout de suite des listes ; son détail, s'il est ouvert, se
  // recharge et indique qu'elle n'est plus disponible.
  if (message.data['type'] == 'ORDER_TAKEN') {
    emitOrderListRefresh(badge: false);
    return;
  }

  // Rafraîchit les listes pour tout autre type de FCM lié aux commandes.
  emitOrderListRefresh();

  if (message.data['type'] == 'PAYMENT_SUCCEEDED' || message.data['type'] == 'PAYMENT_FAILED') {
    final succeeded = message.data['type'] == 'PAYMENT_SUCCEEDED';
    TopToast.show(message: succeeded ? 'Paiement confirmé !' : 'Échec du paiement');
    LiveStream().emit(LIVESTREAM_ORDER_PAYMENT_UPDATE, message.data['order_id']?.toString() ?? '');
    return;
  }

  _showForegroundNotification(message);
}

/// Affiche la notification d'un message reçu app ouverte.
///
/// iOS l'affiche déjà lui-même (setForegroundNotificationPresentationOptions
/// alert: true dans main.dart) : créer en plus une notification locale la
/// faisait apparaître deux fois. Seul Android a besoin de la notification locale.
void _showForegroundNotification(RemoteMessage message) {
  final notif = message.notification;
  if (notif == null) {
    _log('[FCM onMessage] → notification field is null, skipping showNotification');
    return;
  }
  if (Platform.isIOS) return;
  _log('[FCM onMessage] → showNotification title="${notif.title}" body="${notif.body}"');
  showNotification(currentTimeStamp(), notif.title ?? '', parseHtmlString(notif.body ?? ''), message);
}

/// Enregistre le listener foreground UNE SEULE FOIS depuis main() avant runApp().
void registerForegroundMessageListener() {
  FirebaseMessaging.onMessage.listen(_handleForegroundMessage, onError: (e) {
    _log('[FCM onMessage] stream error: $e');
  });

  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    _log('[FCM] token refreshed → sending to backend');
    saveFcmTokenToBackend(newToken);
  });
}

Future<void> registerNotificationListeners() async {
  await FirebaseMessaging.instance.setAutoInitEnabled(true);

  // onMessageOpenedApp — app en arrière-plan, user tape la notif
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    handleNotificationClick(message);
  }, onError: (e) {
    _log("onMessageOpenedApp Error $e");
  });

  // getInitialMessage — app fermée, user tape la notif
  FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
    if (message != null) {
      handleNotificationClick(message);
    }
  }).catchError((e) {
    _log("getInitialMessage error : $e");
  });
}

void _openIncomingCall(Map<String, dynamic> data) {
  final orderId = data['order_id']?.toString() ?? '';
  final channel = data['channel']?.toString() ?? '';
  if (orderId.isEmpty) return;
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => MisonIncomingCallScreen(orderId: orderId, channel: channel),
    ),
  );
}

void handleNotificationClick(RemoteMessage message) {
  // Rafraîchit les listes dès que l'utilisateur ouvre l'app depuis une notif.
  // Pas de badge ici : déjà incrémenté à la réception.
  if (message.data['type'] != 'INCOMING_CALL' &&
      message.data['type'] != 'ORDER_CHAT_MESSAGE') {
    emitOrderListRefresh(badge: false);
  }

  if (message.data['url'] != null && message.data['url'] is String) {
    commonLaunchUrl(message.data['url'], launchMode: LaunchMode.externalApplication);
  }

  // Appel entrant (background/terminé → tap sur notif)
  if (message.data['type'] == 'INCOMING_CALL') {
    final orderId = message.data['order_id']?.toString() ?? '';
    if (!MisonCallScreen.isOutgoing(orderId)) _openIncomingCall(message.data);
    return;
  }

  // Chat de commande — ouvre directement la discussion
  if (message.data['type'] == 'ORDER_CHAT_MESSAGE') {
    final orderId = message.data['order_id']?.toString() ?? '';
    if (orderId.isNotEmpty) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => MisonOrderChatScreen(
            orderId: orderId,
            peerName: message.data['sender_name']?.toString() ?? '',
          ),
        ),
      );
    }
    return;
  }

  // Support (réponse de l'équipe, ex. facture) : ouvre le chat support
  if (message.data['type'] == 'SUPPORT_MESSAGE') {
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const SupportChatScreen()));
    return;
  }

  // Appel manqué : la conversation de la commande, où l'appel est affiché
  if (message.data['type'] == 'MISSED_CALL') {
    final orderId = message.data['order_id']?.toString() ?? '';
    if (orderId.isNotEmpty) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => MisonOrderChatScreen(orderId: orderId, peerName: ''),
      ));
    }
    return;
  }

  // Commande confirmée, prestataire trouvé ou désisté : le suivi sur la carte
  // (il passe tout seul au détail si la commande est déjà terminée). Déjà
  // affiché : rien à faire, il se met à jour de lui-même.
  const followTypes = {'ORDER_CONFIRMED', 'ORDER_ACCEPTED', 'ORDER_ARTISAN_RELEASED'};
  if (followTypes.contains(message.data['type'])) {
    final type = message.data['type'];
    final orderId = message.data['order_id']?.toString() ?? '';
    if (orderId.isNotEmpty && MisonOrderSearchingScreen.openOrderId != orderId) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => MisonOrderSearchingScreen(
          orderId: orderId,
          justConfirmed: type == 'ORDER_CONFIRMED',
          artisanReleased: type == 'ORDER_ARTISAN_RELEASED',
        ),
      ));
    }
    return;
  }

  // Notifications de commande (acceptée, en route, arrivé, frais, paiement,
  // terminée, annulée…) : le serveur envoie order_id → détail de la commande.
  // (mison_order_id : ancien format, conservé.)
  if (message.data.containsKey('order_id') || message.data.containsKey('mison_order_id')) {
    final orderId = (message.data['order_id'] ?? message.data['mison_order_id'])?.toString() ?? '';
    if (orderId.isNotEmpty) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => MisonOrderDetailScreen(orderId: orderId),
        ),
      );
    }
    return;
  }

  if (message.data.containsKey('is_chat')) {
    LiveStream().emit(LIVESTREAM_FIREBASE, 3);
  }
}

void showNotification(int id, String title, String message, RemoteMessage remoteMessage) async {
  try {
  _log('[showNotification] id=$id title="$title"');
  _log('[showNotification] data=${remoteMessage.data}');
  _log("User Message Image Url : ${remoteMessage.data["image_url"]} ");
  // Pas de ré-initialisation ici : le plugin est initialisé une fois dans
  // main() avec le gestionnaire d'appui global (onNotificationTap). Le
  // ré-initialiser à chaque notification écrasait ce gestionnaire : un appui
  // ouvrait la destination de la DERNIÈRE notification reçue, et cassait
  // l'appui sur « Appel entrant ». Les données voyagent dans le payload.
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        _kChannelId,
        _kChannelName,
        importance: Importance.max,
        enableLights: true,
        playSound: true,
        sound: _kSound,
        showBadge: true,
      ));

  // region image logic
  Future<String> _downloadAndSaveFile(String url, String fileName) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String filePath = '${directory.path}/$fileName';
    final http.Response response = await http.get(Uri.parse(url));
    final File file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);
    return filePath;
  }

  BigPictureStyleInformation? bigPictureStyleInformation = remoteMessage.data.containsKey("image_url")
      ? BigPictureStyleInformation(
          FilePathAndroidBitmap(await _downloadAndSaveFile(remoteMessage.data["image_url"], 'bigPicture')),
          largeIcon: FilePathAndroidBitmap(await _downloadAndSaveFile(remoteMessage.data["image_url"], 'largeIcon')),
        )
      : null;
  // endregion

  var androidPlatformChannelSpecifics = AndroidNotificationDetails(
    _kChannelId,
    _kChannelName,
    importance: Importance.max,
    visibility: NotificationVisibility.public,
    autoCancel: true,
    playSound: true,
    sound: _kSound,
    priority: Priority.high,
    icon: '@drawable/ic_stat_ic_notification',
    largeIcon: remoteMessage.data.containsKey("image_url") ? FilePathAndroidBitmap(await _downloadAndSaveFile(remoteMessage.data["image_url"], 'largeIcon')) : null,
    styleInformation: remoteMessage.data.containsKey("image_url") ? bigPictureStyleInformation : null,
  );

  var darwinPlatformChannelSpecifics = const DarwinNotificationDetails(sound: _kIosSound);

  var platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: darwinPlatformChannelSpecifics,
    macOS: darwinPlatformChannelSpecifics,
  );

  _log('[showNotification] calling show()');
  await flutterLocalNotificationsPlugin.show(
    id,
    title,
    parseHtmlString(message),
    platformChannelSpecifics,
    payload: jsonEncode(remoteMessage.data),
  );
  _log('[showNotification] show() done');
  } catch (e, st) {
    _log('[showNotification] ERROR: $e\n$st');
  }
}

/// Journaux de ce fichier : données sensibles toujours masquées (jetons,
/// codes, noms, numéros), voir log_redact.dart.
void _log(Object? value) => nb_log.log(redactForLog(value));
