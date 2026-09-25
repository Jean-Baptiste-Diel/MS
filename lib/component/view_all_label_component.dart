import 'package:booking_system_flutter/component/mison_view_all_button.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

class ViewAllLabel extends StatelessWidget {
  final String label;
  final List? list;
  final VoidCallback? onTap;
  final int? labelSize;
  final TextStyle? trailingTextStyle;
  final bool? alwaysShowViewAll; // New parameter to always show View All button
  final int maxViewAllLength;
  /// Affiche "Voir tout" comme une pilule avec ombre (style bouton) au lieu
  /// d'un simple lien texte. Désactivé par défaut pour ne pas changer
  /// l'apparence des écrans existants qui utilisent ce composant.
  final bool usePillStyle;

  ViewAllLabel({
    required this.label,
    this.onTap,
    this.labelSize,
    this.list,
    this.trailingTextStyle,
    this.alwaysShowViewAll,
    this.maxViewAllLength = 4,
    this.usePillStyle = false,
  });

  bool isViewAllVisible(List list) => list.length >= maxViewAllLength;

  @override
  Widget build(BuildContext context) {
    final bool showViewAll = list == null
        ? true
        : (alwaysShowViewAll == true ? true : isViewAllVisible(list!));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: boldTextStyle(size: labelSize ?? LABEL_TEXT_SIZE)),
        if (!showViewAll)
          const SizedBox()
        else if (usePillStyle)
          // Bouton « Voir tout › » doré de l'accueil
          MisonViewAllButton(onTap: onTap, label: language.lblViewAll)
        else
          TextButton(
            onPressed: onTap,
            child: Text(language.lblViewAll, style: trailingTextStyle ?? secondaryTextStyle()),
          ),
      ],
    );
  }
}