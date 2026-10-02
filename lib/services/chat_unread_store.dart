import 'dart:async';

import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:nb_utils/nb_utils.dart' show HttpMethodType;

/// Nombre de messages non lus, comme les pastilles de WhatsApp : par commande
/// (liste des discussions), total des discussions (onglet), et support.
///
/// Mis à jour toutes les 30 s quand l'app est ouverte, au retour dans l'app,
/// à la réception d'un message (notification) et en quittant une conversation.
class ChatUnreadStore {
  ChatUnreadStore._();

  /// Non lus par commande (clé : id de la commande).
  static final ValueNotifier<Map<String, int>> byOrder = ValueNotifier(const {});

  /// Total des discussions client ↔ prestataire.
  static final ValueNotifier<int> ordersTotal = ValueNotifier(0);

  /// Conversation avec le support Mison.
  static final ValueNotifier<int> support = ValueNotifier(0);

  static Timer? _timer;
  static AppLifecycleListener? _lifecycle;
  static bool _loading = false;

  /// Démarre l'actualisation régulière (appelé par les tableaux de bord).
  static void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    _lifecycle ??= AppLifecycleListener(onResume: refresh);
    refresh();
  }

  static Future<void> refresh() async {
    if (_loading || !appStore.isLoggedIn) return;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) return;
    _loading = true;
    try {
      final data = await handleResponse(
        await buildHttpResponse('chat/conversations/unread', method: HttpMethodType.GET),
      );
      if (data is! Map) return;
      final orders = <String, int>{};
      (data['orders'] as Map? ?? {}).forEach((k, v) => orders[k.toString()] = (v as num).toInt());
      byOrder.value = orders;
      ordersTotal.value = (data['orders_total'] as num?)?.toInt() ?? 0;
      support.value = (data['support'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // Réseau indisponible : on garde les derniers chiffres.
    } finally {
      _loading = false;
    }
  }

  /// Déconnexion : plus de pastilles.
  static void clear() {
    byOrder.value = const {};
    ordersTotal.value = 0;
    support.value = 0;
  }
}
