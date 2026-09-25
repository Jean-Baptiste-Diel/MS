import 'dart:async';
import 'dart:io' show Platform;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/utils/firebase_messaging_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
class MisonCallSession extends ChangeNotifier {
  /// Appel en cours dans l'app (un seul à la fois).
  static final ValueNotifier<MisonCallSession?> current = ValueNotifier(null);

  /// Canal natif iOS : CallKit garde la session audio (Agora n'y touche pas),
  /// c'est donc l'app qui bascule la sortie haut-parleur / écouteur.
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
  StreamSubscription<DocumentSnapshot>? _callStatusSub;

  bool engineReady = false;
  bool isConnected = false;
  bool isMuted = false;
  bool isSpeakerOn = true;
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
    if (isCaller) _listenCallStatus();

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
        await _applySpeaker();
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
      onAudioRoutingChanged: (routing) {
        final speaker = routing == AudioRoute.routeSpeakerphone.value();
        if (speaker != isSpeakerOn && Platform.isAndroid) {
          isSpeakerOn = speaker;
          notifyListeners();
        }
      },
      onError: (err, msg) => log('Agora error: $err $msg'),
    ));

    await engine.enableAudio();
    await engine.muteAllRemoteAudioStreams(false);
    await engine.setDefaultAudioRouteToSpeakerphone(true);
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

  /// Android : sans service de premier plan, le système suspend l'app (et coupe
  /// le micro) dès qu'elle passe en arrière-plan. startCall lance le service
  /// « appel en cours » de flutter_callkit_incoming, avec sa notification.
  Future<void> _keepAliveInBackground() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterCallkitIncoming.startCall(CallKitParams(
        id: orderId,
        nameCaller: otherPartyName,
        appName: 'Mison',
        handle: otherPartyName,
        type: 0, // audio
        extra: {'order_id': orderId, 'channel': channel},
        android: const AndroidParams(
          isCustomNotification: false,
          isShowLogo: false,
          backgroundColor: '#0F1B2D',
          actionColor: '#4CAF50',
          incomingCallNotificationChannelName: 'Appels entrants',
          missedCallNotificationChannelName: 'Appels manqués',
        ),
      ));
    } catch (e) {
      log('MisonCallSession startCall: $e');
    }
  }

  void _listenCallStatus() {
    _callStatusSub = FirebaseFirestore.instance
        .collection('call_status')
        .doc(orderId)
        .snapshots()
        .listen((snap) {
      if (snap.data()?['status'] == 'rejected' && !isConnected) {
        _end(message: '$otherPartyName a refusé l\'appel', rejected: true);
      }
    });
  }

  Future<void> toggleMute() async {
    isMuted = !isMuted;
    notifyListeners();
    await _engine?.muteLocalAudioStream(isMuted);
  }

  Future<void> toggleSpeaker() async {
    isSpeakerOn = !isSpeakerOn;
    notifyListeners();
    await _applySpeaker();
  }

  Future<void> _applySpeaker() async {
    try {
      if (Platform.isIOS) {
        await _audioRoute.invokeMethod('setSpeaker', isSpeakerOn);
      } else {
        await _engine?.setEnableSpeakerphone(isSpeakerOn);
      }
    } catch (e) {
      log('MisonCallSession speaker: $e');
    }
  }

  Future<void> hangUp() => _end();

  Future<void> _end({String? message, bool rejected = false}) async {
    if (ended) return;
    ended = true;
    endMessage = message;
    _timer?.cancel();
    _callStatusSub?.cancel();
    notifyListeners();
    if (current.value == this) current.value = null;
    if (isCaller) MisonCallScreen.clearOutgoing(orderId);

    // Clôture la session CallKit / le service Android : sinon elle garde le
    // focus audio et l'appel suivant reste muet.
    FlutterCallkitIncoming.endCall(orderId).catchError((_) {});
    // Nettoie le statut Firestore pour ne pas influencer l'appel suivant.
    FirebaseFirestore.instance.collection('call_status').doc(orderId).delete().catchError((_) {});
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
    if (rejected) {
      showSimpleLocalNotification(id: 9010, title: 'Appel refusé', body: message ?? '');
    }
  }
}
