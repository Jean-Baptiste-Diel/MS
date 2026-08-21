import 'dart:async';
import 'dart:io' show Platform;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/firebase_messaging_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

const _kOutgoingCallKey = 'outgoing_call_order_id';

class MisonCallScreen extends StatefulWidget {
  final String orderId;
  final String otherPartyName;
  final String appId;
  final String channel;
  final String token;
  final int uid;

  /// true = cet appareil a initié l'appel. L'appelé ne doit surtout pas être
  /// marqué « sortant », sinon son propre écran d'appel entrant est ignoré.
  final bool isCaller;

  const MisonCallScreen({
    Key? key,
    required this.orderId,
    required this.otherPartyName,
    required this.appId,
    required this.channel,
    required this.token,
    required this.uid,
    this.isCaller = false,
  }) : super(key: key);

  // Orders for which the current user is the CALLER (not the callee).
  // Used by FCM handler to skip INCOMING_CALL notifications on the caller's device.
  static final Set<String> _outgoingOrderIds = {};

  static Future<void> markOutgoing(String orderId) async {
    _outgoingOrderIds.add(orderId);
    await _saveOutgoing(orderId);
  }

  static void clearOutgoing(String orderId) {
    _outgoingOrderIds.remove(orderId);
    _clearSavedOutgoing(orderId);
  }

  static Future<void> _saveOutgoing(String orderId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kOutgoingCallKey, orderId);
    } catch (_) {}
  }

  static Future<void> _clearSavedOutgoing(String orderId) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getString(_kOutgoingCallKey) == orderId) await p.remove(_kOutgoingCallKey);
    } catch (_) {}
  }

  static bool isOutgoing(String orderId) => _outgoingOrderIds.contains(orderId);

  @override
  State<MisonCallScreen> createState() => _MisonCallScreenState();
}

class _MisonCallScreenState extends State<MisonCallScreen> {
  late RtcEngine _engine;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  int _callSeconds = 0;
  Timer? _callTimer;
  bool _engineReady = false;
  bool _hasLeft = false;
  bool _engineCreated = false;
  bool _micDenied = false;
  StreamSubscription<DocumentSnapshot>? _callStatusSub;

  @override
  void initState() {
    super.initState();
    if (widget.isCaller) MisonCallScreen.markOutgoing(widget.orderId);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _initAgora();
    if (widget.isCaller) _listenCallStatus();
  }

  void _listenCallStatus() {
    _callStatusSub = FirebaseFirestore.instance
        .collection('call_status')
        .doc(widget.orderId)
        .snapshots()
        .listen((snap) {
      if (snap.data()?['status'] == 'rejected' && !_isConnected && mounted) {
        _callStatusSub?.cancel();
        _hasLeft = true;
        _callTimer?.cancel();
        if (_engineCreated) {
          _engine.leaveChannel();
          _engine.release();
        }
        _endCallKitSession();
        showSimpleLocalNotification(
          id: 9010,
          title: 'Appel refusé',
          body: '${widget.otherPartyName} a refusé l\'appel.',
        );
        TopToast.show(message: '${widget.otherPartyName} a refusé l\'appel');
        if (mounted) Navigator.pop(context);
      }
    });
  }

  Future<void> _initAgora() async {
    // Sans micro accordé, l'appel se connecte mais reste muet des deux côtés.
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (!mounted) return;
      setState(() => _micDenied = true);
      TopToast.show(
        message: 'Micro refusé : autorisez le microphone pour passer un appel',
        type: TopToastType.error,
      );
      if (micStatus.isPermanentlyDenied) await openAppSettings();
      await _endCallKitSession();
      if (mounted) Navigator.pop(context);
      return;
    }

    _engine = createAgoraRtcEngine();
    _engineCreated = true;
    await _engine.initialize(RtcEngineContext(
      appId: widget.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    // iOS : CallKit possède la session audio. Sans ce paramètre, Agora la
    // reconfigure et le flux entrant devient inaudible.
    if (Platform.isIOS) {
      await _engine.setParameters('{"che.audio.keep.audiosession":true}');
    }

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) async {
        await _engine.setEnableSpeakerphone(_isSpeakerOn);
        // Indique au système (CallKit / notification Android) que l'appel est
        // établi : c'est ce qui libère le focus audio vers Agora.
        try {
          await FlutterCallkitIncoming.setCallConnected(widget.orderId);
        } catch (_) {}
        if (mounted) setState(() => _engineReady = true);
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        if (mounted) {
          setState(() => _isConnected = true);
          _startTimer();
        }
      },
      onUserOffline: (connection, remoteUid, reason) {
        _callTimer?.cancel();
        if (mounted) {
          TopToast.show(message: 'Appel terminé');
          Navigator.pop(context);
        }
      },
      onError: (err, msg) => log('Agora error: $err $msg'),
    ));

    await _engine.enableAudio();
    await _engine.muteAllRemoteAudioStreams(false);
    await _engine.setDefaultAudioRouteToSpeakerphone(true);
    await _engine.joinChannel(
      token: widget.token,
      channelId: widget.channel,
      uid: widget.uid,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
  }

  /// Termine la session CallKit — sur Android comme sur iOS, elle retient le
  /// focus audio tant qu'elle est active.
  Future<void> _endCallKitSession() async {
    try {
      await FlutterCallkitIncoming.endCall(widget.orderId);
    } catch (_) {}
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  String _formatDuration(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _hangUp() async {
    if (_hasLeft) return;
    _hasLeft = true;
    _callTimer?.cancel();
    await _endCallKitSession();
    if (_engineCreated) {
      await _engine.leaveChannel();
      await _engine.release();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    MisonCallScreen.clearOutgoing(widget.orderId);
    _callStatusSub?.cancel();
    _callTimer?.cancel();
    // Clean up Firestore doc so stale status doesn't affect future calls.
    FirebaseFirestore.instance
        .collection('call_status')
        .doc(widget.orderId)
        .delete()
        .catchError((_) {});
    // Clôture la session CallKit (iOS et Android) : sinon elle garde le focus
    // audio et l'appel suivant reste muet.
    FlutterCallkitIncoming.endCall(widget.orderId).catchError((_) {});
    if (!_hasLeft && _engineCreated) {
      _hasLeft = true;
      _engine.leaveChannel();
      _engine.release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.otherPartyName.trim().isNotEmpty
        ? widget.otherPartyName.trim()[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      body: DotGridBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ── Top bar ──────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.black, size: 28),
                      onPressed: _hangUp,
                    ),
                    const Spacer(),
                    Text('Appel audio', style: secondaryTextStyle(color: appTextSecondaryColor, size: 14)),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // ── Avatar + nom ─────────────────────────────────────────────────
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryColor.withValues(alpha: 0.12),
                        border: Border.all(
                          color: _isConnected
                              ? Colors.green.withValues(alpha: 0.6)
                              : primaryColor.withValues(alpha: 0.4),
                          width: 2.5,
                        ),
                      ),
                      child: Center(
                        child: Text(initials,
                            style: boldTextStyle(size: 44, color: primaryColor)),
                      ),
                    ),
                    28.height,
                    Text(
                      widget.otherPartyName,
                      style: boldTextStyle(size: 24, color: appTextPrimaryColor),
                      textAlign: TextAlign.center,
                    ),
                    12.height,
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        _micDenied
                            ? 'Microphone refusé'
                            : _isConnected
                                ? _formatDuration(_callSeconds)
                                : _engineReady
                                    ? 'En attente...'
                                    : 'Connexion...',
                        key: ValueKey(_isConnected ? 'timer' : 'waiting'),
                        style: secondaryTextStyle(
                          size: 16,
                          color: _isConnected ? Colors.green.shade600 : appTextSecondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Contrôles ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallButton(
                      icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: _isMuted ? 'Activer' : 'Muet',
                      color: _isMuted
                          ? Colors.redAccent.withValues(alpha: 0.85)
                          : Colors.white,
                      iconColor: _isMuted ? Colors.white : appTextPrimaryColor,
                      onTap: () async {
                        setState(() => _isMuted = !_isMuted);
                        await _engine.muteLocalAudioStream(_isMuted);
                      },
                    ),
                    _CallButton(
                      icon: Icons.call_end_rounded,
                      label: 'Raccrocher',
                      color: Colors.redAccent,
                      iconColor: Colors.white,
                      size: 68,
                      onTap: _hangUp,
                    ),
                    _CallButton(
                      icon: _isSpeakerOn
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      label: 'Haut-parleur',
                      color: _isSpeakerOn
                          ? primaryColor
                          : Colors.white,
                      iconColor: _isSpeakerOn ? Colors.white : appTextPrimaryColor,
                      onTap: () async {
                        setState(() => _isSpeakerOn = !_isSpeakerOn);
                        await _engine.setEnableSpeakerphone(_isSpeakerOn);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final double size;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    this.iconColor = Colors.white,
    this.size = 56,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: color == Colors.white
                  ? Border.all(color: borderColor)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: size * 0.42),
          ),
          8.height,
          Text(label, style: secondaryTextStyle(size: 13, color: appTextSecondaryColor)),
        ],
      ),
    );
  }
}
