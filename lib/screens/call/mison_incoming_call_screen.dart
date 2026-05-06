import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';

class MisonIncomingCallScreen extends StatefulWidget {
  final String orderId;
  final String channel;

  const MisonIncomingCallScreen({
    Key? key,
    required this.orderId,
    required this.channel,
  }) : super(key: key);

  @override
  State<MisonIncomingCallScreen> createState() =>
      _MisonIncomingCallScreenState();
}

class _MisonIncomingCallScreenState extends State<MisonIncomingCallScreen>
    with TickerProviderStateMixin {
  String _callerName = 'Votre artisan';
  bool _isAccepting = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadCallerName();
  }

  Future<void> _loadCallerName() async {
    try {
      final res = await getMisonOrderDetail(widget.orderId);
      final artisan = res.data?.artisan;
      if (artisan != null && mounted) {
        setState(() => _callerName = artisan.fullName.isNotEmpty
            ? artisan.fullName
            : 'Votre artisan');
      }
    } catch (_) {}
  }

  Future<void> _accept() async {
    setState(() => _isAccepting = true);
    try {
      final tokenData = await getCallToken(widget.orderId);
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
          ),
        ),
      );
    } catch (e) {
      setState(() => _isAccepting = false);
      toast('Impossible de rejoindre l\'appel');
    }
  }

  void _decline() => Navigator.pop(context);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1B2D),
      body: SafeArea(
        child: Column(
          children: [
            // ── Label ────────────────────────────────────────────────────────
            const Spacer(),
            Text(
              'Appel entrant',
              style: secondaryTextStyle(size: 15, color: Colors.white54),
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
                  color: Colors.green.withValues(alpha: 0.15),
                  border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.6),
                      width: 2.5),
                ),
                child: const Icon(Icons.phone_in_talk_rounded,
                    color: Colors.greenAccent, size: 52),
              ),
            ),
            28.height,

            // ── Nom ──────────────────────────────────────────────────────────
            Text(
              _callerName,
              style: boldTextStyle(size: 26, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            8.height,
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Appel audio',
                style: secondaryTextStyle(size: 13, color: primaryColor),
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
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
              style: secondaryTextStyle(size: 13, color: Colors.white70)),
        ],
      ),
    );
  }
}
