import 'dart:async';

import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/services/mison_call_session.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';
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

  /// Nombre d'écrans d'appel affichés : la barre « Appel en cours » est masquée
  /// quand l'écran d'appel est déjà à l'écran.
  static final ValueNotifier<int> visibleCount = ValueNotifier(0);

  @override
  State<MisonCallScreen> createState() => _MisonCallScreenState();
}

class _MisonCallScreenState extends State<MisonCallScreen> {
  /// L'appel vit dans la session : quitter cet écran (flèche, retour, app en
  /// arrière-plan) ne raccroche pas. La barre « Appel en cours » permet d'y revenir.
  late final MisonCallSession _session;

  @override
  void initState() {
    super.initState();
    if (widget.isCaller) MisonCallScreen.markOutgoing(widget.orderId);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _session = MisonCallSession.start(
      orderId: widget.orderId,
      otherPartyName: widget.otherPartyName,
      appId: widget.appId,
      channel: widget.channel,
      token: widget.token,
      uid: widget.uid,
      isCaller: widget.isCaller,
    );
    _session.addListener(_onSessionChanged);
    MisonCallScreen.visibleCount.value++;
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (_session.ended) {
      final message = _session.endMessage;
      if (message != null) {
        TopToast.show(
          message: message,
          type: _session.micDenied ? TopToastType.error : TopToastType.info,
        );
      }
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  /// Réduit l'écran : l'appel continue en arrière-plan.
  void _minimize() => Navigator.of(context).maybePop();

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    MisonCallScreen.visibleCount.value--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.otherPartyName.trim().isNotEmpty
        ? widget.otherPartyName.trim()[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
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
                      tooltip: "Réduire (l'appel continue)",
                      onPressed: _minimize,
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
                          color: _session.isConnected
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
                        _session.micDenied
                            ? 'Microphone refusé'
                            : _session.isConnected
                                ? _session.durationLabel
                                : _session.engineReady
                                    ? 'En attente...'
                                    : 'Connexion...',
                        key: ValueKey(_session.isConnected ? 'timer' : 'waiting'),
                        style: secondaryTextStyle(
                          size: 16,
                          color: _session.isConnected ? Colors.green.shade600 : appTextSecondaryColor,
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
                      icon: _session.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: _session.isMuted ? 'Activer' : 'Muet',
                      color: _session.isMuted
                          ? Colors.redAccent.withValues(alpha: 0.85)
                          : Colors.white,
                      iconColor: _session.isMuted ? Colors.white : appTextPrimaryColor,
                      onTap: _session.toggleMute,
                    ),
                    _CallButton(
                      icon: Icons.call_end_rounded,
                      label: 'Raccrocher',
                      color: Colors.redAccent,
                      iconColor: Colors.white,
                      size: 68,
                      onTap: _session.hangUp,
                    ),
                    _CallButton(
                      icon: _session.isSpeakerOn
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      label: 'Haut-parleur',
                      color: _session.isSpeakerOn
                          ? primaryColor
                          : Colors.white,
                      iconColor: _session.isSpeakerOn ? Colors.white : appTextPrimaryColor,
                      onTap: _session.toggleSpeaker,
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
