import 'package:booking_system_flutter/screens/support_chat/support_chat_screen.dart';
import 'package:flutter/material.dart';

/// Chat privé entre le client et l'ouvrier ayant accepté la commande.
///
/// Réutilise l'écran de chat temps réel (WebSocket) du support : seule la
/// conversation ciblée change — ici celle rattachée à la commande.
class MisonOrderChatScreen extends StatelessWidget {
  final String orderId;
  final String peerName;

  const MisonOrderChatScreen({
    Key? key,
    required this.orderId,
    required this.peerName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SupportChatScreen(
      orderId: orderId,
      title: peerName.isNotEmpty ? peerName : 'Discussion',
      emptyTitle: 'Démarrez la discussion',
      emptySubtitle:
          'Échangez directement avec ${peerName.isNotEmpty ? peerName : 'votre interlocuteur'} '
          'au sujet de cette commande.',
      emptyIcon: Icons.chat_bubble_outline_rounded,
    );
  }
}
