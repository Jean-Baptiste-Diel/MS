import 'dart:async';
import 'dart:convert';
import 'dart:math' show min, max, sin, cos, sqrt, atan2, pi;
import 'dart:ui' as ui;

import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/firebase_messaging_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

class MisonTrackingScreen extends StatefulWidget {
  final String orderId;
  final String serviceAddress;
  final String artisanName;
  final double? serviceLat;
  final double? serviceLng;

  const MisonTrackingScreen({
    Key? key,
    required this.orderId,
    required this.serviceAddress,
    required this.artisanName,
    this.serviceLat,
    this.serviceLng,
  }) : super(key: key);

  @override
  State<MisonTrackingScreen> createState() => _MisonTrackingScreenState();
}

class _MisonTrackingScreenState extends State<MisonTrackingScreen> {
  GoogleMapController? _mapController;

  // Marker positions
  LatLng? _artisanPosition;       // raw from Firestore
  LatLng? _animatedPosition;      // smoothly animated
  LatLng? _destinationPosition;

  // Direction (bearing) of travel, in degrees clockwise from north
  double _bearing = 0;
  BitmapDescriptor? _arrowIcon;

  // Route
  List<LatLng> _routePoints = [];
  bool _fetchingRoute = false;
  DateTime? _lastRouteFetch;

  // ETA / distance from Directions API
  String? _etaText;
  String? _distanceText;
  int? _etaSeconds;

  // State flags
  bool _firstLoad = true;
  bool _hadFirstUpdate = false;   // au moins un update reçu
  bool _artisanNearby = false;    // < 500 m
  bool _nearbyAlertShown = false;
  bool _arrivedAlertShown = false;

  // Animation
  Timer? _animTimer;
  static const _animSteps = 25;
  static const _animInterval = Duration(milliseconds: 40);

  StreamSubscription<DocumentSnapshot>? _locationSub;

  static const _defaultZoom = 15.0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    if (widget.serviceLat != null && widget.serviceLng != null) {
      _destinationPosition = LatLng(widget.serviceLat!, widget.serviceLng!);
    }

    _loadArrowIcon();

    _locationSub = FirebaseFirestore.instance
        .collection('artisan_locations')
        .doc(widget.orderId)
        .snapshots()
        .listen(_onFirestoreUpdate);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _animTimer?.cancel();
    _mapController?.dispose();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    super.dispose();
  }

  // ── Firestore → position ──────────────────────────────────────────────────

  void _onFirestoreUpdate(DocumentSnapshot snap) {
    if (!snap.exists || !mounted) return;
    final data = snap.data() as Map<String, dynamic>;
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final newPos = LatLng(lat, lng);
    final previous = _artisanPosition;
    if (previous != null) {
      final movedMeters = _haversine(
        previous.latitude, previous.longitude,
        newPos.latitude, newPos.longitude,
      );
      // On ignore le bruit GPS (petits sauts) pour une flèche stable
      if (movedMeters > 3) {
        _bearing = _bearingBetween(previous, newPos);
      }
    }
    _artisanPosition = newPos;
    _animateMarkerTo(newPos);

    if (_firstLoad) {
      _firstLoad = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBothMarkers());
    }

    _checkNearby(newPos);
    _fetchRoute();
  }

  // ── Smooth marker animation ───────────────────────────────────────────────

  void _animateMarkerTo(LatLng target) {
    if (_animatedPosition == null) {
      setState(() => _animatedPosition = target);
      return;
    }
    final start = _animatedPosition!;
    _animTimer?.cancel();
    int step = 0;
    _animTimer = Timer.periodic(_animInterval, (timer) {
      step++;
      final t = step / _animSteps;
      final ease = t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t; // ease-in-out
      final lat = start.latitude + (target.latitude - start.latitude) * ease;
      final lng = start.longitude + (target.longitude - start.longitude) * ease;
      if (mounted) setState(() => _animatedPosition = LatLng(lat, lng));
      if (step >= _animSteps) {
        timer.cancel();
        if (mounted) setState(() => _animatedPosition = target);
      }
    });
  }

  // ── Nearby alert ──────────────────────────────────────────────────────────

  void _checkNearby(LatLng artisanPos) {
    if (_destinationPosition == null) return;
    final dist = _haversine(
      artisanPos.latitude, artisanPos.longitude,
      _destinationPosition!.latitude, _destinationPosition!.longitude,
    );

    final isArrived = dist < 100 || (_etaSeconds != null && _etaSeconds! < 120);
    final isNearby  = dist < 500 || (_etaSeconds != null && _etaSeconds! < 300);

    if (_hadFirstUpdate) {
      // Arrivée (priorité haute)
      if (isArrived && !_arrivedAlertShown) {
        _arrivedAlertShown = true;
        _nearbyAlertShown  = true; // évite double alerte
        _showArrivedBanner();
        showSimpleLocalNotification(
          id: 9002,
          title: '${widget.artisanName} est arrivé !',
          body: 'Votre ouvrier est arrivé à votre adresse.',
        );
      }
      // Proche (seulement si pas encore déclenché et transition far→near)
      else if (isNearby && !_artisanNearby && !_nearbyAlertShown) {
        _nearbyAlertShown = true;
        _showNearbyBanner();
        showSimpleLocalNotification(
          id: 9001,
          title: '${widget.artisanName} est proche !',
          body: 'Votre ouvrier est à moins de 500 m de chez vous.',
        );
      }
    }

    _hadFirstUpdate = true;
    setState(() => _artisanNearby = isNearby);
  }

  void _showNearbyBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.directions_run_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${widget.artisanName} est à moins de 500 m !',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
  }

  void _showArrivedBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${widget.artisanName} est arrivé !',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  void _fitBothMarkers() {
    if (_mapController == null) return;
    final a = _animatedPosition ?? _artisanPosition;
    final d = _destinationPosition;
    if (a != null && d != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          min(a.latitude, d.latitude) - 0.002,
          min(a.longitude, d.longitude) - 0.002,
        ),
        northeast: LatLng(
          max(a.latitude, d.latitude) + 0.002,
          max(a.longitude, d.longitude) + 0.002,
        ),
      );
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } else if (a != null) {
      _mapController!
          .animateCamera(CameraUpdate.newLatLngZoom(a, _defaultZoom));
    }
  }

  // ── Directions API ────────────────────────────────────────────────────────

  Future<void> _fetchRoute() async {
    if (_artisanPosition == null || _destinationPosition == null) return;
    if (_fetchingRoute) return;
    final now = DateTime.now();
    if (_lastRouteFetch != null &&
        now.difference(_lastRouteFetch!) < const Duration(seconds: 25)) return;

    _fetchingRoute = true;
    _lastRouteFetch = now;
    try {
      final origin =
          '${_artisanPosition!.latitude},${_artisanPosition!.longitude}';
      final dest =
          '${_destinationPosition!.latitude},${_destinationPosition!.longitude}';
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$origin&destination=$dest&mode=driving&key=$GOOGLE_PLACES_API_KEY',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = body['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final leg = routes[0]['legs'][0] as Map<String, dynamic>;
          final encoded = routes[0]['overview_polyline']['points'] as String;
          final points = _decodePolyline(encoded);

          setState(() {
            _routePoints = points;
            _etaText = leg['duration']?['text'] as String?;
            _distanceText = leg['distance']?['text'] as String?;
            _etaSeconds = (leg['duration']?['value'] as num?)?.toInt();
          });
        }
      }
    } catch (_) {
    } finally {
      _fetchingRoute = false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    const toRad = 3.141592653589793 / 180;
    final phi1 = lat1 * toRad;
    final phi2 = lat2 * toRad;
    final dPhi = (lat2 - lat1) * toRad;
    final dLambda = (lon2 - lon1) * toRad;
    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // Cap (direction) en degrés, 0° = nord, sens horaire — comme Google Maps
  double _bearingBetween(LatLng start, LatLng end) {
    const toRad = 3.141592653589793 / 180;
    final lat1 = start.latitude * toRad;
    final lat2 = end.latitude * toRad;
    final dLng = (end.longitude - start.longitude) * toRad;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    final deg = atan2(y, x) * 180 / pi;
    return (deg + 360) % 360;
  }

  // ── Icône flèche de direction (style navigation Google Maps) ───────────────

  Future<void> _loadArrowIcon() async {
    final icon = await _buildNavigationArrowIcon(primaryColor);
    if (mounted) setState(() => _arrowIcon = icon);
  }

  Future<BitmapDescriptor> _buildNavigationArrowIcon(Color color) async {
    const double size = 130;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    const center = Offset(size / 2, size / 2);

    // Halo blanc + ombre douce
    canvas.drawCircle(
      center,
      size / 2 - 6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(center, size / 2 - 10, Paint()..color = Colors.white);

    // Disque de couleur
    canvas.drawCircle(center, size / 2 - 18, Paint()..color = color);

    // Flèche pointant vers le haut (le cap est appliqué via Marker.rotation)
    const arrowSize = size * 0.34;
    final path = Path()
      ..moveTo(center.dx, center.dy - arrowSize / 1.4)
      ..lineTo(center.dx - arrowSize / 2, center.dy + arrowSize / 2.4)
      ..lineTo(center.dx, center.dy + arrowSize / 6)
      ..lineTo(center.dx + arrowSize / 2, center.dy + arrowSize / 2.4)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: 52,
      height: 52,
    );
  }

  // ── Map overlays ──────────────────────────────────────────────────────────

  Set<Marker> get _markers {
    final markers = <Marker>{};
    final pos = _animatedPosition ?? _artisanPosition;
    if (pos != null) {
      markers.add(Marker(
        markerId: const MarkerId('artisan'),
        position: pos,
        rotation: _bearing,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        infoWindow: InfoWindow(
          title: widget.artisanName,
          snippet: _etaText != null ? 'Arrivée dans $_etaText' : 'En déplacement',
        ),
        icon: _arrowIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }
    if (_destinationPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: _destinationPosition!,
        infoWindow: const InfoWindow(
          title: 'Destination',
          snippet: "Lieu d'intervention",
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }
    return markers;
  }

  Set<Polyline> get _polylines {
    if (_routePoints.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints,
        color: primaryColor,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final address = widget.serviceAddress.trim().isNotEmpty
        ? widget.serviceAddress
        : 'Adresse non définie';

    final initialTarget = _destinationPosition ??
        _artisanPosition ??
        const LatLng(14.6928, -17.4467);

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte ─────────────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialTarget,
              zoom: _defaultZoom,
            ),
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              if (_artisanPosition != null || _destinationPosition != null) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _fitBothMarkers());
              }
            },
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // ── AppBar custom ─────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
                child: Row(
                  children: [
                    Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 4,
                      shadowColor: Colors.black26,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(context),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              size: 18, color: Colors.black87),
                        ),
                      ),
                    ),
                    12.width,
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _artisanNearby
                                    ? Colors.orange
                                    : _artisanPosition != null
                                        ? Colors.green
                                        : Colors.grey,
                              ),
                            ),
                            8.width,
                            Expanded(
                              child: Text(
                                _artisanNearby
                                    ? '${widget.artisanName} est presque là !'
                                    : _etaText != null
                                        ? '${widget.artisanName} · $_etaText'
                                        : _artisanPosition != null
                                            ? '${widget.artisanName} est en route'
                                            : 'En attente de localisation…',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: _artisanNearby
                                      ? Colors.orange.shade700
                                      : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Carte infos bas ───────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ETA + distance row
                    if (_etaText != null || _distanceText != null) ...[
                      Row(
                        children: [
                          if (_etaText != null)
                            _InfoChip(
                              icon: Icons.access_time_rounded,
                              label: _etaText!,
                              color: primaryColor,
                            ),
                          if (_etaText != null && _distanceText != null)
                            12.width,
                          if (_distanceText != null)
                            _InfoChip(
                              icon: Icons.straighten_rounded,
                              label: _distanceText!,
                              color: Colors.blueGrey.shade600,
                            ),
                          const Spacer(),
                          // Arrivée estimée
                          if (_etaSeconds != null)
                            Text(
                              'Arrivée ~${_arrivalTime(_etaSeconds!)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      12.height,
                    ] else if (_artisanPosition == null) ...[
                      // Skeleton / waiting
                      Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                              8.width,
                              Text(
                                'Calcul de l\'itinéraire…',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      12.height,
                    ],

                    // Address row
                    Row(
                      children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.location_on_rounded,
                              color: primaryColor, size: 20),
                        ),
                        12.width,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                "Adresse d'intervention",
                                style: TextStyle(
                                    fontSize: 14, color: Colors.black45),
                              ),
                              4.height,
                              Text(
                                address,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    16.height,
                  ],
                ),
              ),
            ),
          ),

          // ── Bouton recentrer ──────────────────────────────────────────────
          Positioned(
            bottom: 148, right: 14,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 4,
              shadowColor: Colors.black26,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _fitBothMarkers,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.fit_screen_rounded,
                      color: primaryColor, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _arrivalTime(int etaSec) {
    final arrival = DateTime.now().add(Duration(seconds: etaSec));
    final h = arrival.hour.toString().padLeft(2, '0');
    final m = arrival.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Info chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
