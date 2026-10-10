import 'dart:async';

import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold;
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/utils/call_status.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/firebase_messaging_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  StreamSubscription<String?>? _statusSub;
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
    _statusSub = callStatusStream(widget.orderId).listen(_onCallStatus);
  }

  /// L'appel a pris fin ailleurs : annulé par l'appelant, ou refusé depuis la
  /// notification / CallKit. L'écran n'a plus lieu d'être.
  void _onCallStatus(String? status) {
    if (!mounted || _isAccepting) return;
    if (status != kCallCancelled && status != kCallRejected && status != kCallMissed) return;
    FlutterRingtonePlayer().stop();
    cancelIncomingCallNotification();
    endCallKitForOrder(widget.orderId);
    if (status == kCallCancelled) {
      TopToast.show(message: 'Appel manqué de $_callerName');
    }
    Navigator.pop(context);
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
      endCallKitForOrder(widget.orderId);
      if (isNotFoundError(e)) {
        // Appel destiné à un autre compte (ex. ancien compte de ce téléphone) :
        // inutile de rester sur l'écran d'appel.
        TopToast.show(message: kOrderUnavailableMessage, type: TopToastType.error);
        Navigator.pop(context);
      } else {
        TopToast.show(message: 'Impossible de rejoindre l\'appel');
        // Déjà décroché depuis l'écran d'appel du téléphone : pas de boutons
        // ici, on ne reste pas bloqué sur « Connexion… ».
        if (widget.autoAccept) Navigator.pop(context);
      }
    }
  }

  Future<void> _decline() async {
    FlutterRingtonePlayer().stop();
    cancelIncomingCallNotification();
    _statusSub?.cancel(); // notre propre refus ne doit pas refermer l'écran une 2e fois
    // Libère la session système : sans cela l'appel suivant reste muet.
    endCallKitForOrder(widget.orderId);
    await markCallDeclined(widget.orderId);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    FlutterRingtonePlayer().stop();
    _pulseController.dispose();
    super.dispose();
  }

  /// Décroché depuis l'écran d'appel du téléphone (CallKit / notification) :
  /// pas de seconde sonnerie ni de boutons Refuser / Accepter, seulement
  /// « Connexion à l'appel… » le temps de rejoindre, puis l'écran d'appel.
  Widget _buildConnecting() {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.withValues(alpha: 0.12),
                  ),
                  child: Icon(Icons.phone_in_talk_rounded, color: Colors.green.shade600, size: 52),
                ),
                28.height,
                Text(_callerName,
                    style: boldTextStyle(size: 26, color: appTextPrimaryColor), textAlign: TextAlign.center),
                12.height,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green.shade600),
                    ),
                    10.width,
                    Text("Connexion à l'appel…",
                        style: secondaryTextStyle(size: 15, color: appTextSecondaryColor)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoAccept) return _buildConnecting();
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
                  color: kMisonGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Appel audio',
                  style: secondaryTextStyle(size: 14, color: kMisonGold),
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
