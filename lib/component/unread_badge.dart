import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Pastille du nombre de messages non lus (comme WhatsApp), masquée à 0.
class UnreadBadge extends StatelessWidget {
  final ValueListenable<int> count;
  final Widget child;

  const UnreadBadge({super.key, required this.count, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: count,
      builder: (_, n, __) => Badge(
        isLabelVisible: n > 0,
        backgroundColor: kMisonGold,
        textColor: Colors.white,
        label: Text(n > 99 ? '99+' : '$n'),
        child: child,
      ),
    );
  }
}

/// Pastille ronde dorée avec le nombre, pour une ligne de conversation.
class UnreadCountBubble extends StatelessWidget {
  final int count;
  const UnreadCountBubble({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: kMisonGold, borderRadius: BorderRadius.circular(12)),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
