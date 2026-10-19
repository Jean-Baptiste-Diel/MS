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

  /// Tests : une session sans moteur d'appel (ni micro, ni Agora).
  @visibleForTesting
  static MisonCallSession forTest({String orderId = 'o1', String otherPartyName = 'Awa'}) =>
      MisonCallSession._(
        orderId: orderId,
        otherPartyName: otherPartyName,
        appId: '',
        channel: '',
        token: '',
        uid: 1,
        isCaller: true,
      );

  RtcEngine? _engine;
  Timer? _timer;

  /// Identifiant de l'appel dans l'écran d'appel du téléphone (CallKit /
  /// notification) : appel sortant créé ici, ou appel entrant décroché.
  String? callKitId;
  /// Tonalité « ça sonne chez l'autre » jouée à l'appelant en attendant la réponse.
  bool _ringbackOn = false;
  static const _ringbackAsset = 'assets/sounds/ringback.wav';
  Timer? _noAnswerTimer;

  /// Appelant : sans réponse au bout de ce délai, l'appel se termine
  /// (« n'a pas répondu ») et s'affiche comme appel manqué dans la conversation.
  static const _noAnswerTimeout = Duration(seconds: 45);

  /// Appelé : délai pour retrouver l'appelant dans l'appel après le décroché.
  static const _calleeJoinTimeout = Duration(seconds: 25);
  StreamSubscription<String?>? _callStatusSub;

  bool engineReady = false;
  bool isConnected = false;

  /// Participants présents dans l'appel (côté Agora).
  final Set<int> _remoteUids = {};
  Timer? _offlineTimer;

  /// Appelant : l'appelé a décroché (signalé via call_status).
  bool _calleeAccepted = false;

  /// Moment où ce téléphone est entré dans l'appel (Agora).
  DateTime? _joinedAt;
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
      // Même appel (retour via la barre « Appel en cours ») : même jeton.
      // Un nouveau jeton = nouvel appel : l'ancienne session, restée ouverte
      // sans personne en face, était réutilisée et l'appel ne se connectait pas.
      if (existing.orderId == orderId && existing.token == token) return existing;
      existing._discard();
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

    if (ended) return;
    await _keepAliveInBackground();
    _listenCallStatus();
    if (isCaller) {
      _noAnswerTimer = Timer(_noAnswerTimeout, () {
        if (!isConnected) _end(message: "$otherPartyName n'a pas répondu", noAnswer: true);
      });
    } else {
      // Appelé : l'appelant a pu raccrocher pendant qu'on décrochait. Sans
      // personne en face, l'appel ne doit pas rester ouvert indéfiniment.
      _noAnswerTimer = Timer(_calleeJoinTimeout, () {
        if (!isConnected) _end(message: "$otherPartyName a raccroché");
      });
    }

    // Le moteur de l'appel précédent doit être libéré avant d'en recréer un.
    await _releasing;
    if (ended) return;
    final engine = createAgoraRtcEngine();
    _engine = engine;
    await engine.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
    // Terminé pendant l'initialisation : le moteur est déjà en cours de libération.
    if (ended || _engine != engine) return;

    // iOS : CallKit possède la session audio. Sans ce paramètre, Agora la
    // reconfigure et le flux entrant devient inaudible.
    if (Platform.isIOS) {
      await engine.setParameters('{"che.audio.keep.audiosession":true}');
    }

    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) async {
        _joinedAt = DateTime.now();
        // Indique au système (CallKit / notification Android) que l'appel est
        // établi : c'est ce qui libère le focus audio vers Agora.
        try {
          await connectCallKitForOrder(orderId);
        } catch (_) {}
        // Casque Bluetooth connecté : l'appel part dessus, sinon sur l'écouteur.
        await refreshAudioRoutes();
        await setAudioRoute(bluetoothAvailable ? kRouteBluetooth : kRouteEarpiece);
        engineReady = true;
        notifyListeners();
        // Appelé : il est dans l'appel parce qu'il a décroché → l'appelant
        // peut passer en « appel en cours ».
        if (!isCaller) markCallAccepted(orderId);
        // Appelant : tonalité d'attente jusqu'à la réponse (seulement chez lui).
        await _startRingback();
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        _remoteUids.add(remoteUid);
        _offlineTimer?.cancel();
        // Appelant : quelqu'un qui arrive bien après nous dans l'appel, c'est
        // l'appelé qui vient de décrocher (un reste d'appel précédent, lui,
        // est déjà là quand on arrive). Ne dépend plus seulement du signal
        // « accepted », qui pouvait ne jamais arriver : l'appel restait alors
        // bloqué sur « ça sonne ».
        final joinedAt = _joinedAt;
        if (isCaller && joinedAt != null &&
            DateTime.now().difference(joinedAt) > const Duration(seconds: 2)) {
          _calleeAccepted = true;
        }
        _maybeConnected();
      },
      onUserOffline: (connection, remoteUid, reason) {
        _remoteUids.remove(remoteUid);
        // Appelant, avant le décroché : c'est un reste d'appel précédent qui
        // quitte l'appel, pas l'appelé. On continue de sonner.
        if (isCaller && !_calleeAccepted) return;
        // Court délai : l'appelé qui rejoint avec le même identifiant fait
        // d'abord sortir son ancienne connexion.
        _offlineTimer?.cancel();
        _offlineTimer = Timer(const Duration(seconds: 2), () {
          if (_remoteUids.isEmpty) _end(message: 'Appel terminé');
        });
      },
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
    // Android, décroché depuis la notification d'appel : cet appel système
    // tient déjà l'app en vie. En créer un second laissait une notification
    // « Raccrocher » après l'appel, et celle du décroché ne raccrochait plus.
    if (Platform.isAndroid && !isCaller) {
      final ids = await callKitIdsFor(orderId, acceptedOnly: true);
      if (ids.isNotEmpty) {
        callKitId ??= ids.first;
        return;
      }
    }
    try {
      await FlutterCallkitIncoming.startCall(CallKitParams(
        id: callKitId = newCallKitId(),
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
  /// [callKitId] : l'appel système qui s'est terminé. Un ancien appel de la
  /// même commande qui se ferme (fin de l'appel précédent) ne doit pas
  /// raccrocher l'appel en cours.
  static void hangUpFromSystem(String orderId, {String callKitId = ''}) {
    final session = current.value;
    if (session == null || session.orderId != orderId) return;
    final own = session.callKitId;
    if (own != null && callKitId.isNotEmpty && own.toLowerCase() != callKitId.toLowerCase()) return;
    session.hangUp();
  }

  /// Nouvel appel entrant pour cette commande : une session encore ouverte
  /// pour elle est un reste de l'appel précédent (app suspendue en arrière-plan,
  /// fin d'appel manquée). Agora la reconnectait au canal : l'appelant se
  /// croyait en ligne pendant que ce téléphone sonnait encore, puis le
  /// décroché réutilisait cette vieille session et rien ne se connectait.
  static void dropStaleFor(String orderId) {
    final session = current.value;
    if (session != null && session.orderId == orderId && !session.ended) session._discard();
  }

  /// Moteur Agora d'une session terminée en cours de libération. Le moteur est
  /// unique dans l'app : une nouvelle session qui démarre pendant que
  /// l'ancienne le libère se faisait couper (décroché, mais rien ne passait).
  static Future<void> _releasing = Future.value();

  /// Ferme un reste d'appel précédent SANS toucher au nouvel appel : ni à
  /// l'écran d'appel du téléphone (CallKit / notification, qui portent le même
  /// numéro de commande), ni au statut partagé (un « cancelled » coupait
  /// l'appel qui sonne), ni à la conversation.
  void _discard() => _end(silent: true);

  Future<void> _startRingback() async {
    final engine = _engine;
    if (!isCaller || isConnected || ended || _ringbackOn || engine == null) return;
    try {
      final path = await engine.getAssetAbsolutePath(_ringbackAsset);
      if (path == null || isConnected || ended) return;
      // loopback : entendu uniquement par l'appelant, pas envoyé à l'appelé.
      await engine.startAudioMixing(filePath: path, loopback: true, cycle: -1);
      _ringbackOn = true;
    } catch (e) {
      log('MisonCallSession ringback: $e');
    }
  }

  Future<void> _stopRingback() async {
    if (!_ringbackOn) return;
    _ringbackOn = false;
    try {
      await _engine?.stopAudioMixing();
    } catch (_) {}
  }

  /// Appel établi : l'autre partie est dans l'appel et, côté appelant, elle a
  /// vraiment décroché. Avant, la seule présence de quelqu'un dans l'appel
  /// suffisait : un reste de l'appel précédent (téléphone de l'appelé encore
  /// connecté) faisait croire à l'appelant que l'appel avait commencé pendant
  /// que l'autre téléphone sonnait encore.
  void _maybeConnected() {
    if (isConnected || ended || _remoteUids.isEmpty) return;
    if (isCaller && !_calleeAccepted) return;
    _stopRingback();
    isConnected = true;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      seconds++;
      notifyListeners();
    });
    notifyListeners();
  }

  void _listenCallStatus() {
    _callStatusSub = callStatusStream(orderId).listen((status) {
      if (isCaller && status == kCallAccepted) {
        _calleeAccepted = true;
        _maybeConnected();
        return;
      }
      if (isConnected) return;
      if (!isCaller) {
        // Appelé : l'appelant a raccroché avant que l'appel soit établi.
        if (status == kCallCancelled) _end(message: "$otherPartyName a raccroché");
        return;
      }
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

  Future<void> _end({String? message, bool rejected = false, bool noAnswer = false, bool silent = false}) async {
    if (ended) return;
    ended = true;
    endMessage = message;
    _timer?.cancel();
    _noAnswerTimer?.cancel();
    _offlineTimer?.cancel();
    if (silent) {
      _callStatusSub?.cancel();
      await _stopRingback();
      notifyListeners();
      if (current.value == this) current.value = null;
      if (isCaller) MisonCallScreen.clearOutgoing(orderId);
      await _releaseEngine();
      return;
    }

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
    await _stopRingback();
    notifyListeners();
    if (current.value == this) current.value = null;
    if (isCaller) MisonCallScreen.clearOutgoing(orderId);

    // Clôture la session CallKit / le service Android : sinon elle garde le
    // focus audio et l'appel suivant reste muet. Puis tout appel encore
    // « en cours » dans le système (plus de notification « Appel en cours »).
    endCallKitForOrder(orderId).then((_) => endLeftoverConnectedCalls());
    if (isCaller && !isConnected && !rejected) {
      // Raccroché avant la réponse : la sonnerie doit s'arrêter chez l'appelé
      // (dans l'app comme dans la notification / CallKit).
      markCallCancelled(orderId);
    } else if (isConnected) {
      // Appel terminé normalement : plus rien à signaler. (Le statut est de
      // toute façon remis à zéro avant chaque nouvel appel.)
      resetCallStatus(orderId);
    }
    await _releaseEngine();
    if (rejected || noAnswer) {
      showSimpleLocalNotification(
        id: 9010,
        title: rejected ? 'Appel refusé' : 'Pas de réponse',
        body: message ?? '',
      );
    }
  }

  /// Quitte l'appel et libère le moteur Agora, à la suite des libérations
  /// précédentes ; la session suivante attend la fin avant de démarrer.
  Future<void> _releaseEngine() {
    final engine = _engine;
    _engine = null;
    if (engine == null) return _releasing;
    return _releasing = _releasing.then((_) async {
      try {
        await engine.leaveChannel();
        await engine.release();
      } catch (e) {
        log('MisonCallSession release: $e');
      }
    });
  }
}
