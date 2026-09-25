import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Bouton « Voir tout › » de l'accueil : doré plein, texte blanc, flèche.
class MisonViewAllButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String label;

  const MisonViewAllButton({Key? key, this.onTap, this.label = 'Voir tout'}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: kMisonGold,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: kMisonGold.withValues(alpha: 0.30),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: boldTextStyle(color: Colors.white, size: 14)),
            2.width,
            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
