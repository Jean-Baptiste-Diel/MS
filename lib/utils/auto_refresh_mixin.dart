import 'dart:async';

import 'package:booking_system_flutter/utils/order_events.dart';
import 'package:flutter/widgets.dart';

/// Actualise une page automatiquement :
/// - toutes les [autoRefreshInterval] tant qu'elle est à l'écran (pas quand
///   une autre page est ouverte par-dessus, ni app en arrière-plan) ;
/// - dès le retour dans l'app ;
/// - immédiatement quand une commande change (notification reçue app ouverte :
///   prestation démarrée, prestataire arrivé, paiement…) ou qu'un bouton
///   d'action a réussi. Même recouverte par une autre page, elle se recharge
///   tout de suite : elle est déjà à jour quand on y revient.
///
/// [onAutoRefresh] doit recharger SANS indicateur de chargement : récupérer
/// les données, puis les remplacer (ex. `_future = Future.value(res)`), pour
/// que la page ne clignote pas.
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _autoRefreshTimer;
  AppLifecycleListener? _autoRefreshLifecycle;
  StreamSubscription<String?>? _orderEventsSub;
  Timer? _eventDebounce;
  bool _autoRefreshing = false;
  bool _refreshAgain = false;

  Duration get autoRefreshInterval => const Duration(seconds: 20);

  /// false : la page gère elle-même les changements de commande (OrderEvents).
  bool get refreshOnOrderEvents => true;

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
    if (!refreshOnOrderEvents) return;
    _orderEventsSub = OrderEvents.stream.listen((_) {
      // Plusieurs notifications d'affilée : une seule actualisation.
      _eventDebounce?.cancel();
      _eventDebounce = Timer(const Duration(milliseconds: 300), () => _runAutoRefresh(force: true));
    });
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _eventDebounce?.cancel();
    _orderEventsSub?.cancel();
    _autoRefreshLifecycle?.dispose();
  }

  void _scheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(autoRefreshInterval, (_) => _runAutoRefresh());
  }

  /// [force] : commande modifiée, on recharge même si une autre page est
  /// ouverte par-dessus (sinon, inutile : l'actualisation périodique attend).
  Future<void> _runAutoRefresh({bool force = false}) async {
    if (!mounted) return;
    if (_autoRefreshing) {
      if (force) _refreshAgain = true; // changement pendant un chargement : on recommence après
      return;
    }
    final route = ModalRoute.of(context);
    if (!force && route != null && !route.isCurrent) return;
    _autoRefreshing = true;
    try {
      await onAutoRefresh();
    } catch (_) {
      // Réseau indisponible : on garde les données affichées, nouvel essai au prochain tour.
    } finally {
      _autoRefreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        _runAutoRefresh(force: true);
      }
    }
  }
}
