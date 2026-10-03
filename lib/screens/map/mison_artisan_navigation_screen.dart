import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:booking_system_flutter/utils/artisan_arrival_reporter.dart';
import 'package:booking_system_flutter/utils/close_map_when_started.dart';
import 'package:booking_system_flutter/utils/route_eta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;


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
    extends State<MisonArtisanNavigationScreen>
    with WidgetsBindingObserver, CloseMapWhenOrderStarted {
  @override
  String get trackedOrderId => widget.orderId;

  GoogleMapController? _map;
  double _zoom = 16;
  BitmapDescriptor? _artisanIcon;
  BitmapDescriptor? _clientIcon;
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
  bool _arrived = false;            // à moins de kArrivalRadiusMeters de l'adresse
  bool _announcedWalkToDest = false; // fin de route atteinte, adresse un peu à l'écart

  @override
  void initState() {
    super.initState();
    startWatchingOrderStart(); // ferme la carte dès que la prestation commence
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _buildIcons();
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
        _arrived = false;
        _announcedWalkToDest = false;
      });

      if (steps.isNotEmpty) _speak(steps.first.instruction);

      if (coords.length > 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute(coords));
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
      _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), _zoom));
    }

    _checkStepProgress(pos);
  }

  void _checkStepProgress(Position pos) {
    if (_steps.isEmpty || _arrived) return;

    final distToDest = Geolocator.distanceBetween(
      pos.latitude, pos.longitude, widget.destLat, widget.destLng,
    );

    // Arrivée : seulement près de l'ADRESSE (pas du dernier virage ni du point
    // routier calculé par l'itinéraire), avec un GPS assez précis.
    if (distToDest <= kArrivalRadiusMeters && pos.accuracy <= kMaxArrivalGpsAccuracyMeters) {
      setState(() {
        _arrived = true;
        _currentStepIndex = _steps.length - 1;
      });
      _speak('Vous êtes arrivé à destination');
      // Serveur : fin de la mini-carte, « Commencer la prestation » disponible.
      ArtisanArrivalReporter.markArrived(widget.orderId);
      return;
    }

    while (_currentStepIndex < _steps.length) {
      final step = _steps[_currentStepIndex];
      final dist = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        step.location.latitude,
        step.location.longitude,
      );

      // Dernière étape (« arrive ») : c'est le point de la route le plus proche
      // de l'adresse. L'arrivée est gérée plus haut, sur l'adresse elle-même ;
      // si la route s'arrête à l'écart, on l'indique une fois.
      if (_currentStepIndex == _steps.length - 1) {
        if (dist < 20 && !_announcedWalkToDest) {
          _announcedWalkToDest = true;
          _speak('La destination est à ${_fmtDist(distToDest)}, continuez à pied');
        }
        break;
      }

      final nextIsArrival = _currentStepIndex + 1 == _steps.length - 1;

      // Annonce à 200 m du prochain manœuvre (pas pour l'arrivée : elle est
      // annoncée quand l'ouvrier y est réellement).
      if (dist < 200 &&
          dist > 30 &&
          !_hasAnnouncedApproach &&
          !nextIsArrival) {
        _hasAnnouncedApproach = true;
        final next = _steps[_currentStepIndex + 1];
        _speak('Dans ${_fmtDist(dist)}, ${next.instruction}');
        break;
      }

      // Passage au step suivant à 20 m
      if (dist < 20) {
        _currentStepIndex++;
        _hasAnnouncedApproach = false;
        if (nextIsArrival) {
          // Dernier virage passé : il reste la dernière rue, pas encore arrivé.
          _speak('Votre destination est à ${_fmtDist(distToDest)}');
        } else if (_currentStepIndex < _steps.length) {
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

  // ── Carte ─────────────────────────────────────────────────────────────────

  /// Tout l'itinéraire à l'écran.
  void _fitRoute(List<LatLng> points) {
    if (_map == null || points.length < 2) return;
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    _map!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)),
      60,
    ));
  }

  /// Icônes rondes aux couleurs Mison, comme sur l'écran du client : flèche
  /// dorée (prestataire, tournée selon son cap) et maison sombre (client).
  Future<void> _buildIcons() async {
    final artisan = await _roundIcon(background: kMisonGold, glyph: Icons.navigation_rounded);
    final client = await _roundIcon(background: kMisonDark, glyph: Icons.home_rounded);
    if (!mounted) return;
    setState(() {
      _artisanIcon = artisan;
      _clientIcon = client;
    });
  }

  Future<BitmapDescriptor> _roundIcon({required Color background, required IconData glyph}) async {
    const double size = 120;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    const center = Offset(size / 2, size / 2);
    canvas.drawCircle(
      center,
      size / 2 - 6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(center, size / 2 - 10, Paint()..color = Colors.white);
    canvas.drawCircle(center, size / 2 - 17, Paint()..color = background);
    final painter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: TextStyle(fontSize: size * 0.42, fontFamily: glyph.fontFamily, package: glyph.fontPackage, color: Colors.white),
      )
      ..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 44, height: 44);
  }

  Set<Marker> _markers(Position? pos) => {
        Marker(
          markerId: const MarkerId('client'),
          position: LatLng(widget.destLat, widget.destLng),
          icon: _clientIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: 'Client', snippet: widget.serviceAddress),
        ),
        if (pos != null)
          Marker(
            markerId: const MarkerId('artisan'),
            position: LatLng(pos.latitude, pos.longitude),
            icon: _artisanIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
            anchor: const Offset(0.5, 0.5),
            // Cap GPS (0° = nord) fourni par le téléphone
            rotation: pos.heading,
            flat: true,
            zIndexInt: 2,
          ),
      };

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
    stopWatchingOrderStart();
    _positionSub?.cancel();
    _tts.stop();
    _map?.dispose();
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
      backgroundColor: Colors.white,
      // Logo centré, comme les autres pages
      appBar: MisonAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kMisonDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ── Carte ─────────────────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                // Toucher la carte arrête de suivre la position.
                Listener(
                  onPointerDown: (_) {
                    if (_isFollowing) setState(() => _isFollowing = false);
                  },
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: pos != null
                          ? LatLng(pos.latitude, pos.longitude)
                          : LatLng(widget.destLat, widget.destLng),
                      zoom: 14,
                    ),
                    onMapCreated: (c) {
                      _map = c;
                      if (_routePoints.length > 1) _fitRoute(_routePoints);
                    },
                    onCameraMove: (p) => _zoom = p.zoom,
                    markers: _markers(pos),
                    polylines: {
                      if (_routePoints.isNotEmpty)
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: _routePoints,
                          color: kMisonGold,
                          width: 6,
                          startCap: Cap.roundCap,
                          endCap: Cap.roundCap,
                          jointType: JointType.round,
                        ),
                    },
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                  ),
                ),

                // Erreur
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
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _fetchRoute,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Boutons flottants
                if (!_isLoading)
                  Positioned(
                    right: 14,
                    bottom: 20,
                    child: Column(
                      children: [
                        // Recentrer sur ma position
                        _FloatBtn(
                          icon: Icons.my_location_rounded,
                          color: _isFollowing ? kMisonGold : Colors.white,
                          iconColor: _isFollowing ? Colors.white : kMisonGold,
                          onTap: () {
                            setState(() => _isFollowing = true);
                            if (pos != null) {
                              _zoom = 16;
                              _map?.animateCamera(
                                CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        // Recalculer
                        _FloatBtn(
                          icon: Icons.refresh_rounded,
                          color: Colors.white,
                          iconColor: kMisonGold,
                          onTap: _fetchRoute,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── En bas : prochaine instruction, distance et temps restants ─────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4)),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(currentStep),
                  if (!_isLoading && _error == null) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _fmtDist(_remainingDistanceM),
                            style: const TextStyle(color: kMisonDark, fontSize: 24, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            _fmtEta(_remainingDistanceM),
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    // Destination
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: kMisonGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kMisonGold.withValues(alpha: 0.35)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.home_rounded, color: kMisonGold, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Client',
                            style: TextStyle(color: kMisonGold, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Distance jusqu'à la prochaine manœuvre (« Dans 200 m »), sauf pour
  /// l'arrivée, qui a déjà sa distance dans l'instruction.
  String? _distanceToStep(_NavStep? step) {
    final pos = _currentPos;
    if (step == null || pos == null || _arrived || _currentStepIndex >= _steps.length - 1) return null;
    final meters = Geolocator.distanceBetween(
      pos.latitude, pos.longitude, step.location.latitude, step.location.longitude,
    );
    return 'Dans ${_fmtDist(meters)}';
  }

  /// L'étape « arrivée » ne dit « Vous êtes arrivé » qu'une fois réellement
  /// à l'adresse ; avant, elle indique la distance restante.
  String _headerInstruction(_NavStep? step) {
    if (step == null) return 'Navigation';
    if (_arrived) return 'Vous êtes arrivé à destination';
    if (_currentStepIndex == _steps.length - 1) {
      return 'Destination à ${_fmtDist(_remainingDistanceM)}';
    }
    return step.instruction;
  }

  /// Carte dorée : prochaine manœuvre, sa distance et l'adresse du client.
  Widget _buildHeader(_NavStep? step) {
    final inDistance = _isLoading ? null : _distanceToStep(step);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: kMisonGold,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: kMisonGold.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : Icon(step?.icon ?? Icons.navigation_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (inDistance != null)
                  Text(
                    inDistance,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                Text(
                  _isLoading ? 'Recherche de position…' : _headerInstruction(step),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.serviceAddress.isNotEmpty)
                  Text(
                    widget.serviceAddress,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
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
