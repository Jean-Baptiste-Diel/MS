import 'dart:convert';

import 'package:booking_system_flutter/utils/constant.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

/// Itinéraire en voiture calculé par Google Directions (comme Google Maps).
class RouteEta {
  final int seconds;          // durée estimée, trafic compris si disponible
  final String durationText;  // ex. "12 min"
  final String distanceText;  // ex. "4,3 km"
  final int distanceMeters;   // distance par la route
  final String encodedPolyline;

  const RouteEta({
    required this.seconds,
    required this.durationText,
    required this.distanceText,
    required this.encodedPolyline,
    this.distanceMeters = 0,
  });

  /// Heure d'arrivée estimée, ex. "14:32".
  String get arrivalTime => formatArrivalTime(seconds);

  /// Tracé de l'itinéraire (décodé depuis la polyline Google).
  List<LatLng> get points => decodePolyline(encodedPolyline);
}

/// Décode une polyline encodée Google (algorithme standard).
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int shift = 0, result = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

/// Calcule l'itinéraire en voiture de [origin] à [destination], ou null en cas d'échec.
Future<RouteEta?> fetchDrivingRoute(LatLng origin, LatLng destination) async {
  final uri = Uri.parse(
    'https://maps.googleapis.com/maps/api/directions/json'
    '?origin=${origin.latitude},${origin.longitude}'
    '&destination=${destination.latitude},${destination.longitude}'
    '&mode=driving&departure_time=now&language=fr&key=$GOOGLE_PLACES_API_KEY',
  );
  try {
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = body['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      log('Directions: ${body['status']} ${body['error_message'] ?? ''}');
      return null;
    }
    final leg = routes[0]['legs'][0] as Map<String, dynamic>;
    // Avec departure_time=now, Google fournit la durée avec le trafic actuel.
    final duration = (leg['duration_in_traffic'] ?? leg['duration']) as Map<String, dynamic>?;
    return RouteEta(
      seconds: (duration?['value'] as num?)?.toInt() ?? 0,
      durationText: duration?['text']?.toString() ?? '',
      distanceText: leg['distance']?['text']?.toString() ?? '',
      distanceMeters: (leg['distance']?['value'] as num?)?.toInt() ?? 0,
      encodedPolyline: routes[0]['overview_polyline']['points'] as String,
    );
  } catch (e) {
    log('Directions error: $e');
    return null;
  }
}

/// Heure d'arrivée ("HH:mm") dans [etaSeconds] secondes.
String formatArrivalTime(int etaSeconds) {
  final arrival = DateTime.now().add(Duration(seconds: etaSeconds));
  return '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}';
}

/// Distance (à vol d'oiseau) à l'adresse sous laquelle l'ouvrier est « arrivé ».
/// Au-delà, il est seulement « à proximité » : annoncer l'arrivée à 50-100 m
/// (fin de rue, dernier virage) était trompeur.
const double kArrivalRadiusMeters = 30;

/// Au-delà de cette imprécision GPS (en mètres), on ne déclare pas l'arrivée :
/// un saut de position pourrait la déclencher à tort.
const double kMaxArrivalGpsAccuracyMeters = 50;
