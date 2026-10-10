import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/services/mison_call_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:nb_utils/nb_utils.dart' show navigatorKey;

/// Barre « Appel en cours » au-dessus de toute l'app quand l'écran d'appel a
/// été réduit : l'appel continue, un appui y ramène (comme WhatsApp).
class OngoingCallBanner extends StatefulWidget {
  final Widget child;

  const OngoingCallBanner({Key? key, required this.child}) : super(key: key);

  @override
  State<OngoingCallBanner> createState() => _OngoingCallBannerState();
}

class _OngoingCallBannerState extends State<OngoingCallBanner> {
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    MisonCallSession.current.addListener(_scheduleRefresh);
    MisonCallScreen.visibleCount.addListener(_scheduleRefresh);
  }

  @override
  void dispose() {
    MisonCallSession.current.removeListener(_scheduleRefresh);
    MisonCallScreen.visibleCount.removeListener(_scheduleRefresh);
    super.dispose();
  }

  /// L'écran d'appel change ces valeurs pendant qu'il se construit ou se
  /// ferme : Flutter refuse alors de redessiner la barre, qui restait figée
  /// (rien ne s'affichait en réduisant l'appel). On redessine après l'image en cours.
  void _scheduleRefresh() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted) setState(() {});
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final session = MisonCallSession.current.value;
    final showBar = session != null && !session.ended && MisonCallScreen.visibleCount.value <= 0;
    // Structure toujours identique : l'app (Navigator) n'est jamais reconstruite.
    return Column(
      children: [
        if (showBar) _Bar(session: session),
        Expanded(
          // La barre occupe déjà la zone de la barre d'état.
          child: MediaQuery.removePadding(context: context, removeTop: showBar, child: widget.child),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final MisonCallSession session;

  const _Bar({required this.session});

  void _reopen() {
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => MisonCallScreen(
        orderId: session.orderId,
        otherPartyName: session.otherPartyName,
        appId: session.appId,
        channel: session.channel,
        token: session.token,
        uid: session.uid,
        isCaller: session.isCaller,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.green.shade600,
      child: InkWell(
        onTap: _reopen,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
            child: AnimatedBuilder(
              animation: session,
              builder: (_, __) => Row(
                children: [
                  const Icon(Icons.call_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      session.isConnected
                          ? 'Appel en cours avec ${session.otherPartyName} · ${session.durationLabel}'
                          : 'Appel vers ${session.otherPartyName}…',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Text('Revenir', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 8),
                  // Raccrocher sans revenir sur l'écran d'appel.
                  Material(
                    color: Colors.redAccent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: session.hangUp,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.call_end_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
