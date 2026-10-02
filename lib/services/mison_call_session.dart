import 'dart:async';
import 'dart:io' show Platform;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/utils/call_status.dart';
import 'package:booking_system_flutter/utils/firebase_messaging_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:permission_handler/permission_handler.dart';

/// Appel audio en cours (Agora), indépendant de l'écran d'appel.
///
/// L'écran n'est qu'une vue : le quitter (flèche « réduire », navigation, app
/// en arrière-plan) ne coupe pas l'appel. Seuls « Raccrocher », le départ de
/// l'autre partie ou un refus y mettent fin.
const kRouteEarpiece = 'earpiece';
const kRouteSpeaker = 'speaker';
const kRouteBluetooth = 'bluetooth';
const kRouteWired = 'wired';

class MisonCallSession extends ChangeNotifier {
  /// Appel en cours dans l'app (un seul à la fois).
  static final ValueNotifier<MisonCallSession?> current = ValueNotifier(null);

  /// Canal natif de la sortie audio (écouteur / haut-parleur / Bluetooth).
  /// iOS : CallKit garde la session audio (Agora n'y touche pas), c'est donc
  /// l'app qui bascule la sortie. Android : Agora gère le haut-parleur, le
  /// canal force l'écouteur ou le Bluetooth et liste les sorties.
  static const _audioRoute = MethodChannel('mison/audio_route');

  final String orderId;
  final String otherPartyName;
  final String appId;
  final String channel;
  final String token;
  final int uid;
  final bool isCaller;

  MisonCallSession._({
    required this.orderId,
    required this.otherPartyName,
    required this.appId,
    required this.channel,
    required this.token,
    required this.uid,
    required this.isCaller,
  });

  RtcEngine? _engine;
  Timer? _timer;
  Timer? _noAnswerTimer;

  /// Appelant : sans réponse au bout de ce délai, l'appel se termine
  /// (« n'a pas répondu ») et s'affiche comme appel manqué dans la conversation.
  static const _noAnswerTimeout = Duration(seconds: 45);
  StreamSubscription<String?>? _callStatusSub;

  bool engineReady = false;
  bool isConnected = false;
  bool isMuted = false;
  /// Sortie audio : 'earpiece', 'speaker', 'bluetooth' ou 'wired'.
  /// L'appel démarre sur l'écouteur (comme un appel téléphonique), ou sur le
  /// casque Bluetooth s'il y en a un de connecté.
  String audioRoute = kRouteEarpiece;

  /// Un casque / des écouteurs Bluetooth sont connectés au téléphone.
  bool bluetoothAvailable = false;
  String bluetoothName = '';

  bool get isSpeakerOn => audioRoute == kRouteSpeaker;
  bool micDenied = false;
  bool ended = false;
  int seconds = 0;

  /// Message à afficher quand l'appel se termine (ex. « Appel refusé »).
  String? endMessage;

  /// Démarre l'appel, ou renvoie celui déjà en cours pour cette commande.
  static MisonCallSession start({
    required String orderId,
    required String otherPartyName,
    required String appId,
    required String channel,
    required String token,
    required int uid,
    required bool isCaller,
  }) {
    final existing = current.value;
    if (existing != null && !existing.ended) {
      if (existing.orderId == orderId) return existing;
      existing.hangUp();
    }
    final session = MisonCallSession._(
      orderId: orderId,
      otherPartyName: otherPartyName,
      appId: appId,
      channel: channel,
      token: token,
      uid: uid,
      isCaller: isCaller,
    );
    current.value = session;
    // Casque branché / débranché pendant l'appel : le natif prévient.
    _audioRoute.setMethodCallHandler((call) async {
      if (call.method == 'routeChanged') await current.value?.refreshAudioRoutes();
    });
    session._init();
    return session;
  }

  String get durationLabel =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _init() async {
    // Sans micro accordé, l'appel se connecte mais reste muet des deux côtés.
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      micDenied = true;
      if (micStatus.isPermanentlyDenied) await openAppSettings();
      await _end(message: 'Micro refusé : autorisez le microphone pour passer un appel');
      return;
    }

    await _keepAliveInBackground();
    if (isCaller) {
      _listenCallStatus();
      _noAnswerTimer = Timer(_noAnswerTimeout, () {
        if (!isConnected) _end(message: "$otherPartyName n'a pas répondu", noAnswer: true);
      });
    }

    final engine = createAgoraRtcEngine();
    _engine = engine;
    await engine.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    // iOS : CallKit possède la session audio. Sans ce paramètre, Agora la
    // reconfigure et le flux entrant devient inaudible.
    if (Platform.isIOS) {
      await engine.setParameters('{"che.audio.keep.audiosession":true}');
    }

    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) async {
        // Indique au système (CallKit / notification Android) que l'appel est
        // établi : c'est ce qui libère le focus audio vers Agora.
        try {
          await FlutterCallkitIncoming.setCallConnected(orderId);
        } catch (_) {}
        // Casque Bluetooth connecté : l'appel part dessus, sinon sur l'écouteur.
        await refreshAudioRoutes();
        await setAudioRoute(bluetoothAvailable ? kRouteBluetooth : kRouteEarpiece);
        engineReady = true;
        notifyListeners();
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        isConnected = true;
        _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
          seconds++;
          notifyListeners();
        });
        notifyListeners();
      },
      onUserOffline: (connection, remoteUid, reason) => _end(message: 'Appel terminé'),
      // La sortie audio peut changer seule (casque, Bluetooth) : on reflète l'état réel.
      onAudioRoutingChanged: (_) => refreshAudioRoutes(),
      onError: (err, msg) => log('Agora error: $err $msg'),
    ));

    await engine.enableAudio();
    await engine.muteAllRemoteAudioStreams(false);
    await engine.setDefaultAudioRouteToSpeakerphone(false);
    await engine.joinChannel(
      token: token,
      channelId: channel,
      uid: uid,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
  }

  /// Déclare l'appel au système, ce qui donne un bouton « Raccrocher » hors de
  /// l'app (géré par main.dart → [hangUpFromSystem]) :
  /// - Android : service « appel en cours » (sans lui, le système suspend l'app
  ///   et coupe le micro en arrière-plan) + notification avec « Raccrocher ».
  /// - iOS : appel sortant CallKit (écran verrouillé, pastille verte). L'appelé
  ///   y est déjà, via l'appel entrant CallKit qu'il a accepté.
  Future<void> _keepAliveInBackground() async {
    if (Platform.isIOS && !isCaller) return;
    try {
      await FlutterCallkitIncoming.startCall(CallKitParams(
        id: orderId,
        nameCaller: otherPartyName,
        appName: 'MISON',
        handle: otherPartyName,
        type: 0, // audio
        extra: {'order_id': orderId, 'channel': channel},
        callingNotification: const NotificationParams(
          showNotification: true,
          subtitle: 'Appel en cours…',
          isShowCallback: true, // bouton « Raccrocher » dans la notification
          callbackText: 'Raccrocher',
        ),
        android: const AndroidParams(
          isCustomNotification: false,
          isShowLogo: false,
          backgroundColor: '#0F1B2D',
          actionColor: '#4CAF50',
          incomingCallNotificationChannelName: 'Appels entrants',
          missedCallNotificationChannelName: 'Appels manqués',
        ),
        ios: const IOSParams(
          handleType: 'generic',
          supportsVideo: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          supportsDTMF: false,
          configureAudioSession: true,
        ),
      ));
    } catch (e) {
      log('MisonCallSession startCall: $e');
    }
  }

  /// « Raccrocher » depuis la notification Android ou l'interface CallKit iOS.
  static void hangUpFromSystem(String orderId) {
    final session = current.value;
    if (session != null && session.orderId == orderId) session.hangUp();
  }

  void _listenCallStatus() {
    _callStatusSub = callStatusStream(orderId).listen((status) {
      if (isConnected) return;
      if (status == kCallRejected) {
        _end(message: "$otherPartyName a refusé l'appel", rejected: true);
      } else if (status == kCallMissed) {
        _end(message: "$otherPartyName n'a pas répondu", noAnswer: true);
      }
    });
  }

  Future<void> toggleMute() async {
    isMuted = !isMuted;
    notifyListeners();
    await _engine?.muteLocalAudioStream(isMuted);
  }

  /// Bouton « Haut-parleur » (sans casque Bluetooth) : haut-parleur ↔ écouteur.
  Future<void> toggleSpeaker() =>
      setAudioRoute(isSpeakerOn ? (bluetoothAvailable ? kRouteBluetooth : kRouteEarpiece) : kRouteSpeaker);

  /// Lit les sorties disponibles et la sortie réellement utilisée.
  Future<void> refreshAudioRoutes() async {
    if (ended) return;
    try {
      final info = await _audioRoute.invokeMapMethod<String, dynamic>('getRoutes');
      if (info == null) return;
      bluetoothAvailable = info['bluetooth'] == true;
      bluetoothName = info['bluetoothName']?.toString() ?? '';
      final route = info['current']?.toString();
      if (route != null && route.isNotEmpty) audioRoute = route;
      notifyListeners();
    } catch (e) {
      log('MisonCallSession routes: $e');
    }
  }

  /// Bascule la sortie audio : écouteur, haut-parleur ou Bluetooth.
  Future<void> setAudioRoute(String route) async {
    // Android 12+ : le Bluetooth demande l'autorisation « Appareils à proximité »,
    // demandée seulement quand l'utilisateur choisit son casque.
    if (route == kRouteBluetooth && Platform.isAndroid) {
      final status = await Permission.bluetoothConnect.request();
      if (!status.isGranted && !status.isLimited && !status.isRestricted) {
        // Android < 12 : l'autorisation n'existe pas et est considérée accordée.
        if (status.isPermanentlyDenied) await openAppSettings();
        return;
      }
    }
    audioRoute = route;
    notifyListeners();
    try {
      if (Platform.isAndroid) {
        await _engine?.setEnableSpeakerphone(route == kRouteSpeaker);
      }
      await _audioRoute.invokeMethod('setRoute', route);
    } catch (e) {
      log('MisonCallSession route: $e');
    }
    // Le système peut refuser (casque déconnecté entre-temps) : état réel.
    await Future.delayed(const Duration(milliseconds: 400));
    await refreshAudioRoutes();
  }

  Future<void> hangUp() => _end();

  Future<void> _end({String? message, bool rejected = false, bool noAnswer = false}) async {
    if (ended) return;
    ended = true;
    endMessage = message;
    _timer?.cancel();
    _noAnswerTimer?.cancel();

    // Appelant : l'appel s'affiche dans la conversation de la commande
    // (abouti avec sa durée, refusé, ou sans réponse / annulé).
    if (isCaller && !micDenied) {
      logOrderCall(
        orderId,
        outcome: isConnected ? 'completed' : (rejected ? 'declined' : 'missed'),
        durationSeconds: seconds,
      );
    }
    _callStatusSub?.cancel();
    notifyListeners();
    if (current.value == this) current.value = null;
    if (isCaller) MisonCallScreen.clearOutgoing(orderId);

    // Clôture la session CallKit / le service Android : sinon elle garde le
    // focus audio et l'appel suivant reste muet.
    FlutterCallkitIncoming.endCall(orderId).catchError((_) {});
    if (isCaller && !isConnected && !rejected) {
      // Raccroché avant la réponse : la sonnerie doit s'arrêter chez l'appelé
      // (dans l'app comme dans la notification / CallKit).
      markCallCancelled(orderId);
    } else if (isConnected) {
      // Appel terminé normalement : plus rien à signaler. (Le statut est de
      // toute façon remis à zéro avant chaque nouvel appel.)
      resetCallStatus(orderId);
    }
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      try {
        await engine.leaveChannel();
        await engine.release();
      } catch (e) {
        log('MisonCallSession release: $e');
      }
    }
    if (rejected || noAnswer) {
      showSimpleLocalNotification(
        id: 9010,
        title: rejected ? 'Appel refusé' : 'Pas de réponse',
        body: message ?? '',
      );
    }
  }
}
