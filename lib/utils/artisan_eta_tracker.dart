import 'dart:async';

import 'package:booking_system_flutter/utils/route_eta.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nb_utils/nb_utils.dart';

/// Suivi partagé de l'arrivée de l'ouvrier pour une commande : une seule
/// écoute de sa position (Firestore) et un seul calcul Google Directions
/// (trafic compris) toutes les 1 min 30, quel que soit le nombre d'affichages
/// qui l'utilisent (ligne « Arrivée de l'ouvrier », carte de suivi…).
class ArtisanEtaTracker extends ChangeNotifier {
  /// Google Directions est payant à l'appel : un recalcul toutes les 1 min 30
  /// limite la facturation.
  static const refreshInterval = Duration(seconds: 90);

  static final Map<String, ArtisanEtaTracker> _instances = {};

  final String orderId;
  final LatLng? destination;

  LatLng? artisanPosition;
  RouteEta? eta;

  int _refs = 0;
  bool _disposed = false;
  bool _fetching = false;
  DateTime? _lastFetch;
  StreamSubscription<DocumentSnapshot>? _sub;

  ArtisanEtaTracker._(this.orderId, this.destination);

  /// Récupère (ou crée) le suivi de [orderId]. Appeler [release] à la fin.
  static ArtisanEtaTracker acquire(String orderId, LatLng? destination) {
    final tracker = _instances.putIfAbsent(orderId, () => ArtisanEtaTracker._(orderId, destination).._start());
    tracker._refs++;
    return tracker;
  }

  void release() {
    _refs--;
    if (_refs > 0) return;
    _sub?.cancel();
    _instances.remove(orderId);
    _disposed = true;
    dispose();
  }

  void _start() {
    if (destination == null) return;
    _sub = FirebaseFirestore.instance
        .collection('artisan_locations')
        .doc(orderId)
        .snapshots()
        .listen(_onLocation, onError: (e) => log('ArtisanEtaTracker: $e'));
  }

  void _onLocation(DocumentSnapshot snap) {
    if (!snap.exists || _disposed) return;
    final data = snap.data() as Map<String, dynamic>;
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    artisanPosition = LatLng(lat, lng);
    notifyListeners();
    _refresh();
  }

  Future<void> _refresh() async {
    final origin = artisanPosition;
    final dest = destination;
    if (origin == null || dest == null || _fetching) return;
    final now = DateTime.now();
    if (_lastFetch != null && now.difference(_lastFetch!) < refreshInterval) return;

    _fetching = true;
    _lastFetch = now;
    try {
      final result = await fetchDrivingRoute(origin, dest);
      if (result != null && !_disposed) {
        eta = result;
        notifyListeners();
      }
    } finally {
      _fetching = false;
    }
  }
}
