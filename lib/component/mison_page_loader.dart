import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:flutter/material.dart';

/// Indicateur de chargement des pages Mison : les points animés aux couleurs
/// de l'app (comme sur les autres pages), à la place du cercle standard.
class MisonPageLoader extends StatelessWidget {
  const MisonPageLoader({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(child: LoaderWidget(colors: [kMisonDark, kMisonGold]));
  }
}
