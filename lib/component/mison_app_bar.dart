import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';

/// Couleurs de la marque (logo).
const Color kMisonGold = Color(0xFFC49716);
const Color kMisonDark = Color(0xFF3A3A3A);

/// Fond blanc des pages (même couleur que [DotGridBackground]) : l'en-tête
/// se fond dans la page.
const Color kMisonHeaderBg = Color(0xFFFFFFFF);

/// Gris clair des champs et options sur fond blanc (ex. panneaux).
const Color kMisonFieldBg = Color(0xFFF1F2F4);

/// En-tête commun : logo centré sur le fond de la page, titre de la page
/// en dessous (et contenu optionnel, ex. onglets).
class MisonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? subtitle;

  /// Élément affiché en face du titre, à droite (ex. bouton d'appel).
  final Widget? titleTrailing;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final List<Widget>? actions;

  static const double _toolbarHeight = 84;
  static const double _titleHeight = 40;

  const MisonAppBar({
    Key? key,
    this.title,
    this.subtitle,
    this.titleTrailing,
    this.bottom,
    this.leading,
    this.actions,
  }) : super(key: key);

  double get _titleBlockHeight =>
      title == null ? 0 : _titleHeight + (subtitle != null ? 18 : 0);

  @override
  Size get preferredSize => Size.fromHeight(
      _toolbarHeight + _titleBlockHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final hasBottom = title != null || bottom != null;

    return AppBar(
      backgroundColor: kMisonHeaderBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: _toolbarHeight,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      automaticallyImplyLeading: false,
      leading: leading,
      centerTitle: true,
      // Logo un peu plus bas dans la barre
      title: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Image.asset('assets/logo/logo_transparent.png', height: 58),
      ),
      actions: actions,
      bottom: hasBottom
          ? PreferredSize(
              preferredSize: Size.fromHeight(
                  _titleBlockHeight + (bottom?.preferredSize.height ?? 0)),
              // Pleine largeur : sinon l'AppBar centre ce bloc et le titre
              // n'est pas à gauche
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Padding(
                        // Même marge que le contenu des pages (16) : titre aligné sur la liste
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: boldTextStyle(color: kMisonDark, size: 22)),
                                  if (subtitle != null) subtitle!,
                                ],
                              ),
                            ),
                            if (titleTrailing != null) ...[
                              8.width,
                              titleTrailing!,
                            ],
                          ],
                        ),
                      ),
                    if (bottom != null) bottom!,
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
