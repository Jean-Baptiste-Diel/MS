import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/services/mison_call_session.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart' show navigatorKey;

/// Barre « Appel en cours » au-dessus de toute l'app quand l'écran d'appel a
/// été réduit : l'appel continue, un appui y ramène (comme WhatsApp).
class OngoingCallBanner extends StatelessWidget {
  final Widget child;

  const OngoingCallBanner({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MisonCallSession?>(
      valueListenable: MisonCallSession.current,
      builder: (context, session, _) => ValueListenableBuilder<int>(
        valueListenable: MisonCallScreen.visibleCount,
        builder: (context, visibleScreens, _) {
          if (session == null || visibleScreens > 0) return child;
          return Column(
            children: [
              _Bar(session: session),
              Expanded(
                // La barre occupe déjà la zone de la barre d'état.
                child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
              ),
            ],
          );
        },
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
