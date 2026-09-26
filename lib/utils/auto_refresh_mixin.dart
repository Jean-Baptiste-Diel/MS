import 'dart:async';

import 'package:flutter/widgets.dart';

/// Actualise une page automatiquement :
/// - toutes les [autoRefreshInterval] tant qu'elle est à l'écran (pas quand
///   une autre page est ouverte par-dessus, ni app en arrière-plan) ;
/// - dès le retour dans l'app.
///
/// [onAutoRefresh] doit recharger SANS indicateur de chargement : récupérer
/// les données, puis les remplacer (ex. `_future = Future.value(res)`), pour
/// que la page ne clignote pas.
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _autoRefreshTimer;
  AppLifecycleListener? _autoRefreshLifecycle;
  bool _autoRefreshing = false;

  Duration get autoRefreshInterval => const Duration(seconds: 20);

  Future<void> onAutoRefresh();

  void startAutoRefresh() {
    _autoRefreshLifecycle = AppLifecycleListener(
      onResume: () {
        _runAutoRefresh();
        _scheduleAutoRefresh();
      },
      onHide: () => _autoRefreshTimer?.cancel(),
    );
    _scheduleAutoRefresh();
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshLifecycle?.dispose();
  }

  void _scheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(autoRefreshInterval, (_) => _runAutoRefresh());
  }

  Future<void> _runAutoRefresh() async {
    if (!mounted || _autoRefreshing) return;
    // Une autre page est ouverte par-dessus : inutile de recharger celle-ci.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _autoRefreshing = true;
    try {
      await onAutoRefresh();
    } catch (_) {
      // Réseau indisponible : on garde les données affichées, nouvel essai au prochain tour.
    } finally {
      _autoRefreshing = false;
    }
  }
}
