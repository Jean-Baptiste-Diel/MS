import 'dart:convert';

import 'package:booking_system_flutter/main.dart';
import 'package:nb_utils/nb_utils.dart';

/// Lieu enregistré par le client (Maison, Bureau…), proposé à la commande.
class FavoritePlace {
  final String label;
  final String address;
  final double lat;
  final double lon;

  const FavoritePlace({required this.label, required this.address, required this.lat, required this.lon});

  factory FavoritePlace.fromJson(Map<String, dynamic> json) => FavoritePlace(
        label: json['label']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'label': label, 'address': address, 'lat': lat, 'lon': lon};

  /// Même endroit (à ~20 m près) : pas de doublon dans les favoris.
  bool isSamePlace(double otherLat, double otherLon) =>
      (lat - otherLat).abs() < 0.0002 && (lon - otherLon).abs() < 0.0002;
}

/// Lieux favoris, gardés sur le téléphone pour le compte connecté.
class FavoritePlacesStore {
  static const maxPlaces = 10;

  static String get _key {
    final owner = [appStore.uid, appStore.userEmail, appStore.userContactNumber]
        .firstWhere((v) => v.isNotEmpty, orElse: () => 'guest');
    return 'mison_favorite_places_$owner';
  }

  static List<FavoritePlace> load() {
    try {
      final raw = getStringAsync(_key);
      if (raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => FavoritePlace.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<FavoritePlace> places) =>
      setValue(_key, jsonEncode(places.map((p) => p.toJson()).toList()));

  static FavoritePlace? find(double lat, double lon) =>
      load().where((p) => p.isSamePlace(lat, lon)).firstOrNull;

  /// Ajoute le lieu (ou renomme celui qui est au même endroit). false : liste pleine.
  static Future<bool> add(FavoritePlace place) async {
    final places = load();
    final index = places.indexWhere((p) => p.isSamePlace(place.lat, place.lon));
    if (index >= 0) {
      places[index] = place;
    } else {
      if (places.length >= maxPlaces) return false;
      places.add(place);
    }
    await _save(places);
    return true;
  }

  static Future<void> remove(FavoritePlace place) async {
    await _save(load().where((p) => !p.isSamePlace(place.lat, place.lon)).toList());
  }
}
