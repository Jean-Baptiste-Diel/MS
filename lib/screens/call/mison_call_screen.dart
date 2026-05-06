import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:permission_handler/permission_handler.dart';

class MisonCallScreen extends StatefulWidget {
  final String orderId;
  final String otherPartyName;
  final String appId;
  final String channel;
  final String token;
  final int uid;

  const MisonCallScreen({
    Key? key,
    required this.orderId,
    required this.otherPartyName,
    required this.appId,
    required this.channel,
    required this.token,
    required this.uid,
  }) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _initAgora();
  }

  Future<void> _initAgora() async {
    await [Permission.microphone].request();

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(appId: widget.appId));

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        _engine.setEnableSpeakerphone(true);
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
          toast('Appel terminé');
          Navigator.pop(context);
        }
      },
      onError: (err, msg) => log('Agora error: $err $msg'),
    ));

    await _engine.enableAudio();
    await _engine.setDefaultAudioRouteToSpeakerphone(true);
    await _engine.joinChannel(
      token: widget.token,
      channelId: widget.channel,
      uid: widget.uid,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  String _formatDuration(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _hangUp() async {
    _callTimer?.cancel();
    await _engine.leaveChannel();
    await _engine.release();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _engine.leaveChannel();
    _engine.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.otherPartyName.trim().isNotEmpty
        ? widget.otherPartyName.trim()[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1B2D),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white54, size: 28),
                    onPressed: _hangUp,
                  ),
                  const Spacer(),
                  Text('Appel audio', style: secondaryTextStyle(color: Colors.white54, size: 13)),
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
                  // Cercle avatar avec anneau animé
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor.withValues(alpha: 0.15),
                      border: Border.all(
                        color: _isConnected
                            ? Colors.greenAccent.withValues(alpha: 0.6)
                            : primaryColor.withValues(alpha: 0.4),
                        width: 2.5,
                      ),
                    ),
                    child: Center(
                      child: Text(initials,
                          style: boldTextStyle(size: 44, color: Colors.white)),
                    ),
                  ),
                  28.height,
                  Text(
                    widget.otherPartyName,
                    style: boldTextStyle(size: 24, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  12.height,
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      _isConnected
                          ? _formatDuration(_callSeconds)
                          : _engineReady
                              ? 'En attente...'
                              : 'Connexion...',
                      key: ValueKey(_isConnected ? 'timer' : 'waiting'),
                      style: secondaryTextStyle(
                        size: 16,
                        color: _isConnected ? Colors.greenAccent : Colors.white54,
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
                        ? Colors.redAccent.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.15),
                    onTap: () async {
                      setState(() => _isMuted = !_isMuted);
                      await _engine.muteLocalAudioStream(_isMuted);
                    },
                  ),
                  _CallButton(
                    icon: Icons.call_end_rounded,
                    label: 'Raccrocher',
                    color: Colors.redAccent,
                    size: 68,
                    onTap: _hangUp,
                  ),
                  _CallButton(
                    icon: _isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: 'Haut-parleur',
                    color: _isSpeakerOn
                        ? primaryColor.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.15),
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
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
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
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: size * 0.42),
          ),
          8.height,
          Text(label, style: secondaryTextStyle(size: 11, color: Colors.white54)),
        ],
      ),
    );
  }
}
