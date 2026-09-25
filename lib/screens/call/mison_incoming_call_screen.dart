import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/firebase_messaging_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

import '../../main.dart';

class MisonIncomingCallScreen extends StatefulWidget {
  final String orderId;
  final String channel;
  /// true when coming from a CallKit accept on iOS lock screen — skips ringing and auto-accepts.
  final bool autoAccept;

  const MisonIncomingCallScreen({
    Key? key,
    required this.orderId,
    required this.channel,
    this.autoAccept = false,
  }) : super(key: key);

  @override
  State<MisonIncomingCallScreen> createState() =>
      _MisonIncomingCallScreenState();
}

class _MisonIncomingCallScreenState extends State<MisonIncomingCallScreen>
    with TickerProviderStateMixin {
  String _callerName = 'Votre ouvrier';
  bool _isAccepting = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.autoAccept) {
      // User already accepted via CallKit lock screen — skip ringing, go straight to call.
      WidgetsBinding.instance.addPostFrameCallback((_) => _accept());
    } else {
      FlutterRingtonePlayer().playRingtone(looping: true, volume: 1.0);
    }
    _loadCallerName();
  }

  Future<void> _loadCallerName() async {
    try {
      final res = await getMisonOrderDetail(widget.orderId);
      final order = res.data;
      if (order == null || !mounted) return;
      // Show the OTHER party's name — the one who initiated the call.
      final isClient = appStore.userType == USER_TYPE_USER;
      final name = isClient
          ? (order.artisan?.fullName ?? '')
          : ('${order.client?.firstName ?? ''} ${order.client?.lastName ?? ''}'.trim());
      if (name.isNotEmpty) setState(() => _callerName = name);
    } catch (_) {}
  }

  Future<void> _accept() async {
    FlutterRingtonePlayer().stop();
    cancelIncomingCallNotification();
    setState(() => _isAccepting = true);
    try {
      // notify:false — on rejoint un appel déjà en cours, inutile de refaire
      // sonner l'appelant.
      final tokenData = await getCallToken(widget.orderId, notify: false);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MisonCallScreen(
            orderId: widget.orderId,
            otherPartyName: _callerName,
            appId: tokenData.appId ?? '',
            channel: tokenData.channel ?? widget.channel,
            token: tokenData.token ?? '',
            uid: tokenData.uid ?? 2,
            isCaller: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAccepting = false);
      FlutterCallkitIncoming.endCall(widget.orderId).catchError((_) {});
      if (isNotFoundError(e)) {
        // Appel destiné à un autre compte (ex. ancien compte de ce téléphone) :
        // inutile de rester sur l'écran d'appel.
        TopToast.show(message: kOrderUnavailableMessage, type: TopToastType.error);
        Navigator.pop(context);
      } else {
        TopToast.show(message: 'Impossible de rejoindre l\'appel');
      }
    }
  }

  Future<void> _decline() async {
    FlutterRingtonePlayer().stop();
    cancelIncomingCallNotification();
    // Libère la session système : sans cela l'appel suivant reste muet.
    FlutterCallkitIncoming.endCall(widget.orderId).catchError((_) {});
    await FirebaseFirestore.instance
        .collection('call_status')
        .doc(widget.orderId)
        .set({'status': 'rejected', 'at': FieldValue.serverTimestamp()})
        .catchError((_) {});
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    FlutterRingtonePlayer().stop();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: DotGridBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ── Label ────────────────────────────────────────────────────────
              const Spacer(),
              Text(
                'Appel entrant',
                style: secondaryTextStyle(size: 16, color: appTextSecondaryColor),
              ),
              20.height,

              // ── Icône pulsante ────────────────────────────────────────────────
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.withValues(alpha: 0.12),
                    border: Border.all(
                        color: Colors.green.withValues(alpha: 0.5),
                        width: 2.5),
                  ),
                  child: Icon(Icons.phone_in_talk_rounded,
                      color: Colors.green.shade600, size: 52),
                ),
              ),
              28.height,

              // ── Nom ──────────────────────────────────────────────────────────
              Text(
                _callerName,
                style: boldTextStyle(size: 26, color: appTextPrimaryColor),
                textAlign: TextAlign.center,
              ),
              8.height,
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Appel audio',
                  style: secondaryTextStyle(size: 14, color: primaryColor),
                ),
              ),

              const Spacer(),

              // ── Boutons ───────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 48, 52),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Refuser
                    _IncomingCallButton(
                      icon: Icons.call_end_rounded,
                      label: 'Refuser',
                      color: Colors.redAccent,
                      onTap: _decline,
                    ),
                    // Accepter
                    _IncomingCallButton(
                      icon: Icons.call_rounded,
                      label: 'Accepter',
                      color: Colors.green,
                      isLoading: _isAccepting,
                      onTap: _isAccepting ? null : _accept,
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

class _IncomingCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback? onTap;

  const _IncomingCallButton({
    required this.icon,
    required this.label,
    required this.color,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : Icon(icon, color: Colors.white, size: 32),
          ),
          12.height,
          Text(label,
              style: secondaryTextStyle(size: 14, color: appTextSecondaryColor)),
        ],
      ),
    );
  }
}
