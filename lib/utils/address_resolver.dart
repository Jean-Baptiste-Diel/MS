import 'dart:convert';
import 'dart:math' as math;

import 'package:booking_system_flutter/utils/constant.dart' show GOOGLE_PLACES_API_KEY;
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

/// Adresse retrouvée sur la carte à partir d'un texte saisi ou collé.
class ResolvedAddress {
  final String label;
  final String detail;
  final double lat;
  final double lon;

  /// Distance (km) au point de référence (position du client, sinon Dakar).
  final double distanceKm;

  const ResolvedAddress({
    required this.label,
    required this.detail,
    required this.lat,
    required this.lon,
    required this.distanceKm,
  });
}

/// Région de Dakar (Dakar, Pikine, Guédiawaye, Rufisque, Diamniadio…).
const _minLat = 14.55, _maxLat = 14.90, _minLon = -17.55, _maxLon = -17.05;
const _dakarLat = 14.6928, _dakarLon = -17.4467;

bool _inDakarRegion(double lat, double lon) =>
    lat >= _minLat && lat <= _maxLat && lon >= _minLon && lon <= _maxLon;

double _km(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180, dl = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Retrouve les lieux correspondant à [text] dans la région de Dakar, du plus
/// proche au plus éloigné du point de référence ([refLat]/[refLon] : position
/// du client si connue, sinon le centre de Dakar). Liste vide = introuvable.
///
/// Comprend, dans l'ordre :
/// 1. des coordonnées collées (« 14.6928, -17.4467 ») ;
/// 2. un lien Google Maps partagé depuis une autre app (lien court compris) ;
/// 3. un nom de lieu ou une adresse : OpenStreetMap (gratuit), puis Google en
///    secours pour les lieux qu'OpenStreetMap ne connaît pas.
Future<List<ResolvedAddress>> resolveAddress(String text, {double? refLat, double? refLon}) async {
  final query = text.trim();
  if (query.length < 3) return [];
  final rLat = refLat ?? _dakarLat, rLon = refLon ?? _dakarLon;

  ResolvedAddress point(double lat, double lon, String label, [String detail = '']) => ResolvedAddress(
        label: label,
        detail: detail,
        lat: lat,
        lon: lon,
        distanceKm: _km(rLat, rLon, lat, lon),
      );

  // 1-2. Coordonnées ou lien de carte collés
  final coords = await _coordinatesFromText(query);
  if (coords != null) {
    if (!_inDakarRegion(coords.$1, coords.$2)) return [];
    return [point(coords.$1, coords.$2, 'Position partagée', '${coords.$1.toStringAsFixed(5)}, ${coords.$2.toStringAsFixed(5)}')];
  }

  // 3a. OpenStreetMap (Photon), limité à la région de Dakar
  final results = <ResolvedAddress>[];
  try {
    final uri = Uri.parse('https://photon.komoot.io/api/'
        '?q=${Uri.encodeComponent(query)}&lang=fr&limit=8'
        '&lat=$rLat&lon=$rLon&bbox=$_minLon,$_minLat,$_maxLon,$_maxLat');
    final res = await http.get(uri, headers: {'User-Agent': 'MisonApp/1.0'}).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      for (final f in (jsonDecode(res.body)['features'] as List? ?? [])) {
        final coordsList = (f['geometry']?['coordinates'] as List?) ?? const [];
        if (coordsList.length < 2) continue;
        final lon = (coordsList[0] as num).toDouble(), lat = (coordsList[1] as num).toDouble();
        if (!_inDakarRegion(lat, lon)) continue;
        final p = f['properties'] as Map? ?? {};
        final label = (p['name'] ?? p['street'] ?? '').toString();
        if (label.isEmpty) continue;
        final detail = [p['street'], p['district'], p['city']]
            .where((e) => e != null && e.toString().isNotEmpty && e.toString() != label)
            .toSet()
            .join(', ');
        results.add(point(lat, lon, label, detail));
      }
    }
  } catch (e) {
    log('resolveAddress photon: $e');
  }

  // 3b. Google en secours (lieux absents d'OpenStreetMap) : payant, donc
  // seulement quand OpenStreetMap n'a rien trouvé.
  if (results.isEmpty) {
    try {
      final uri = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json'
          '?address=${Uri.encodeComponent(query)}'
          '&components=country:SN'
          '&bounds=$_minLat,$_minLon|$_maxLat,$_maxLon'
          '&language=fr&key=$GOOGLE_PLACES_API_KEY');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in (body['results'] as List? ?? [])) {
          // Résultat au niveau du pays ou de la région entière : trop vague.
          final types = (r['types'] as List? ?? []).map((e) => e.toString()).toSet();
          if (types.contains('country') || types.contains('administrative_area_level_1')) continue;
          final loc = r['geometry']?['location'];
          if (loc == null) continue;
          final lat = (loc['lat'] as num).toDouble(), lon = (loc['lng'] as num).toDouble();
          if (!_inDakarRegion(lat, lon)) continue;
          final formatted = r['formatted_address']?.toString() ?? query;
          final parts = formatted.split(',').map((e) => e.trim()).toList();
          results.add(point(lat, lon, parts.first, parts.skip(1).take(2).join(', ')));
        }
      } else {
        log('resolveAddress google: HTTP ${res.statusCode}');
      }
    } catch (e) {
      log('resolveAddress google: $e');
    }
  }

  // D'abord les lieux dont le nom correspond vraiment au texte, puis les
  // autres ; à pertinence égale, les plus proches. Sans doublons (~50 m).
  final words = _normalize(query).split(RegExp(r'[\s,]+')).where((w) => w.length > 1).toList();
  int tier(ResolvedAddress r) {
    final name = _normalize(r.label);
    if (words.every(name.contains)) return 0;
    if (words.every(_normalize('${r.label} ${r.detail}').contains)) return 1;
    return 2;
  }
  results.sort((a, b) {
    final t = tier(a).compareTo(tier(b));
    return t != 0 ? t : a.distanceKm.compareTo(b.distanceKm);
  });
  final unique = <ResolvedAddress>[];
  for (final r in results) {
    if (unique.every((u) => _km(u.lat, u.lon, r.lat, r.lon) > 0.05)) unique.add(r);
  }
  return unique.take(5).toList();
}

String _normalize(String text) {
  const from = 'àâäáãçéèêëíìîïñóòôöõúùûüÿ';
  const to = 'aaaaaceeeeiiiinooooouuuuy';
  final out = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}

/// Coordonnées dans un texte collé : « lat, lng » ou lien de carte.
Future<(double, double)?> _coordinatesFromText(String text) async {
  (double, double)? parse(String s) {
    final patterns = [
      RegExp(r'@(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'), // .../@14.69,-17.44,15z
      RegExp(r'[?&](?:q|query|ll|destination|daddr)=(-?\d{1,2}\.\d+)(?:,|%2C)\s*(-?\d{1,3}\.\d+)'),
      RegExp(r'!3d(-?\d{1,2}\.\d+)!4d(-?\d{1,3}\.\d+)'), // lien « place »
      RegExp(r'^\s*(-?\d{1,2}\.\d+)\s*[,; ]\s*(-?\d{1,3}\.\d+)\s*$'), // 14.69, -17.44
    ];
    for (final re in patterns) {
      final m = re.firstMatch(s);
      if (m != null) {
        final lat = double.tryParse(m.group(1)!), lon = double.tryParse(m.group(2)!);
        if (lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180) return (lat, lon);
      }
    }
    return null;
  }

  final direct = parse(text);
  if (direct != null) return direct;

  // Lien court partagé (maps.app.goo.gl, goo.gl/maps) : on suit la redirection.
  final link = RegExp(r'https?://(?:maps\.app\.goo\.gl|goo\.gl/maps|maps\.google\.[a-z.]+|www\.google\.[a-z.]+/maps)\S*')
      .firstMatch(text)
      ?.group(0);
  if (link == null) return null;
  try {
    final client = http.Client();
    var uri = Uri.parse(link);
    for (var i = 0; i < 5; i++) {
      final req = http.Request('GET', uri)..followRedirects = false;
      final res = await client.send(req).timeout(const Duration(seconds: 6));
      final found = parse(uri.toString());
      if (found != null) {
        client.close();
        return found;
      }
      final next = res.headers['location'];
      if (next == null) break;
      uri = uri.resolve(next);
    }
    client.close();
    return parse(uri.toString());
  } catch (e) {
    log('resolveAddress link: $e');
    return null;
  }
}
