import 'dart:async';

import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/order_events.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Client : deux moments où l'écran reste sur la commande tant qu'il n'a pas
/// agi (voir [MisonOrder.clientMustAct]) :
///   1. l'ouvrier a proposé un prix → valider ou refuser ;
///   2. l'ouvrier a terminé la prestation → payer.
/// La page de la commande s'ouvre toute seule (ouverture de l'app, retour dans
/// l'app, notification reçue) et ne se ferme pas tant que c'est en attente.
class ClientOrderLock {
  static StreamSubscription<String?>? _sub;
  static Timer? _debounce;
  static bool _checking = false;

  /// Accueil client : écoute les changements de commande (notifications).
  static void start() {
    _sub ??= OrderEvents.stream.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), check);
    });
    check();
  }

  static Future<void> check() async {
    if (_checking) return;
    if (!appStore.isLoggedIn) return;
    final isArtisan = appStore.userType == USER_TYPE_PROVIDER;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _checking = true;
    try {
      final orders = (await getMisonOrders()).data ?? [];
      // Client : prix à valider / prestation à payer.
      // Ouvrier : prestation en cours (il reste dessus jusqu'à la terminer).
      final pending = orders.where((o) => o.id != null && (isArtisan ? o.isInProgress : o.clientMustAct));
      if (pending.isEmpty) return;
      final id = pending.first.id!;
      if (MisonOrderDetailScreen.isOpen(id)) return; // déjà à l'écran (et bloquée)
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => MisonOrderDetailScreen(orderId: id),
      ));
    } catch (e) {
      log('ClientOrderLock: $e');
    } finally {
      _checking = false;
    }
  }
}
