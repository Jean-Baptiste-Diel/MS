import 'dart:async';
import 'dart:convert';

import 'package:booking_system_flutter/utils/colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';


// ── Step model ───────────────────────────────────────────────────────────────

class _NavStep {
  final LatLng location;
  final String instruction;
  final double distanceM;
  final IconData icon;

  _NavStep({
    required this.location,
    required this.instruction,
    required this.distanceM,
    required this.icon,
  });
}

// ── Screen ───────────────────────────────────────────────────────────────────

class MisonArtisanNavigationScreen extends StatefulWidget {
  final String serviceAddress;
  final double destLat;
  final double destLng;
  final String orderId;

  const MisonArtisanNavigationScreen({
    Key? key,
    required this.serviceAddress,
    required this.destLat,
    required this.destLng,
    required this.orderId,
  }) : super(key: key);

  @override
  State<MisonArtisanNavigationScreen> createState() =>
      _MisonArtisanNavigationScreenState();
}

class _MisonArtisanNavigationScreenState
    extends State<MisonArtisanNavigationScreen> {
  final MapController _mapController = MapController();
  final FlutterTts _tts = FlutterTts();

  Position? _currentPos;
  List<LatLng> _routePoints = [];
  List<_NavStep> _steps = [];
  int _currentStepIndex = 0;
  bool _isFollowing = true;
  bool _isLoading = true;
  String? _error;
  double _remainingDistanceM = 0;
  StreamSubscription<Position>? _positionSub;
  bool _hasAnnouncedApproach = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _initTts();
    _startNavigation();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _startNavigation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Permission de localisation refusée.\nActivez-la dans les paramètres.';
        });
      }
      return;
    }

    try {
      _currentPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Impossible d\'obtenir votre position.';
        });
      }
      return;
    }

    await _fetchRoute();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
    );

    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPositionUpdate,
      onError: (_) {},
    );
  }

  Future<void> _fetchRoute() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final pos = _currentPos!;
    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${pos.longitude},${pos.latitude};'
        '${widget.destLng},${widget.destLat}'
        '?steps=true&geometries=geojson&overview=full';

    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') throw Exception('OSRM: ${data['code']}');

      final route =
          (data['routes'] as List).first as Map<String, dynamic>;
      final totalDist = (route['distance'] as num).toDouble();

      final coords = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();

      final steps = <_NavStep>[];
      for (final leg in (route['legs'] as List)) {
        for (final step in (leg['steps'] as List)) {
          final maneuver = step['maneuver'] as Map<String, dynamic>;
          final loc = maneuver['location'] as List;
          final streetName = step['name'] as String? ?? '';
          steps.add(_NavStep(
            location: LatLng(
              (loc[1] as num).toDouble(),
              (loc[0] as num).toDouble(),
            ),
            instruction: _buildInstruction(maneuver, streetName),
            distanceM: (step['distance'] as num).toDouble(),
            icon: _maneuverIcon(maneuver),
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _routePoints = coords;
        _steps = steps;
        _remainingDistanceM = totalDist;
        _isLoading = false;
        _currentStepIndex = 0;
        _hasAnnouncedApproach = false;
      });

      if (steps.isNotEmpty) _speak(steps.first.instruction);

      if (coords.length > 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.fitCamera(
              CameraFit.coordinates(
                coordinates: coords,
                padding: const EdgeInsets.fromLTRB(40, 120, 40, 160),
              ),
            );
          } catch (_) {}
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Itinéraire indisponible.\nVérifiez votre connexion.';
        });
      }
    }
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;

    setState(() {
      _currentPos = pos;
      _remainingDistanceM = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        widget.destLat,
        widget.destLng,
      );
    });

    // Firestore — continue d'envoyer même pendant la navigation
    FirebaseFirestore.instance
        .collection('artisan_locations')
        .doc(widget.orderId)
        .set({
      'lat': pos.latitude,
      'lng': pos.longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (_isFollowing) {
      try {
        _mapController.move(
          LatLng(pos.latitude, pos.longitude),
          _mapController.camera.zoom,
        );
      } catch (_) {}
    }

    _checkStepProgress(pos);
  }

  void _checkStepProgress(Position pos) {
    if (_steps.isEmpty) return;

    while (_currentStepIndex < _steps.length) {
      final step = _steps[_currentStepIndex];
      final dist = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        step.location.latitude,
        step.location.longitude,
      );

      // Annonce à 200 m du prochain manœuvre
      if (dist < 200 &&
          dist > 30 &&
          !_hasAnnouncedApproach &&
          _currentStepIndex + 1 < _steps.length) {
        _hasAnnouncedApproach = true;
        final next = _steps[_currentStepIndex + 1];
        _speak('Dans ${_fmtDist(dist)}, ${next.instruction}');
        break;
      }

      // Passage au step suivant à 20 m
      if (dist < 20) {
        _currentStepIndex++;
        _hasAnnouncedApproach = false;
        if (_currentStepIndex < _steps.length) {
          _speak(_steps[_currentStepIndex].instruction);
        }
      } else {
        break;
      }
    }
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  // ── Instruction builder (français) ──────────────────────────────────────

  String _buildInstruction(Map<String, dynamic> maneuver, String street) {
    final type = maneuver['type'] as String? ?? '';
    final modifier = maneuver['modifier'] as String? ?? '';
    final on = street.isNotEmpty ? ' sur $street' : '';

    switch (type) {
      case 'depart':
        return street.isNotEmpty
            ? 'Démarrez sur $street'
            : 'Démarrez en direction du client';
      case 'arrive':
        return 'Vous êtes arrivé à destination';
      case 'turn':
        switch (modifier) {
          case 'left':
            return 'Tournez à gauche$on';
          case 'right':
            return 'Tournez à droite$on';
          case 'slight left':
            return 'Légèrement à gauche$on';
          case 'slight right':
            return 'Légèrement à droite$on';
          case 'sharp left':
            return 'Tournez nettement à gauche$on';
          case 'sharp right':
            return 'Tournez nettement à droite$on';
          case 'uturn':
            return 'Faites demi-tour$on';
          default:
            return 'Continuez tout droit$on';
        }
      case 'continue':
      case 'new name':
        return street.isNotEmpty
            ? 'Continuez sur $street'
            : 'Continuez tout droit';
      case 'merge':
        return 'Rejoignez la voie$on';
      case 'on ramp':
        return 'Prenez la bretelle d\'accès$on';
      case 'off ramp':
        return 'Prenez la sortie$on';
      case 'fork':
        return modifier.contains('right')
            ? 'Gardez la droite au carrefour$on'
            : 'Gardez la gauche au carrefour$on';
      case 'roundabout':
      case 'rotary':
        final exit = maneuver['exit'] as int?;
        return exit != null
            ? 'Prenez la ${exit}ème sortie du rond-point'
            : 'Engagez-vous dans le rond-point';
      case 'end of road':
        return modifier.contains('right')
            ? 'Au bout de la route, tournez à droite$on'
            : 'Au bout de la route, tournez à gauche$on';
      default:
        return street.isNotEmpty ? 'Continuez sur $street' : 'Continuez';
    }
  }

  IconData _maneuverIcon(Map<String, dynamic> maneuver) {
    final type = maneuver['type'] as String? ?? '';
    final modifier = maneuver['modifier'] as String? ?? '';
    if (type == 'arrive') return Icons.location_on_rounded;
    if (type == 'depart') return Icons.navigation_rounded;
    if (type == 'roundabout' || type == 'rotary') {
      return Icons.rotate_right_rounded;
    }
    if (type == 'fork' || type == 'on ramp' || type == 'off ramp') {
      return modifier.contains('right')
          ? Icons.fork_right_rounded
          : Icons.fork_left_rounded;
    }
    switch (modifier) {
      case 'left':
      case 'sharp left':
        return Icons.turn_left_rounded;
      case 'right':
      case 'sharp right':
        return Icons.turn_right_rounded;
      case 'slight left':
        return Icons.turn_slight_left_rounded;
      case 'slight right':
        return Icons.turn_slight_right_rounded;
      case 'uturn':
        return Icons.u_turn_left_rounded;
      default:
        return Icons.straight_rounded;
    }
  }

  // ── Formatters ───────────────────────────────────────────────────────────

  String _fmtDist(double m) {
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  String _fmtEta(double m) {
    final seconds = (m / 1000 / 30 * 3600).round();
    if (seconds < 60) return 'moins d\'1 min';
    final min = seconds ~/ 60;
    if (min < 60) return '$min min';
    return '${min ~/ 60}h${(min % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _tts.stop();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pos = _currentPos;
    final currentStep =
        (_steps.isNotEmpty && _currentStepIndex < _steps.length)
            ? _steps[_currentStepIndex]
            : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // ── Header instruction ────────────────────────────────────────────
          Container(
            color: primaryColor,
            child: SafeArea(
              bottom: false,
              child: _buildHeader(currentStep),
            ),
          ),

          // ── Map ───────────────────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                // Map (even during loading — show destination)
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: pos != null
                        ? LatLng(pos.latitude, pos.longitude)
                        : LatLng(widget.destLat, widget.destLng),
                    initialZoom: 14,
                    onPositionChanged: (_, hasGesture) {
                      if (hasGesture && _isFollowing) {
                        setState(() => _isFollowing = false);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.misonservice.app',
                    ),
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            color: primaryColor,
                            strokeWidth: 5.5,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        // Destination
                        Marker(
                          point: LatLng(widget.destLat, widget.destLng),
                          width: 40,
                          height: 50,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.redAccent,
                            size: 40,
                            shadows: [
                              Shadow(
                                color: Colors.black45,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              )
                            ],
                          ),
                        ),
                        // Position ouvrier
                        if (pos != null)
                          Marker(
                            point: LatLng(pos.latitude, pos.longitude),
                            width: 36,
                            height: 36,
                            rotate: false,
                            child: Transform.rotate(
                              // pos.heading = cap GPS en degrés (0° = nord), fourni par le device
                              angle: pos.heading * (3.141592653589793 / 180),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blueAccent,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black38,
                                      blurRadius: 6,
                                    )
                                  ],
                                ),
                                child: const Icon(
                                  Icons.navigation_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Loading overlay
                if (_isLoading)
                  Container(
                    color: Colors.black45,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2A3D),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: primaryColor),
                            const SizedBox(height: 14),
                            const Text(
                              'Calcul de l\'itinéraire…',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Error overlay
                if (!_isLoading && _error != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 100,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.shade700,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.15),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _fetchRoute,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Floating buttons
                if (!_isLoading)
                  Positioned(
                    right: 14,
                    bottom: 140,
                    child: Column(
                      children: [
                        // Recenter
                        _FloatBtn(
                          icon: Icons.my_location_rounded,
                          color:
                              _isFollowing ? primaryColor : Colors.white,
                          iconColor:
                              _isFollowing ? Colors.white : primaryColor,
                          onTap: () {
                            setState(() => _isFollowing = true);
                            if (pos != null) {
                              _mapController.move(
                                LatLng(pos.latitude, pos.longitude),
                                16,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        // Recalculate
                        _FloatBtn(
                          icon: Icons.refresh_rounded,
                          color: Colors.white,
                          iconColor: primaryColor,
                          onTap: _fetchRoute,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Bottom bar ────────────────────────────────────────────────────
          if (!_isLoading && _error == null)
            Container(
              color: const Color(0xFF1A2A3D),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _fmtDist(_remainingDistanceM),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            _fmtEta(_remainingDistanceM),
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                    // Destination label
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: Colors.redAccent, size: 18),
                          const SizedBox(height: 2),
                          const Text(
                            'Client',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(_NavStep? step) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Text(
              'Recherche de position…',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              step?.icon ?? Icons.navigation_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step?.instruction ?? 'Navigation',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.serviceAddress.isNotEmpty)
                  Text(
                    widget.serviceAddress,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Floating button helper ────────────────────────────────────────────────────

class _FloatBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _FloatBtn({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 3),
            )
          ],
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
    );
  }
}
