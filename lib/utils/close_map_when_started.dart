import 'dart:async';

import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/order_events.dart';
import 'package:flutter/widgets.dart';

/// Pour les cartes du trajet (navigation du prestataire, suivi du client) :
/// dès que la prestation a commencé (ou est terminée / annulée), la carte se
/// ferme toute seule et on retrouve la page de la commande en dessous —
/// « Définir les frais de prestation » chez le prestataire, « Payer » chez le
/// client.
///
/// Déclencheurs : événement de commande (notification reçue, « Oui,
/// commencer »), retour dans l'app, et une vérification toutes les 30 s.
mixin CloseMapWhenOrderStarted<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  String get trackedOrderId;

  StreamSubscription<String?>? _orderSub;
  Timer? _orderPoll;
  bool _checking = false;
  bool _closed = false;

  void startWatchingOrderStart() {
    WidgetsBinding.instance.addObserver(this);
    _orderSub = OrderEvents.stream.listen((id) {
      if (id == null || id == trackedOrderId) _checkOrderStarted();
    });
    _orderPoll = Timer.periodic(const Duration(seconds: 30), (_) => _checkOrderStarted());
  }

  void stopWatchingOrderStart() {
    WidgetsBinding.instance.removeObserver(this);
    _orderSub?.cancel();
    _orderPoll?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkOrderStarted();
  }

  Future<void> _checkOrderStarted() async {
    if (_checking || _closed || !mounted) return;
    _checking = true;
    try {
      final order = (await getMisonOrderDetail(trackedOrderId)).data;
      if (order == null || !mounted || _closed) return;
      if (order.isBeforeStart) return; // pas encore commencée : la carte reste
      _closed = true;
      final route = ModalRoute.of(context);
      // removeRoute : ferme la carte même si un panneau est ouvert par-dessus.
      if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
    } catch (_) {
      // réseau : on réessaiera au prochain déclencheur
    } finally {
      _checking = false;
    }
  }
}
