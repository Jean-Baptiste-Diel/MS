import 'dart:convert';
import 'dart:io';

import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nb_utils/nb_utils.dart';

/// Rappel « Commencer la prestation » chez le prestataire : dès qu'il est
/// arrivé chez le client et jusqu'au démarrage, une notification reste dans
/// la barre, même app fermée. Sur Android elle ne s'efface pas d'un geste ;
/// iOS ne le permet pas (elle reste jusqu'à ce qu'il la balaye).
///
/// Synchronisée à chaque chargement des commandes (liste ou détail) : elle
/// apparaît après l'arrivée et disparaît au démarrage, au désistement ou à
/// l'annulation.
class StartReminder {
  static const _channelId = 'start_reminder';
  static const _channelName = 'Prestation à commencer';
  static const _tag = 'start_reminder';
  static const _type = 'ORDER_START_REMINDER';

  /// Commandes dont le rappel est affiché (cette session).
  static final Set<String> _shown = {};

  static bool get _isArtisan => appStore.userType == USER_TYPE_PROVIDER;

  static bool _needsStart(MisonOrder order) => order.hasArrived;

  /// Une commande (écran de détail) : affiche ou retire son rappel.
  static Future<void> syncOrder(MisonOrder? order) async {
    if (!_isArtisan || order?.id == null) return;
    if (_needsStart(order!)) {
      await _show(order);
    } else {
      await cancel(order.id!);
    }
  }

  /// Toutes les commandes du prestataire (tableau de bord) : affiche les
  /// rappels nécessaires et retire tous les autres, y compris ceux restés
  /// d'une session précédente (commande annulée pendant que l'app était fermée).
  static Future<void> syncOrders(List<MisonOrder> orders) async {
    if (!_isArtisan) return;
    final waiting = orders.where((o) => o.id != null && _needsStart(o)).toList();
    final keep = waiting.map((o) => o.id!).toSet();
    for (final order in waiting) {
      await _show(order);
    }
    for (final orderId in {..._shown, ...await _activeOrderIds()}.difference(keep)) {
      await cancel(orderId);
    }
  }

  static Future<void> cancel(String orderId) async {
    _shown.remove(orderId);
    try {
      await FlutterLocalNotificationsPlugin().cancel(_idFor(orderId), tag: _tag);
    } catch (_) {}
  }

  static Future<void> _show(MisonOrder order) async {
    final orderId = order.id!;
    if (_shown.contains(orderId)) return;
    _shown.add(orderId);
    final client = order.client?.firstName?.trim() ?? '';
    try {
      await FlutterLocalNotificationsPlugin().show(
        _idFor(orderId),
        client.isEmpty ? 'Vous êtes chez le client' : 'Vous êtes chez $client',
        'Appuyez sur « Commencer la prestation » dans l\'app Mison pour démarrer.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Rappel tant que la prestation n\'a pas été commencée',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/ic_stat_ic_notification',
            tag: _tag,
            // Reste dans la barre jusqu'au démarrage
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
        ),
        // Appui : détail de la commande, bouton « Commencer » en bas.
        payload: jsonEncode({'type': _type, 'order_id': orderId}),
      );
    } catch (e) {
      _shown.remove(orderId);
      log('StartReminder: $e');
    }
  }

  /// Rappels encore affichés par le système (Android), même d'une session
  /// précédente.
  static Future<Set<String>> _activeOrderIds() async {
    if (!Platform.isAndroid) return {};
    try {
      final active = await FlutterLocalNotificationsPlugin().getActiveNotifications();
      return {
        for (final n in active)
          if (n.tag == _tag && n.payload != null)
            (jsonDecode(n.payload!) as Map)['order_id']?.toString() ?? '',
      }..remove('');
    } catch (_) {
      return {};
    }
  }

  /// Identifiant stable d'une commande (le hashCode de Dart peut changer d'un
  /// lancement à l'autre).
  static int _idFor(String orderId) {
    var hash = 0x811c9dc5;
    for (final unit in orderId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
