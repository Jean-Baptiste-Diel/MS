import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Annulation / désistement : bouton discret, gris clair, sans fond, avec un
/// contour aux arrondis d'origine (14). L'action reste accessible sans attirer
/// l'œil. Même style partout (« Mes commandes », détail client et prestataire).
class MisonDiscreetCancelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  /// true : prend toute la largeur disponible, hauteur des gros boutons (52).
  final bool expanded;

  const MisonDiscreetCancelButton({
    Key? key,
    this.label = 'Annuler',
    required this.onTap,
    this.expanded = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey.shade600,
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: expanded ? 0 : 6),
        minimumSize: expanded ? const Size(double.infinity, 52) : Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: secondaryTextStyle(size: expanded ? 14 : 12, color: Colors.grey.shade600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
