import 'dart:async';

import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark;
import 'package:booking_system_flutter/services/location_service.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nb_utils/nb_utils.dart';

/// Lieu choisi sur la carte.
class PickedLocation {
  final double lat;
  final double lon;
  final String address;
  const PickedLocation(this.lat, this.lon, this.address);
}

/// « Choisir sur la carte » : pour les lieux qu'aucune recherche ne connaît.
/// Le client déplace la carte sous l'épingle du centre, l'adresse s'affiche en
/// bas, puis il confirme. Limité à la région de Dakar.
class MisonLocationPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const MisonLocationPickerScreen({super.key, this.initial});

  static Future<PickedLocation?> open(BuildContext context, {LatLng? initial}) =>
      Navigator.of(context).push<PickedLocation>(
        MaterialPageRoute(builder: (_) => MisonLocationPickerScreen(initial: initial)),
      );

  @override
  State<MisonLocationPickerScreen> createState() => _MisonLocationPickerScreenState();
}

class _MisonLocationPickerScreenState extends State<MisonLocationPickerScreen> {
  static const _dakar = LatLng(14.6928, -17.4467);

  GoogleMapController? _map;
  late LatLng _target = widget.initial ?? _dakar;
  String? _address;
  bool _resolving = false;
  bool _moving = false;
  Timer? _debounce;
  int _requestId = 0;
  /// Plan par défaut ; Satellite (avec noms de rues) pour les quartiers où le
  /// plan n'affiche pas les rues.
  bool _satellite = false;

  static bool _inDakarRegion(LatLng p) =>
      p.latitude >= 14.55 && p.latitude <= 14.90 && p.longitude >= -17.55 && p.longitude <= -17.05;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) _goToMyPosition(silent: true);
    _resolveAddress();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _map?.dispose();
    super.dispose();
  }

  /// Adresse sous l'épingle (géocodeur du téléphone, gratuit), une fois la
  /// carte immobile.
  void _resolveAddress() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final id = ++_requestId;
      setState(() => _resolving = true);
      String? address;
      try {
        address = await buildFullAddressFromLatLong(_target.latitude, _target.longitude)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        address = null;
      }
      if (!mounted || id != _requestId) return;
      setState(() {
        _address = address;
        _resolving = false;
      });
    });
  }

  Future<void> _goToMyPosition({bool silent = false}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && !silent) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (!silent) TopToast.show(message: 'Autorisez la localisation pour utiliser votre position.');
        return;
      }
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
          );
      final here = LatLng(pos.latitude, pos.longitude);
      if (silent && !_inDakarRegion(here)) return;
      _target = here;
      _map?.animateCamera(CameraUpdate.newLatLngZoom(here, 17));
      _resolveAddress();
    } catch (_) {
      if (!silent) TopToast.show(message: 'Position introuvable pour le moment.');
    }
  }

  void _confirm() {
    if (!_inDakarRegion(_target)) {
      TopToast.show(message: 'Ce lieu est hors de la région de Dakar, où Mison intervient.', type: TopToastType.error);
      return;
    }
    final address = (_address ?? '').trim().isNotEmpty ? _address!.trim() : 'Lieu choisi sur la carte';
    Navigator.pop(context, PickedLocation(_target.latitude, _target.longitude, address));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _target, zoom: widget.initial != null ? 17 : 13),
            onMapCreated: (c) => _map = c,
            mapType: _satellite ? MapType.hybrid : MapType.normal,
            onCameraMove: (pos) {
              _target = pos.target;
              if (!_moving) setState(() => _moving = true);
            },
            onCameraIdle: () {
              setState(() => _moving = false);
              _resolveAddress();
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
          ),
          // Viseur de précision : la pointe de l'épingle et le point indiquent
          // exactement le lieu choisi (centre de la carte). L'épingle se
          // soulève pendant le déplacement, le point reste sur le lieu.
          IgnorePointer(child: Center(child: _PrecisionPin(lifted: _moving))),
          // Plan / Satellite
          Positioned(
            right: 12,
            bottom: 16,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              elevation: 3,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _satellite = !_satellite),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_satellite ? Icons.map_outlined : Icons.satellite_alt_rounded, color: kMisonGold, size: 20),
                      6.width,
                      Text(_satellite ? 'Plan' : 'Satellite', style: boldTextStyle(size: 13, color: kMisonDark)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  12.width,
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
                      ),
                      child: Text('Déplacez la carte pour placer l\'épingle sur votre lieu',
                          style: secondaryTextStyle(size: 13, color: kMisonDark)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          color: context.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on_rounded, color: kMisonGold),
                10.width,
                Expanded(
                  child: Text(
                    _moving || _resolving
                        ? 'Recherche de l\'adresse…'
                        : (_address ?? 'Lieu choisi sur la carte'),
                    style: primaryTextStyle(size: 15, weight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => _goToMyPosition(),
                  child: Text('Ma position', style: boldTextStyle(size: 13, color: kMisonGold)),
                ),
              ],
            ),
            14.height,
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _moving ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMisonGold,
                  disabledBackgroundColor: kMisonGold.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Confirmer ce lieu', style: boldTextStyle(color: Colors.white, size: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Épingle de précision dessinée pour que sa pointe tombe pile au centre de
/// la carte : tête dorée, tige, et point + ombre au sol à l'endroit exact.
class _PrecisionPin extends StatelessWidget {
  final bool lifted;
  const _PrecisionPin({required this.lifted});

  @override
  Widget build(BuildContext context) {
    // Boîte de 60 × 120 centrée sur la carte : son milieu (y = 60) est le lieu.
    return SizedBox(
      width: 60,
      height: 120,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Ombre au sol, qui s'élargit quand l'épingle se soulève.
          Positioned(
            top: 55,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: lifted ? 22 : 14,
              height: lifted ? 8 : 6,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: lifted ? 0.18 : 0.28),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          // Point exact du lieu choisi.
          Positioned(
            top: 55,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: kMisonDark,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
          // Tête + tige : la pointe de la tige touche le point (y = 60).
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            top: lifted ? -12 : 0,
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: kMisonGold,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: const Icon(Icons.home_rounded, color: Colors.white, size: 18),
                ),
                Container(width: 3, height: 22, color: kMisonGold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
