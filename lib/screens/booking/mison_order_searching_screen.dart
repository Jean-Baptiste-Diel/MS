import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold;
import 'package:booking_system_flutter/component/mison_cancel_order_sheet.dart';
import 'package:booking_system_flutter/component/mison_discreet_cancel_button.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nb_utils/nb_utils.dart';

/// Recherche d'un prestataire, façon Yango : carte centrée sur le client,
/// radar animé, cercle du rayon de recherche (5 → 10 → 15 km) et prestataires
/// disponibles autour (positions approximatives, sans identité).
///
/// Dès qu'un prestataire accepte, l'écran laisse la place au détail de la commande.
class MisonOrderSearchingScreen extends StatefulWidget {
  final String orderId;

  /// Commande déjà connue de l'écran précédent : la carte s'affiche tout de
  /// suite, sans attendre la première réponse du serveur.
  final MisonOrder? initialOrder;

  const MisonOrderSearchingScreen({super.key, required this.orderId, this.initialOrder});

  @override
  State<MisonOrderSearchingScreen> createState() => _MisonOrderSearchingScreenState();
}

class _MisonOrderSearchingScreenState extends State<MisonOrderSearchingScreen>
    with SingleTickerProviderStateMixin {
  static const _pollEvery = Duration(seconds: 6);

  late final AnimationController _radar =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  Timer? _poll;
  GoogleMapController? _map;

  MisonOrder? _order;
  // Prestataires libres, par clé stable : position affichée (qui glisse vers
  // la nouvelle position reçue) et position de départ de l'animation.
  final Map<String, LatLng> _shown = {};
  Map<String, LatLng> _from = {};
  Map<String, LatLng> _to = {};
  Timer? _glide;
  static const _glideTicks = 25; // 25 × 80 ms = 2 s
  int _radiusKm = 5;
  bool _exhausted = false;
  bool _leaving = false;

  BitmapDescriptor? _artisanIcon;
  BitmapDescriptor? _clientIcon;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _radiusKm = widget.initialOrder?.searchRadiusKm ?? _radiusKm;
    _buildIcons();
    _refresh();
    _poll = Timer.periodic(_pollEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _glide?.cancel();
    _radar.dispose();
    _map?.dispose();
    super.dispose();
  }

  LatLng? get _center {
    final lat = double.tryParse(_order?.latitude ?? '');
    final lng = double.tryParse(_order?.longitude ?? '');
    return (lat == null || lng == null) ? null : LatLng(lat, lng);
  }

  /// Zoom de quartier (≈ 3 km de large à 5 km de rayon), qui recule un peu
  /// quand la recherche s'élargit : 5 km → 14, 10 km → 13,2, 15 km → 12,7.
  double _zoomFor(int radiusKm) => 14.0 - 0.8 * math.log(radiusKm / 5) / math.ln2;

  Future<void> _refresh() async {
    if (_leaving) return;
    try {
      final results = await Future.wait([
        getMisonOrderDetail(widget.orderId),
        getOrderNearbyArtisans(widget.orderId),
      ]);
      if (!mounted || _leaving) return;
      final order = (results[0] as MisonOrderDetailResponse).data;
      final nearby = results[1] as Map<String, dynamic>;
      if (order == null) return;

      if (!order.isPending) return _leave(order);

      final previousRadius = _radiusKm;
      final hadCenter = _center != null;
      setState(() {
        _order = order;
        _radiusKm = (nearby['search_radius_km'] as num?)?.toInt() ?? order.searchRadiusKm ?? _radiusKm;
        _exhausted = nearby['search_exhausted'] == true || order.isSearchHandledByTeam;
      });
      _moveArtisans(((nearby['artisans'] as List?) ?? []).whereType<Map>().toList());
      // Rayon élargi : la caméra recule pour montrer tout le cercle.
      final center = _center;
      if (center != null && (!hadCenter || previousRadius != _radiusKm)) {
        _map?.animateCamera(CameraUpdate.newLatLngZoom(center, _zoomFor(_radiusKm)));
      }
    } catch (_) {
      // Réseau instable : on réessaie au prochain tour, l'écran reste affiché.
    }
  }

  /// Nouvelles positions : chaque prestataire glisse de sa position affichée
  /// vers la nouvelle en 2 s (les nouveaux apparaissent directement).
  void _moveArtisans(List<Map> artisans) {
    final next = <String, LatLng>{};
    for (var i = 0; i < artisans.length; i++) {
      final a = artisans[i];
      final key = a['key']?.toString() ?? 'a$i';
      next[key] = LatLng((a['latitude'] as num).toDouble(), (a['longitude'] as num).toDouble());
    }
    _glide?.cancel();
    setState(() {
      _shown.removeWhere((key, _) => !next.containsKey(key));
      _from = {for (final e in next.entries) e.key: _shown[e.key] ?? e.value};
      _to = next;
      _shown.addAll(_from);
    });
    final moving = next.keys.any((k) => _from[k] != _to[k]);
    if (!moving) return;
    var tick = 0;
    _glide = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      tick++;
      final t = Curves.easeInOut.transform(tick / _glideTicks);
      if (!mounted) return timer.cancel();
      setState(() {
        for (final key in _to.keys) {
          final a = _from[key]!, b = _to[key]!;
          _shown[key] = LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
        }
      });
      if (tick >= _glideTicks) timer.cancel();
    });
  }

  /// Plus en recherche : prestataire trouvé → détail ; annulée → retour.
  void _leave(MisonOrder order) {
    _leaving = true;
    _poll?.cancel();
    if (order.isCancelled || order.isRejected) {
      TopToast.show(message: 'Votre commande a été annulée.');
      finish(context);
      return;
    }
    TopToast.show(message: 'Un prestataire a accepté votre commande !', type: TopToastType.success);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MisonOrderDetailScreen(orderId: widget.orderId)),
    );
  }

  void _openDetail() {
    _leaving = true;
    _poll?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MisonOrderDetailScreen(orderId: widget.orderId)),
    );
  }

  Future<void> _cancel() async {
    final cancelled = await showMisonCancelOrderSheet(context, orderId: widget.orderId);
    if (cancelled && mounted) {
      _leaving = true;
      _poll?.cancel();
      finish(context);
    }
  }

  // ── Icônes de la carte ────────────────────────────────────────────────────

  Future<void> _buildIcons() async {
    final artisan = await _roundIcon(
      background: kMisonGold,
      glyph: Icons.engineering_rounded,
      glyphColor: Colors.white,
    );
    final client = await _roundIcon(
      background: const Color(0xFF1B1F2A),
      glyph: Icons.home_rounded,
      glyphColor: Colors.white,
    );
    if (!mounted) return;
    setState(() {
      _artisanIcon = artisan;
      _clientIcon = client;
    });
  }

  Future<BitmapDescriptor> _roundIcon({
    required Color background,
    required IconData glyph,
    required Color glyphColor,
  }) async {
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
        style: TextStyle(fontSize: size * 0.42, fontFamily: glyph.fontFamily, package: glyph.fontPackage, color: glyphColor),
      )
      ..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 40, height: 40);
  }

  Set<Marker> _markers(LatLng center) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('client'),
        position: center,
        icon: _clientIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 2,
      ),
    };
    for (final entry in _shown.entries) {
      markers.add(Marker(
        markerId: MarkerId('artisan_${entry.key}'),
        position: entry.value,
        icon: _artisanIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        anchor: const Offset(0.5, 0.5),
      ));
    }
    return markers;
  }

  // ── Interface ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = _center;
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (center == null)
                  // Ouverture sans commande connue : le temps de la charger.
                  Container(
                    color: const Color(0xFFEFEFEF),
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(color: kMisonGold),
                  )
                else
                  GoogleMap(
                    initialCameraPosition: CameraPosition(target: center, zoom: _zoomFor(_radiusKm)),
                    onMapCreated: (c) => _map = c,
                    markers: _markers(center),
                    circles: {
                      Circle(
                        circleId: const CircleId('radius'),
                        center: center,
                        radius: _radiusKm * 1000.0,
                        fillColor: kMisonGold.withValues(alpha: 0.07),
                        strokeColor: kMisonGold.withValues(alpha: 0.55),
                        strokeWidth: 2,
                      ),
                    },
                    // Carte fixe : le radar reste centré sur le client.
                    scrollGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                  ),
                // Radar : ondes qui partent du client.
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _radar,
                      builder: (_, __) => CustomPaint(painter: _RadarPainter(_radar.value, _exhausted)),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
                      onPressed: () => finish(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildPanel(),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    final order = _order;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: context.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _radar,
            builder: (_, __) {
              final dots = '.' * (1 + (_radar.value * 3).floor() % 3);
              return Text(
                _exhausted ? 'Votre demande est en cours' : 'Recherche d\'un prestataire près de vous$dots',
                style: boldTextStyle(size: 18),
              );
            },
          ),
          // Recherche prise en charge par l'équipe : on explique au client.
          if (_exhausted) ...[
            6.height,
            Text(
              'Aucun prestataire disponible pour le moment. '
              "Notre équipe s'en occupe et vous prévient dès qu'un prestataire est trouvé.",
              style: secondaryTextStyle(size: 13),
            ),
          ],
          if (order != null) ...[
            16.height,
            Row(children: [
              const Icon(Icons.handyman_rounded, color: kMisonGold, size: 20),
              10.width,
              Expanded(child: Text(order.service?.name ?? '', style: primaryTextStyle(size: 14, weight: FontWeight.w600))),
            ]),
            if ((order.serviceAddress ?? '').isNotEmpty) ...[
              8.height,
              Row(children: [
                Icon(Icons.location_on_rounded, color: Colors.grey.shade600, size: 20),
                10.width,
                Expanded(
                  child: Text(order.serviceAddress!, style: secondaryTextStyle(size: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ],
          ],
          18.height,
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: _openDetail,
              style: OutlinedButton.styleFrom(
                foregroundColor: kMisonGold,
                side: const BorderSide(color: kMisonGold, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Voir ma commande', style: boldTextStyle(size: 15, color: kMisonGold)),
            ),
          ),
          10.height,
          MisonDiscreetCancelButton(label: 'Annuler la commande', onTap: _cancel, expanded: true),
        ],
      ),
    );
  }
}

/// Ondes concentriques qui partent du centre (position du client).
class _RadarPainter extends CustomPainter {
  final double t;
  final bool calm;

  _RadarPainter(this.t, this.calm);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.48;
    const waves = 3;
    for (var i = 0; i < waves; i++) {
      final progress = (t + i / waves) % 1.0;
      final radius = 18 + progress * (maxRadius - 18);
      final opacity = (1 - progress) * (calm ? 0.18 : 0.35);
      canvas.drawCircle(center, radius, Paint()..color = kMisonGold.withValues(alpha: opacity * 0.35));
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = kMisonGold.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t || old.calm != calm;
}
