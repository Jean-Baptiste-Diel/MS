import 'package:booking_system_flutter/utils/colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nb_utils/nb_utils.dart';

class MisonTrackingScreen extends StatefulWidget {
  final String orderId;
  final String serviceAddress;
  final String artisanName;

  const MisonTrackingScreen({
    Key? key,
    required this.orderId,
    required this.serviceAddress,
    required this.artisanName,
  }) : super(key: key);

  @override
  State<MisonTrackingScreen> createState() => _MisonTrackingScreenState();
}

class _MisonTrackingScreenState extends State<MisonTrackingScreen> {
  GoogleMapController? _mapController;
  LatLng? _artisanPosition;
  bool _firstLoad = true;

  static const _defaultZoom = 15.0;

  Set<Marker> get _markers {
    final markers = <Marker>{};
    if (_artisanPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('artisan'),
        position: _artisanPosition!,
        infoWindow: InfoWindow(title: widget.artisanName, snippet: 'En déplacement'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }
    return markers;
  }

  void _onPositionUpdate(LatLng pos) {
    setState(() => _artisanPosition = pos);
    if (_firstLoad && _mapController != null) {
      _firstLoad = false;
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(pos, _defaultZoom));
    } else if (!_firstLoad && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(pos));
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('artisan_locations')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _onPositionUpdate(LatLng(lat, lng)),
              );
            }
          }

          return Stack(
            children: [
              // ── Carte ────────────────────────────────────────────────────────
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _artisanPosition ?? const LatLng(14.6928, -17.4467),
                  zoom: _defaultZoom,
                ),
                onMapCreated: (ctrl) {
                  _mapController = ctrl;
                  if (_artisanPosition != null) {
                    ctrl.animateCamera(
                      CameraUpdate.newLatLngZoom(_artisanPosition!, _defaultZoom),
                    );
                  }
                },
                markers: _markers,
                myLocationEnabled: true,
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
                          elevation: 2,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        12.width,
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.green,
                                  ),
                                ),
                                8.width,
                                Expanded(
                                  child: Text(
                                    _artisanPosition != null
                                        ? '${widget.artisanName} est en route'
                                        : 'En attente de localisation…',
                                    style: boldTextStyle(size: 13),
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

              // ── Adresse destination en bas ────────────────────────────────────
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.location_on_rounded, color: primaryColor, size: 20),
                      ),
                      12.width,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Adresse d\'intervention',
                                style: secondaryTextStyle(size: 11)),
                            4.height,
                            Text(
                              widget.serviceAddress.isNotEmpty
                                  ? widget.serviceAddress
                                  : 'Adresse non définie',
                              style: boldTextStyle(size: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Bouton recentrer ──────────────────────────────────────────────
              if (_artisanPosition != null)
                Positioned(
                  bottom: 110, right: 16,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      icon: Icon(Icons.my_location_rounded, color: primaryColor),
                      onPressed: () => _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(_artisanPosition!, _defaultZoom),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
