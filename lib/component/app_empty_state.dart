import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold;
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

enum AppEmptyStateType { empty, error, search }

/// Composant unifié pour tous les états vides (liste vide, recherche sans
/// résultat, erreur de chargement) — remplace les blocs Center/Column/Icon/Text
/// dupliqués dans chaque écran.
class AppEmptyState extends StatelessWidget {
  final AppEmptyStateType type;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final EdgeInsetsGeometry padding;

  const AppEmptyState({
    super.key,
    this.type = AppEmptyStateType.empty,
    this.title,
    this.subtitle,
    this.icon,
    this.onRetry,
    this.retryLabel,
    this.padding = const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
  });

  IconData get _defaultIcon {
    switch (type) {
      case AppEmptyStateType.error:
        return Icons.wifi_off_rounded;
      case AppEmptyStateType.search:
        return Icons.search_off_rounded;
      case AppEmptyStateType.empty:
        return Icons.inbox_rounded;
    }
  }

  String get _defaultTitle {
    switch (type) {
      case AppEmptyStateType.error:
        return 'Erreur de chargement';
      case AppEmptyStateType.search:
        return 'Aucun résultat';
      case AppEmptyStateType.empty:
        return 'Aucune donnée disponible';
    }
  }

  Color get _accentColor =>
      type == AppEmptyStateType.error ? Colors.redAccent : kMisonGold;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentColor.withValues(alpha: 0.08),
              ),
              child: Icon(icon ?? _defaultIcon,
                  size: 38, color: _accentColor.withValues(alpha: 0.75)),
            ),
            18.height,
            Text(
              title ?? _defaultTitle,
              style: boldTextStyle(size: 16),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              6.height,
              Text(
                subtitle!,
                style: secondaryTextStyle(size: 14),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              22.height,
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                    color: kMisonGold,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: kMisonGold.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Text(
                    retryLabel ?? 'Réessayer',
                    style: boldTextStyle(color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
