import 'package:booking_system_flutter/component/mison_start_prestation_sheet.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/order_events.dart';
import 'package:booking_system_flutter/utils/route_eta.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nb_utils/nb_utils.dart';

/// Signale automatiquement au serveur que l'ouvrier est arrivé chez le client,
/// dès qu'une position le place à [kArrivalRadiusMeters] de l'adresse (GPS assez
/// précis). Appelé partout où l'app de l'ouvrier reçoit sa position : détail de
/// la commande, tableau de bord, écran de navigation.
///
/// Conséquences : fin de la mini-carte des deux côtés, bouton « Commencer la
/// prestation » chez l'ouvrier, notification « arrivé » chez le client.
class ArtisanArrivalReporter {
  static final Set<String> _reported = {};
  static final Set<String> _inFlight = {};

  static Future<void> check({
    required String orderId,
    required double? destLat,
    required double? destLng,
    required Position position,
  }) async {
    if (destLat == null || destLng == null) return;
    if (_reported.contains(orderId) || _inFlight.contains(orderId)) return;
    if (position.accuracy > kMaxArrivalGpsAccuracyMeters) return;

    final distance = Geolocator.distanceBetween(position.latitude, position.longitude, destLat, destLng);
    if (distance > kArrivalRadiusMeters) return;

    await markArrived(orderId);
  }

  /// Arrivée signalée (automatiquement, ou via « Je suis arrivé »).
  static Future<bool> markArrived(String orderId) async {
    if (_reported.contains(orderId)) return true;
    _inFlight.add(orderId);
    try {
      await artisanArrive(orderId);
      _reported.add(orderId);
      OrderEvents.emit(orderId); // rafraîchit le détail : bouton « Commencer »
      // Rappel « Commencer » dans la barre de notifications (voir StartReminder),
      // même si aucun écran de la commande n'est ouvert.
      getMisonOrderDetail(orderId).ignore();
      _promptStart(orderId);
      return true;
    } catch (e) {
      log('ArtisanArrivalReporter: $e');
      return false;
    } finally {
      _inFlight.remove(orderId);
    }
  }

  static final Set<String> _prompted = {};

  /// Sur les lieux : le panneau « Commencer la prestation » s'ouvre tout seul
  /// (une fois par commande), si l'app est à l'écran. Sinon, le rappel dans
  /// la barre de notifications prend le relais.
  static Future<void> _promptStart(String orderId) async {
    if (!_prompted.add(orderId)) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    HapticFeedback.mediumImpact();
    final started = await showMisonStartPrestationSheet(context, orderId: orderId);
    if (started) {
      OrderEvents.emit(orderId); // détail et listes à jour
      getMisonOrderDetail(orderId).ignore(); // retire le rappel de la barre
    }
  }
}
