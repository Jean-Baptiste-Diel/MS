import 'dart:async';
import 'dart:convert';

import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

/// Suggestion renvoyée par Nominatim (OpenStreetMap)
class NominatimSuggestion {
  final String displayName;
  final double lat;
  final double lon;

  NominatimSuggestion({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  factory NominatimSuggestion.fromJson(Map<String, dynamic> json) {
    return NominatimSuggestion(
      displayName: json['display_name'] ?? '',
      lat: double.tryParse(json['lat']?.toString() ?? '0') ?? 0,
      lon: double.tryParse(json['lon']?.toString() ?? '0') ?? 0,
    );
  }

  /// Nom court : "Quartier, Ville"
  String get shortName {
    final parts = displayName.split(',');
    if (parts.length >= 2) return '${parts[0].trim()}, ${parts[1].trim()}';
    return parts.first.trim();
  }
}

/// Champ d'adresse avec autocomplétion Nominatim (sans clé API).
/// Callback [onSelected] reçoit le nom court + lat/lon.
class NominatimAddressField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final InputDecoration? decoration;
  final List<String> countryCodes; // ex: ['sn', 'ml']
  final void Function(NominatimSuggestion suggestion)? onSelected;

  const NominatimAddressField({
    Key? key,
    required this.controller,
    this.hintText = 'Rechercher une adresse...',
    this.decoration,
    this.countryCodes = const ['sn'],
    this.onSelected,
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

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      _removeOverlay();
      return;
    }

    setState(() => _isSearching = true);

    try {
      final countryFilter = widget.countryCodes.join(',');
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json'
        '&addressdetails=1'
        '&limit=5'
        '&countrycodes=$countryFilter',
      );

      final response = await http.get(url, headers: {'User-Agent': 'MisonApp/1.0'});

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        _suggestions = data
            .map((e) => NominatimSuggestion.fromJson(e as Map<String, dynamic>))
            .toList();
        if (_suggestions.isNotEmpty) {
          _showOverlay();
        } else {
          _removeOverlay();
        }
      }
    } catch (_) {
      _removeOverlay();
    }

    if (mounted) setState(() => _isSearching = false);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  void _select(NominatimSuggestion suggestion) {
    widget.controller.text = suggestion.shortName;
    widget.onSelected?.call(suggestion);
    _removeOverlay();
    setState(() => _suggestions = []);
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

    return OverlayEntry(
      builder: (_) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
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
                        color: primaryColor, size: 18),
                    title: Text(s.shortName,
                        style: primaryTextStyle(size: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.displayName,
                        style: secondaryTextStyle(size: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
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
              prefixIcon:
                  Icon(Icons.location_on_outlined, color: primaryColor, size: 20),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
      ),
    );
  }
}
