import 'dart:async';
import 'dart:convert';

import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

/// Suggestion renvoyée par Nominatim avec adresse structurée
class NominatimSuggestion {
  final String displayName;
  final double lat;
  final double lon;
  final String mainText;   // ex: "Plateau"
  final String subText;    // ex: "Dakar, Sénégal"

  NominatimSuggestion({
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.mainText,
    required this.subText,
  });

  factory NominatimSuggestion.fromJson(Map<String, dynamic> json) {
    final address = json['address'] as Map<String, dynamic>? ?? {};

    final main = _buildMainText(address, json['display_name']?.toString() ?? '');
    final sub  = _buildSubText(address);

    return NominatimSuggestion(
      displayName: json['display_name']?.toString() ?? '',
      lat: double.tryParse(json['lat']?.toString() ?? '0') ?? 0,
      lon: double.tryParse(json['lon']?.toString() ?? '0') ?? 0,
      mainText: main,
      subText: sub,
    );
  }

  /// Construit une suggestion à partir d'une feature GeoJSON renvoyée par
  /// l'API Photon (komoot) — moteur d'autocomplétion bâti sur les données OSM.
  factory NominatimSuggestion.fromPhotonFeature(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final coords = (feature['geometry'] as Map<String, dynamic>?)?['coordinates']
            as List<dynamic>? ??
        const [0, 0];
    // GeoJSON: [lon, lat]
    final lon = double.tryParse(coords[0].toString()) ?? 0;
    final lat = double.tryParse(coords.length > 1 ? coords[1].toString() : '0') ?? 0;

    final name      = props['name']?.toString();
    final street     = props['street']?.toString();
    final district   = props['district']?.toString();
    final main = (name?.isNotEmpty ?? false)
        ? name!
        : (street?.isNotEmpty ?? false)
            ? street!
            : (district?.isNotEmpty ?? false)
                ? district!
                : (props['city']?.toString() ?? '');

    final city    = props['city']?.toString();
    final state   = props['state']?.toString();
    final country = props['country']?.toString();
    final subParts = <String>[
      if (city != null && city.isNotEmpty && city != main) city,
      if (state != null && state.isNotEmpty && state != city) state,
      if (country != null && country.isNotEmpty) country,
    ];
    final sub = subParts.take(2).join(', ');

    final displayParts = <String>[
      main,
      if (sub.isNotEmpty) sub,
    ];

    return NominatimSuggestion(
      displayName: displayParts.join(', '),
      lat: lat,
      lon: lon,
      mainText: main,
      subText: sub,
    );
  }

  /// Texte affiché dans le champ après sélection : "Quartier, Ville"
  String get shortName =>
      subText.isNotEmpty ? '$mainText, $subText' : mainText;

  static String _buildMainText(Map<String, dynamic> a, String fallback) {
    // Priorité : nom du lieu > quartier > rue > sous-localité
    final name        = a['name']?.toString();
    final suburb      = a['suburb']?.toString()
                     ?? a['neighbourhood']?.toString()
                     ?? a['quarter']?.toString()
                     ?? a['residential']?.toString();
    final road        = a['road']?.toString()
                     ?? a['pedestrian']?.toString()
                     ?? a['footway']?.toString();
    final sublocality = a['sublocality']?.toString()
                     ?? a['city_district']?.toString();

    final value = name ?? suburb ?? road ?? sublocality;
    if (value != null && value.isNotEmpty) return value;

    // Fallback : première partie du display_name
    final parts = fallback.split(',');
    return parts.first.trim();
  }

  static String _buildSubText(Map<String, dynamic> a) {
    final city    = a['city']?.toString()
                 ?? a['town']?.toString()
                 ?? a['village']?.toString()
                 ?? a['municipality']?.toString();
    final country = a['country']?.toString();

    if (city != null && country != null) return '$city, $country';
    if (city != null) return city;
    if (country != null) return country;
    return '';
  }
}

/// Champ d'adresse avec autocomplétion Nominatim (sans clé API).
/// Callback [onSelected] reçoit la suggestion avec mainText, subText, lat, lon.
class NominatimAddressField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final InputDecoration? decoration;
  final List<String> countryCodes;
  final void Function(NominatimSuggestion suggestion)? onSelected;

  /// Widget optionnel affiché à droite du champ (ex: bouton "Ma position"),
  /// masqué pendant la recherche (le spinner de recherche prend sa place).
  final Widget? suffixButton;

  const NominatimAddressField({
    Key? key,
    required this.controller,
    this.hintText = 'Rechercher une adresse...',
    this.decoration,
    this.countryCodes = const ['sn', 'ml', 'ci', 'bf', 'gn', 'ne', 'tg', 'bj', 'mr', 'gm'],
    this.onSelected,
    this.suffixButton,
  }) : super(key: key);

  @override
  State<NominatimAddressField> createState() => _NominatimAddressFieldState();
}

class _NominatimAddressFieldState extends State<NominatimAddressField> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  List<NominatimSuggestion> _suggestions = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _removeOverlay();
    _debounce?.cancel();
    super.dispose();
  }

  // Biais géographique vers Dakar/Sénégal pour favoriser les résultats locaux.
  static const double _biasLat = 14.6928;
  static const double _biasLon = -17.4467;

  // Boîte englobante Afrique de l'Ouest (Mauritanie/Sénégal → Niger/Bénin).
  // Photon ne fait qu'un boost de pertinence avec lat/lon seuls : pour une
  // requête courte/ambiguë ("plat", "da"...), les résultats mondiaux les plus
  // "importants" (Europe, etc.) passent souvent devant les résultats locaux et
  // finissent tous filtrés par countrycode côté client → liste vide. Le bbox
  // restreint la recherche elle-même à la zone, donc les résultats remontés
  // sont déjà pertinents.
  static const String _westAfricaBbox = '-17.5,4.3,16.0,27.3';

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      _removeOverlay();
      return;
    }

    if (mounted) setState(() => _isSearching = true);

    try {
      final allowedCodes =
          widget.countryCodes.map((c) => c.toLowerCase()).toSet();
      final url = Uri.parse(
        'https://photon.komoot.io/api/'
        '?q=${Uri.encodeComponent(query)}'
        '&lang=fr'
        '&limit=15'
        '&lat=$_biasLat'
        '&lon=$_biasLon'
        '&bbox=$_westAfricaBbox',
      );

      final response = await http
          .get(url, headers: {'User-Agent': 'MisonApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>? ?? [];

        _suggestions = features
            .map((e) => MapEntry(
                e as Map<String, dynamic>,
                ((e['properties'] as Map<String, dynamic>?)?['countrycode'])
                    ?.toString()
                    .toLowerCase()))
            .where((entry) => allowedCodes.contains(entry.value))
            .map((entry) => NominatimSuggestion.fromPhotonFeature(entry.key))
            .where((s) => s.mainText.isNotEmpty)
            .take(6)
            .toList();

        if (_suggestions.isNotEmpty) {
          _showOverlay();
        } else {
          _removeOverlay();
        }
      } else {
        log('Photon error: HTTP ${response.statusCode} — ${response.body}');
        _removeOverlay();
      }
    } catch (e) {
      log('Photon search failed: $e');
      _removeOverlay();
    }

    if (mounted) setState(() => _isSearching = false);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _search(value),
    );
  }

  void _select(NominatimSuggestion suggestion) {
    widget.controller.text = suggestion.shortName;
    widget.onSelected?.call(suggestion);
    _removeOverlay();
    if (mounted) setState(() => _suggestions = []);
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _buildOverlay();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _buildOverlay() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final cardColor = Theme.of(context).cardColor;

    return OverlayEntry(
      builder: (_) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 8,
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: borderColor),
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.location_on_outlined,
                        color: primaryColor, size: 20),
                    title: Text(
                      s.mainText,
                      style: primaryTextStyle(size: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: s.subText.isNotEmpty
                        ? Text(
                            s.subText,
                            style: secondaryTextStyle(size: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () => _select(s),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        onChanged: _onChanged,
        decoration: widget.decoration ??
            InputDecoration(
              hintText: widget.hintText,
              hintStyle: secondaryTextStyle(),
              prefixIcon: Icon(Icons.location_on_outlined,
                  color: primaryColor, size: 20),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : widget.suffixButton,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
      ),
    );
  }
}
