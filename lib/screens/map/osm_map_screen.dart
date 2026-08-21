import 'dart:async';
import 'dart:convert';
import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/services/location_service.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../utils/constant.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

/// Modèle pour les suggestions de recherche
class PlaceSuggestion {
  final String displayName;
  final double lat;
  final double lon;
  final String? type;

  PlaceSuggestion({
    required this.displayName,
    required this.lat,
    required this.lon,
    this.type,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceSuggestion(
      displayName: json['display_name'] ?? '',
      lat: double.tryParse(json['lat']?.toString() ?? '0') ?? 0,
      lon: double.tryParse(json['lon']?.toString() ?? '0') ?? 0,
      type: json['type'],
    );
  }
  
  /// Retourne le nom court (première partie de l'adresse)
  String get shortName {
    final parts = displayName.split(',');
    if (parts.length >= 2) {
      return '${parts[0].trim()}, ${parts[1].trim()}';
    }
    return parts.first.trim();
  }
}

/// Écran de carte OpenStreetMap pour sélectionner une adresse
/// Gratuit et sans clé API
class OsmMapScreen extends StatefulWidget {
  final double? latitude;
  final double? longitude;

  const OsmMapScreen({Key? key, this.latitude, this.longitude}) : super(key: key);

  @override
  OsmMapScreenState createState() => OsmMapScreenState();
}

class OsmMapScreenState extends State<OsmMapScreen> {
  final MapController _mapController = MapController();
  
  LatLng? _selectedLocation;
  String _currentAddress = '';
  bool _isLoading = true;
  
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  
  // Search autocomplete
  List<PlaceSuggestion> _suggestions = [];
  bool _showSuggestions = false;
  bool _isSearching = false;
  Timer? _debounceTimer;
  
  // Coordonnées sélectionnées
  double? _selectedLat;
  double? _selectedLon;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Recherche des suggestions via Nominatim (OpenStreetMap)
  Future<void> _searchPlaces(String query) async {
    if (query.length < 2) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      // Utiliser Nominatim pour rechercher (privilégier le Sénégal)
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}, Sénégal'
        '&format=json'
        '&addressdetails=1'
        '&limit=5'
        '&countrycodes=sn',
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'MisonApp/1.0'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _suggestions = data.map((e) => PlaceSuggestion.fromJson(e)).toList();
          _showSuggestions = _suggestions.isNotEmpty;
        });
      }
    } catch (e) {
      log('Search error: $e');
    }

    setState(() => _isSearching = false);
  }

  /// Gérer la saisie de recherche avec debounce
  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchPlaces(value);
    });
  }

  /// Sélectionner une suggestion
  void _selectSuggestion(PlaceSuggestion suggestion) {
    setState(() {
      _selectedLocation = LatLng(suggestion.lat, suggestion.lon);
      _selectedLat = suggestion.lat;
      _selectedLon = suggestion.lon;
      _currentAddress = suggestion.shortName;
      _addressController.text = suggestion.shortName;
      _searchController.clear();
      _suggestions = [];
      _showSuggestions = false;
    });

    // Déplacer la carte vers la position sélectionnée
    _mapController.move(_selectedLocation!, 16.0);
  }

  Future<void> _initializeMap() async {
    setState(() => _isLoading = true);
    
    try {
      // Si des coordonnées sont fournies, les utiliser
      if (widget.latitude != null && widget.longitude != null) {
        _selectedLocation = LatLng(widget.latitude!, widget.longitude!);
        await _getAddressFromLatLng(_selectedLocation!);
      } else {
        // Sinon, obtenir la position actuelle
        await _getCurrentLocation();
      }
    } catch (e) {
      // Position par défaut: Dakar, Sénégal
      _selectedLocation = const LatLng(14.6928, -17.4467);
      _currentAddress = 'Dakar, Sénégal';
      _addressController.text = _currentAddress;
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await getUserLocationPosition();
      _selectedLocation = LatLng(position.latitude, position.longitude);
      await _getAddressFromLatLng(_selectedLocation!);
      
      _mapController.move(_selectedLocation!, 16.0);
    } catch (e) {
      // Position par défaut: Dakar
      _selectedLocation = const LatLng(14.6928, -17.4467);
      _currentAddress = 'Dakar, Sénégal';
      _addressController.text = _currentAddress;
    }
  }

  Future<void> _getAddressFromLatLng(LatLng position) async {
    // Sauvegarder les coordonnées
    _selectedLat = position.latitude;
    _selectedLon = position.longitude;
    
    try {
      // Utiliser Nominatim (OpenStreetMap) pour le reverse geocoding
      // Plus fiable que le package geocoding pour le Sénégal
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${position.latitude}'
        '&lon=${position.longitude}'
        '&format=json'
        '&addressdetails=1'
        '&accept-language=fr',
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'MisonApp/1.0'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        
        // Extraire les détails de l'adresse
        final address = data['address'] as Map<String, dynamic>?;
        
        if (address != null) {
          // Construire une adresse lisible avec quartier, ville, etc.
          final List<String> addressParts = [];
          
          // Nom du lieu ou numéro de rue
          if (data['name'] != null && data['name'].toString().isNotEmpty) {
            addressParts.add(data['name'].toString());
          }
          
          // Rue
          final road = address['road'] ?? address['street'];
          if (road != null && road.toString().isNotEmpty) {
            addressParts.add(road.toString());
          }
          
          // Quartier
          final neighbourhood = address['neighbourhood'] ?? 
                               address['suburb'] ?? 
                               address['quarter'] ??
                               address['residential'];
          if (neighbourhood != null && neighbourhood.toString().isNotEmpty) {
            addressParts.add(neighbourhood.toString());
          }
          
          // Commune/Arrondissement
          final commune = address['city_district'] ?? 
                         address['municipality'] ??
                         address['town'];
          if (commune != null && commune.toString().isNotEmpty) {
            addressParts.add(commune.toString());
          }
          
          // Ville
          final city = address['city'] ?? 
                      address['village'] ??
                      address['state_district'];
          if (city != null && city.toString().isNotEmpty && 
              !addressParts.contains(city.toString())) {
            addressParts.add(city.toString());
          }
          
          // Région
          final region = address['state'] ?? address['region'];
          if (region != null && region.toString().isNotEmpty &&
              !addressParts.contains(region.toString())) {
            addressParts.add(region.toString());
          }
          
          if (addressParts.isNotEmpty) {
            _currentAddress = addressParts.join(', ');
          } else {
            // Fallback sur display_name
            _currentAddress = data['display_name']?.toString() ?? 
                '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
          }
        } else {
          // Utiliser display_name si pas d'adresse détaillée
          _currentAddress = data['display_name']?.toString() ?? 
              '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        }
        
        _addressController.text = _currentAddress;
      } else {
        // Fallback sur les coordonnées en cas d'erreur
        _currentAddress = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        _addressController.text = _currentAddress;
      }
    } catch (e) {
      log('Reverse geocoding error: $e');
      // Fallback: essayer avec le package geocoding
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          _currentAddress = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
          ].where((s) => s != null && s.isNotEmpty).join(', ');
          
          _addressController.text = _currentAddress;
        } else {
          _currentAddress = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
          _addressController.text = _currentAddress;
        }
      } catch (e2) {
        _currentAddress = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        _addressController.text = _currentAddress;
      }
    }
    
    setState(() {});
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) async {
    setState(() {
      _selectedLocation = point;
      _selectedLat = point.latitude;
      _selectedLon = point.longitude;
      _isLoading = true;
      _showSuggestions = false;
    });
    
    await _getAddressFromLatLng(point);
    
    setState(() => _isLoading = false);
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  void _goToCurrentLocation() async {
    setState(() => _isLoading = true);
    await _getCurrentLocation();
    setState(() => _isLoading = false);
  }

  void _confirmAddress() {
    if (_addressController.text.isNotEmpty && _selectedLat != null && _selectedLon != null) {
      // Retourner un Map avec nom et coordonnées
      final result = {
        'name': _addressController.text,
        'lat': _selectedLat,
        'lon': _selectedLon,
      };
      finish(context, result);
    } else if (_addressController.text.isNotEmpty) {
      // Fallback: retourner juste le nom
      finish(context, {'name': _addressController.text});
    } else {
      TopToast.show(message: language.lblPickAddress.validate());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarWidget(
        language.chooseYourLocation,
        backWidget: BackWidget(),
        color: primaryColor,
        elevation: 0,
        textColor: white,
        textSize: APP_BAR_TEXT_SIZE,
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation ?? const LatLng(14.6928, -17.4467),
              initialZoom: 14.0,
              onTap: _onMapTap,
            ),
            children: [
              // OpenStreetMap tile layer
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mison.app',
                maxZoom: 19,
              ),
              // Marker layer
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          
          // Zoom controls
          Positioned(
            left: 10,
            top: 100,
            child: Column(
              children: [
                _ZoomButton(
                  icon: Icons.add,
                  onTap: _zoomIn,
                ),
                const SizedBox(height: 12),
                _ZoomButton(
                  icon: Icons.remove,
                  onTap: _zoomOut,
                ),
              ],
            ),
          ),
          
          // Search bar with autocomplete
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search field
                  Container(
                    decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      onTap: () {
                        if (_suggestions.isNotEmpty) {
                          setState(() => _showSuggestions = true);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Rechercher une zone (ex: Guédiawaye)',
                        hintStyle: secondaryTextStyle(),
                        prefixIcon: Icon(Icons.search, color: primaryColor),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: grey),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _suggestions = [];
                                        _showSuggestions = false;
                                      });
                                    },
                                  )
                                : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  
                  // Suggestions list
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        color: context.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          return ListTile(
                            leading: Icon(Icons.location_on, color: primaryColor),
                            title: Text(
                              suggestion.shortName,
                              style: primaryTextStyle(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${suggestion.lat.toStringAsFixed(4)}, ${suggestion.lon.toStringAsFixed(4)}',
                              style: secondaryTextStyle(size: 14),
                            ),
                            onTap: () => _selectSuggestion(suggestion),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Bottom panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Current location button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FloatingActionButton.small(
                        onPressed: _goToCurrentLocation,
                        backgroundColor: primaryColor.withOpacity(0.9),
                        child: const Icon(Icons.my_location, color: Colors.white),
                      ),
                    ],
                  ),
                  12.height,
                  
                  // Address field
                  AppTextField(
                    controller: _addressController,
                    textFieldType: TextFieldType.MULTILINE,
                    maxLines: 2,
                    minLines: 1,
                    textStyle: primaryTextStyle(),
                    decoration: inputDecoration(
                      context,
                      labelText: 'Adresse sélectionnée',
                    ).copyWith(
                      fillColor: context.scaffoldBackgroundColor,
                      prefixIcon: Icon(Icons.location_on, color: primaryColor),
                    ),
                  ),
                  12.height,
                  
                  // Confirm button
                  AppButton(
                    width: context.width(),
                    color: primaryColor,
                    text: 'Confirmer l\'adresse',
                    textStyle: boldTextStyle(color: Colors.white),
                    onTap: _confirmAddress,
                  ),
                  8.height,
                ],
              ),
            ),
          ),
          
          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: LoaderWidget(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Material(
        color: context.cardColor.withOpacity(0.9),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 45,
            height: 45,
            child: Icon(icon, color: primaryColor),
          ),
        ),
      ),
    );
  }
}
