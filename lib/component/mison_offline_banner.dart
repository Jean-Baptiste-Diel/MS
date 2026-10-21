import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonDark;
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Petit bandeau « Vous êtes hors ligne » : la page affiche les dernières
/// informations enregistrées sur le téléphone.
class MisonOfflineBanner extends StatelessWidget {
  final EdgeInsetsGeometry margin;

  const MisonOfflineBanner({Key? key, this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 8)}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kMisonDark,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
        8.width,
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Vous êtes hors ligne', style: boldTextStyle(size: 13, color: Colors.white)),
              TextSpan(
                text: ' · dernières infos enregistrées',
                style: primaryTextStyle(size: 12, color: Colors.white.withValues(alpha: 0.75)),
              ),
            ]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}
