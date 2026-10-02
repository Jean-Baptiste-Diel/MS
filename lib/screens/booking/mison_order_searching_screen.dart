import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold;
import 'package:booking_system_flutter/component/mison_cancel_order_sheet.dart';
import 'package:booking_system_flutter/component/mison_discreet_cancel_button.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart';
import 'package:booking_system_flutter/utils/artisan_eta_tracker.dart';
import 'package:booking_system_flutter/utils/colors.dart' show completed;
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nb_utils/nb_utils.dart';

/// Suivi d'une commande sur la carte, côté client, du début à la fin :
///
/// 1. Recherche, façon Yango : carte centrée sur le client, radar animé,
///    cercle du rayon de recherche (5 → 10 → 15 km) et prestataires
///    disponibles autour (positions approximatives, sans identité).
/// 2. Prestataire trouvé : suivi de sa position et de son trajet jusqu'au
///    client, puis arrivée et intervention. Le bouton « Détails » déplie sa
///    photo, son nom, sa note et le service.
///
/// S'il se désiste, l'écran repasse tout seul en recherche. Prestation
/// terminée (paiement, note…) : place au détail de la commande.
class MisonOrderSearchingScreen extends StatefulWidget {
  final String orderId;

  /// Commande déjà connue de l'écran précédent : la carte s'affiche tout de
  /// suite, sans attendre la première réponse du serveur.
  final MisonOrder? initialOrder;

  /// Commande tout juste confirmée : bandeau « Commande confirmée » en haut
  /// de la carte pendant 3 s.
  final bool justConfirmed;

  /// Ouvert depuis la notification de désistement : bandeau qui l'explique.
  final bool artisanReleased;

  const MisonOrderSearchingScreen({
    super.key,
    required this.orderId,
    this.initialOrder,
    this.justConfirmed = false,
    this.artisanReleased = false,
  });

  /// Commande dont le suivi est à l'écran : une notification de cette
  /// commande ne rouvre pas l'écran par-dessus lui-même.
  static String? openOrderId;

  /// Commande suivie sur la carte : en recherche, ou prestataire en approche,
  /// sur place ou au travail. Sinon (terminée, annulée…), le détail.
  static bool canFollow(MisonOrder order) =>
      (order.latitude ?? '').isNotEmpty &&
      (order.isPending || order.isBeforeStart || (order.isInProgress && order.artisan != null));

  /// Ouvre le suivi si la commande s'y prête, sinon son détail.
  static Widget screenFor(MisonOrder order) => canFollow(order)
      ? MisonOrderSearchingScreen(orderId: order.id ?? '', initialOrder: order)
      : MisonOrderDetailScreen(orderId: order.id ?? '');

  @override
  State<MisonOrderSearchingScreen> createState() => _MisonOrderSearchingScreenState();
}

/// Bandeau affiché quelques secondes en haut de la carte.
enum _Notice { confirmed, found, released }

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

  _Notice? _notice;
  Timer? _noticeHide;

  // Minuteur de recherche (depuis son début, ou son redémarrage après un
  // désistement) et message qui change toutes les 30 s. ValueNotifier : seul
  // le panneau se redessine.
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  late DateTime _searchStart = _searchStartOf(widget.initialOrder) ?? DateTime.now();
  Timer? _clock;
  static const _messageEvery = 30;
  static const _messages = [
    'Recherche en cours…',
    'Patientez encore un instant…',
    'Encore quelques secondes…',
    'Nous y sommes presque…',
    'Merci de votre patience…',
    'Toujours en cours, ne quittez pas…',
  ];

  // Suivi du prestataire (position + trajet), partagé avec le détail.
  ArtisanEtaTracker? _tracker;
  bool _fittedOnArtisan = false;
  bool _detailsOpen = false;

  BitmapDescriptor? _artisanIcon;
  BitmapDescriptor? _clientIcon;

  bool get _searching => _order?.isPending ?? true;

  @override
  void initState() {
    super.initState();
    MisonOrderSearchingScreen.openOrderId = widget.orderId;
    _order = widget.initialOrder;
    _radiusKm = widget.initialOrder?.searchRadiusKm ?? _radiusKm;
    _buildIcons();
    if (_order != null && !_searching) _startTracking(_order!);
    _refresh();
    _poll = Timer.periodic(_pollEvery, (_) => _refresh());
    if (widget.justConfirmed) _showNotice(_Notice.confirmed);
    if (widget.artisanReleased) _showNotice(_Notice.released);
    _tickClock();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _noticeHide?.cancel();
    _clock?.cancel();
    _elapsed.dispose();
    _stopTracking();
    if (MisonOrderSearchingScreen.openOrderId == widget.orderId) MisonOrderSearchingScreen.openOrderId = null;
    _glide?.cancel();
    _radar.dispose();
    _map?.dispose();
    super.dispose();
  }

  static DateTime? _searchStartOf(MisonOrder? order) =>
      DateTime.tryParse(order?.searchStartedAt ?? order?.createdAt ?? '')?.toLocal();

  void _tickClock() {
    final elapsed = DateTime.now().difference(_searchStart);
    _elapsed.value = elapsed.isNegative ? Duration.zero : elapsed;
  }

  void _showNotice(_Notice notice) {
    _noticeHide?.cancel();
    setState(() => _notice = notice);
    final duration = switch (notice) {
      _Notice.confirmed => const Duration(seconds: 3),
      _Notice.found => const Duration(seconds: 4),
      _Notice.released => const Duration(seconds: 6),
    };
    _noticeHide = Timer(duration, () {
      if (mounted) setState(() => _notice = null);
    });
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
      final wasSearching = _order == null ? null : _searching;
      // Prestataires autour : seulement en recherche (sans effet après).
      final results = await Future.wait([
        getMisonOrderDetail(widget.orderId),
        if (wasSearching ?? true)
          getOrderNearbyArtisans(widget.orderId).catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted || _leaving) return;
      final order = (results[0] as MisonOrderDetailResponse).data;
      if (order == null) return;

      if (!MisonOrderSearchingScreen.canFollow(order)) return _leave(order);

      if (!order.isPending) {
        setState(() => _order = order);
        if (wasSearching != false) _onArtisanFound(order, announce: wasSearching == true);
        return;
      }

      // En recherche (de nouveau, si le prestataire s'est désisté).
      if (wasSearching == false) _onArtisanReleased();
      _searchStart = _searchStartOf(order) ?? _searchStart;
      final nearby = results.length > 1 ? results[1] as Map<String, dynamic> : <String, dynamic>{};
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
      if (center != null && (!hadCenter || previousRadius != _radiusKm || wasSearching == false)) {
        _map?.animateCamera(CameraUpdate.newLatLngZoom(center, _zoomFor(_radiusKm)));
      }
    } catch (_) {
      // Réseau instable : on réessaie au prochain tour, l'écran reste affiché.
    }
  }

  /// Un prestataire a accepté : fin du radar, début du suivi.
  void _onArtisanFound(MisonOrder order, {required bool announce}) {
    _glide?.cancel();
    setState(() {
      _shown.clear();
      _detailsOpen = false;
    });
    if (announce) _showNotice(_Notice.found);
    _startTracking(order);
  }

  /// Le prestataire s'est désisté : retour au radar, minuteur relancé.
  void _onArtisanReleased() {
    _stopTracking();
    _showNotice(_Notice.released);
  }

  void _startTracking(MisonOrder order) {
    if (_tracker != null) return;
    final center = _center;
    _fittedOnArtisan = false;
    _tracker = ArtisanEtaTracker.acquire(widget.orderId, center)..addListener(_onTrackerUpdate);
    if (center != null) _map?.animateCamera(CameraUpdate.newLatLngZoom(center, 15));
    // Position déjà connue (suivi partagé avec le détail) : cadrage immédiat.
    if (_tracker!.artisanPosition != null) _onTrackerUpdate();
  }

  void _stopTracking() {
    _tracker?.removeListener(_onTrackerUpdate);
    _tracker?.release();
    _tracker = null;
  }

  void _onTrackerUpdate() {
    if (!mounted) return;
    setState(() {});
    if (!_fittedOnArtisan) {
      _fittedOnArtisan = true;
      _fitArtisanAndClient();
    }
  }

  /// Cadre le prestataire et l'adresse du client.
  void _fitArtisanAndClient() {
    final a = _tracker?.artisanPosition;
    final c = _center;
    if (_map == null || c == null) return;
    if (a == null) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(c, 15));
      return;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(math.min(a.latitude, c.latitude) - 0.002, math.min(a.longitude, c.longitude) - 0.002),
      northeast: LatLng(math.max(a.latitude, c.latitude) + 0.002, math.max(a.longitude, c.longitude) + 0.002),
    );
    _map!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
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

  /// Plus rien à suivre : annulée → retour ; terminée, paiement… → détail.
  void _leave(MisonOrder order) {
    _leaving = true;
    _poll?.cancel();
    if (order.isCancelled || order.isRejected) {
      TopToast.show(message: 'Votre commande a été annulée.');
      finish(context);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MisonOrderDetailScreen(orderId: widget.orderId)),
    );
  }

  /// Détail (appel, discussion, paiement…) par-dessus : le retour revient ici.
  void _openDetail() => MisonOrderDetailScreen(orderId: widget.orderId).launch(context);

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
    if (_searching) {
      for (final entry in _shown.entries) {
        markers.add(Marker(
          markerId: MarkerId('artisan_${entry.key}'),
          position: entry.value,
          icon: _artisanIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          anchor: const Offset(0.5, 0.5),
        ));
      }
    } else if (_tracker?.artisanPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('my_artisan'),
        position: _tracker!.artisanPosition!,
        icon: _artisanIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 3,
      ));
    }
    return markers;
  }

  /// Trajet du prestataire jusqu'au client, pendant qu'il est en route.
  Set<Polyline> get _polylines {
    final eta = _tracker?.eta;
    if (_searching || eta == null || !(_order?.isEnRoute ?? false)) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: eta.points,
        color: kMisonGold,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  // ── Interface ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = _center;
    final searching = _searching;
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
                    initialCameraPosition: CameraPosition(target: center, zoom: searching ? _zoomFor(_radiusKm) : 15),
                    onMapCreated: (c) {
                      _map = c;
                      if (!searching) WidgetsBinding.instance.addPostFrameCallback((_) => _fitArtisanAndClient());
                    },
                    markers: _markers(center),
                    polylines: _polylines,
                    circles: {
                      if (searching)
                        Circle(
                          circleId: const CircleId('radius'),
                          center: center,
                          radius: _radiusKm * 1000.0,
                          fillColor: kMisonGold.withValues(alpha: 0.07),
                          strokeColor: kMisonGold.withValues(alpha: 0.55),
                          strokeWidth: 2,
                        ),
                    },
                    // En recherche, carte fixe : le radar reste centré sur le
                    // client. Pendant le suivi, carte libre.
                    scrollGesturesEnabled: !searching,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    zoomGesturesEnabled: !searching,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                  ),
                // Radar : ondes qui partent du client.
                if (searching)
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
                // Recentrer sur le prestataire et le client.
                if (!searching && center != null)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: IconButton(
                        icon: const Icon(Icons.center_focus_strong_rounded, color: kMisonGold),
                        onPressed: _fitArtisanAndClient,
                      ),
                    ),
                  ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 76,
                  right: 16,
                  child: _buildNotice(),
                ),
              ],
            ),
          ),
          _buildPanel(),
        ],
      ),
    );
  }

  /// Bandeau du moment (commande confirmée, prestataire trouvé, désistement) :
  /// il descend du haut, puis disparaît au bout de quelques secondes.
  Widget _buildNotice() {
    final notice = _notice;
    final firstName = _order?.artisan?.firstName ?? '';
    final Widget child;
    if (notice == null) {
      child = const SizedBox.shrink(key: ValueKey('none'));
    } else {
      final (Color color, IconData icon, String title, String body) = switch (notice) {
        _Notice.confirmed => (
            completed,
            Icons.check_circle_rounded,
            'Commande confirmée',
            'Nous recherchons un prestataire près de vous. Vous serez notifié dès qu\'il accepte.',
          ),
        _Notice.found => (
            completed,
            Icons.person_pin_circle_rounded,
            'Prestataire trouvé !',
            firstName.isEmpty ? 'Un prestataire a accepté votre commande.' : '$firstName a accepté votre commande.',
          ),
        _Notice.released => (
            const Color(0xFFE8833A),
            Icons.info_rounded,
            'Votre prestataire s\'est désisté',
            'Pas d\'inquiétude : nous en cherchons un autre près de vous.',
          ),
      };
      child = Container(
        key: ValueKey(notice),
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 30),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: boldTextStyle(size: 17, color: Colors.white)),
                  4.height,
                  Text(body, style: primaryTextStyle(size: 13, color: Colors.white.withValues(alpha: 0.92))),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Titre du panneau en recherche : message qui change toutes les 30 s + minuteur.
  Widget _buildSearchTitle() {
    return ValueListenableBuilder<Duration>(
      valueListenable: _elapsed,
      builder: (_, elapsed, __) {
        final message = _exhausted
            ? 'Votre demande est en cours'
            : _messages[(elapsed.inSeconds ~/ _messageEvery) % _messages.length];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topLeft,
                  children: [...previous, if (current != null) current],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(message, key: ValueKey(message), style: boldTextStyle(size: 18)),
              ),
            ),
            12.width,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kMisonGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, color: kMisonGold, size: 16),
                  4.width,
                  Text(
                    _formatElapsed(elapsed),
                    style: boldTextStyle(size: 14, color: kMisonGold)
                        .copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Étape du suivi : titre, précision et icône.
  (String, String, IconData) _trackingStatus(MisonOrder order) {
    final name = order.artisan?.firstName?.trim();
    final who = (name == null || name.isEmpty) ? 'Votre prestataire' : name;
    final service = order.service?.name ?? 'prestation';
    if (order.isInProgress) {
      return ('Intervention en cours', '$who s\'occupe de votre $service.', Icons.handyman_rounded);
    }
    if (order.hasArrived) {
      return (
        '$who est arrivé',
        'Demandez-lui de lancer la prestation dans l\'app Mison.',
        Icons.where_to_vote_rounded,
      );
    }
    if (order.isEnRoute) {
      final eta = _tracker?.eta;
      final detail = eta == null
          ? 'En route vers votre adresse.'
          : 'Arrivée vers ${eta.arrivalTime} · ${eta.durationText} · ${eta.distanceText}';
      return ('$who est en route', detail, Icons.directions_car_rounded);
    }
    if (order.needsArtisanConfirmation) {
      return ('Prestataire affecté', '$who doit encore confirmer la commande.', Icons.person_pin_circle_rounded);
    }
    return ('Prestataire trouvé', '$who va bientôt partir vers vous.', Icons.person_pin_circle_rounded);
  }

  Widget _buildTrackingTitle(MisonOrder order) {
    final (title, detail, icon) = _trackingStatus(order);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: kMisonGold.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: kMisonGold, size: 24),
        ),
        12.width,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: boldTextStyle(size: 18)),
              3.height,
              Text(detail, style: secondaryTextStyle(size: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  /// « Détails » : déplie la photo, le nom, la note du prestataire et le service.
  Widget _buildArtisanDetails(MisonOrder order) {
    final artisan = order.artisan;
    if (artisan == null) return const SizedBox.shrink();
    final reviews = artisan.totalReviews ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _detailsOpen = !_detailsOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.badge_outlined, color: kMisonGold, size: 20),
                8.width,
                Expanded(child: Text('Détails du prestataire', style: boldTextStyle(size: 15, color: kMisonGold))),
                AnimatedRotation(
                  turns: _detailsOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: kMisonGold),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: !_detailsOpen
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kMisonGold.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      CachedImageWidget(
                        url: artisan.profilePictureUrl ?? '',
                        height: 64,
                        width: 64,
                        fit: BoxFit.cover,
                        circle: true,
                      ),
                      14.width,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              artisan.fullName.isEmpty ? 'Prestataire Mison' : artisan.fullName,
                              style: boldTextStyle(size: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            6.height,
                            Row(
                              children: [
                                for (var i = 1; i <= 5; i++)
                                  Icon(
                                    artisan.rating >= i
                                        ? Icons.star_rounded
                                        : artisan.rating >= i - 0.5
                                            ? Icons.star_half_rounded
                                            : Icons.star_outline_rounded,
                                    color: kMisonGold,
                                    size: 18,
                                  ),
                                6.width,
                                Flexible(
                                  child: Text(
                                    reviews == 0
                                        ? 'Nouveau'
                                        : '${artisan.rating.toStringAsFixed(1)} ($reviews avis)',
                                    style: secondaryTextStyle(size: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            8.height,
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.handyman_rounded, color: kMisonGold, size: 14),
                                5.width,
                                Flexible(
                                  child: Text(
                                    order.service?.name ?? '',
                                    style: boldTextStyle(size: 12, color: kMisonGold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    final order = _order;
    final searching = _searching;
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
          if (searching || order == null) ...[
            _buildSearchTitle(),
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
          ] else ...[
            _buildTrackingTitle(order),
            10.height,
            _buildArtisanDetails(order),
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
          if (order == null || order.canCancelByClient) ...[
            10.height,
            MisonDiscreetCancelButton(label: 'Annuler la commande', onTap: _cancel, expanded: true),
          ],
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
