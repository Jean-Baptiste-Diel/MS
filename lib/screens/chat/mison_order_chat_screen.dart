import 'package:booking_system_flutter/screens/support_chat/support_chat_screen.dart';
import 'package:flutter/material.dart';

/// Chat privé entre le client et l'ouvrier ayant accepté la commande.
///
/// Réutilise l'écran de chat temps réel (WebSocket) du support : seule la
/// conversation ciblée change — ici celle rattachée à la commande.
class MisonOrderChatScreen extends StatefulWidget {
  final String orderId;
  final String peerName;

  const MisonOrderChatScreen({
    Key? key,
    required this.orderId,
    required this.peerName,
  }) : super(key: key);

  /// Discussions à l'écran (une commande peut être ouverte plusieurs fois).
  static final Map<String, int> _open = {};
  static bool isOpen(String orderId) => (_open[orderId] ?? 0) > 0;

  /// Ouvre la discussion, sauf si elle est déjà à l'écran : sinon deux
  /// discussions empilées, et deux « retour » pour la quitter.
  static Future<void> openOnce(NavigatorState? navigator, String orderId, {String peerName = ''}) async {
    if (navigator == null || orderId.isEmpty || isOpen(orderId)) return;
    await navigator.push(MaterialPageRoute(
      builder: (_) => MisonOrderChatScreen(orderId: orderId, peerName: peerName),
    ));
  }

  @override
  State<MisonOrderChatScreen> createState() => _MisonOrderChatScreenState();
}

class _MisonOrderChatScreenState extends State<MisonOrderChatScreen> {
  @override
  void initState() {
    super.initState();
    MisonOrderChatScreen._open.update(widget.orderId, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    final n = (MisonOrderChatScreen._open[widget.orderId] ?? 1) - 1;
    if (n <= 0) {
      MisonOrderChatScreen._open.remove(widget.orderId);
    } else {
      MisonOrderChatScreen._open[widget.orderId] = n;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peerName = widget.peerName;
    return SupportChatScreen(
      orderId: widget.orderId,
      title: peerName.isNotEmpty ? peerName : 'Discussion',
      emptyTitle: 'Démarrez la discussion',
      emptySubtitle:
          'Échangez directement avec ${peerName.isNotEmpty ? peerName : 'votre interlocuteur'} '
          'au sujet de cette commande.',
      emptyIcon: Icons.chat_bubble_outline_rounded,
      callPeerName: peerName,
    );
  }
}
