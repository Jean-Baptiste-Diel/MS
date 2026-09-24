import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';

/// Couleurs de la marque (logo).
const Color kMisonGold = Color(0xFFC49716);
const Color kMisonDark = Color(0xFF3A3A3A);

/// Même gris clair que [DotGridBackground] : l'en-tête se fond dans la page.
const Color kMisonHeaderBg = Color(0xFFF1F2F4);

/// En-tête commun : logo centré sur le fond de la page, titre de la page
/// en dessous (et contenu optionnel, ex. onglets).
class MisonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? subtitle;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final List<Widget>? actions;

  static const double _toolbarHeight = 72;
  static const double _titleHeight = 40;

  const MisonAppBar({
    Key? key,
    this.title,
    this.subtitle,
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
      title: Image.asset('assets/logo/logo_transparent.png', height: 58),
      actions: actions,
      bottom: hasBottom
          ? PreferredSize(
              preferredSize: Size.fromHeight(
                  _titleBlockHeight + (bottom?.preferredSize.height ?? 0)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!,
                              style: boldTextStyle(color: kMisonDark, size: 22)),
                          if (subtitle != null) subtitle!,
                        ],
                      ),
                    ),
                  if (bottom != null) bottom!,
                ],
              ),
            )
          : null,
    );
  }
}
