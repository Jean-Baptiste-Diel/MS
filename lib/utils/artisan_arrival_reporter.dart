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
      return true;
    } catch (e) {
      log('ArtisanArrivalReporter: $e');
      return false;
    } finally {
      _inFlight.remove(orderId);
    }
  }
}
