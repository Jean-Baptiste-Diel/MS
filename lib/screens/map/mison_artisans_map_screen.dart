import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/component/mison_offline_banner.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_artisan_reviews_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_search_service_screen.dart';
import 'package:booking_system_flutter/utils/require_login.dart';
import 'package:booking_system_flutter/utils/service_icons.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nb_utils/nb_utils.dart';

/// Onglet « Notre réseau » : carte des prestataires inscrits autour du client, une
/// icône par service. Filtre par service, avis, et commande du service.
class MisonArtisansMapScreen extends StatefulWidget {
  const MisonArtisansMapScreen({Key? key}) : super(key: key);

  @override
  State<MisonArtisansMapScreen> createState() => _MisonArtisansMapScreenState();
}

class _MisonArtisansMapScreenState extends State<MisonArtisansMapScreen> {
  static const String _mapStyle = '[{"featureType":"poi","stylers":[{"visibility":"off"}]},'
      '{"featureType":"transit","stylers":[{"visibility":"off"}]}]';
  static const LatLng _dakar = LatLng(14.7167, -17.4677);
  static const int _radiusKm = 30;

  GoogleMapController? _map;
  bool _hasLocation = false;
  bool _loading = true;

  /// Prestataires affichés depuis le téléphone (pas de réseau).
  bool _offline = false;
  static const _kMapCacheKey = 'mison_network_map_cache';

  /// Fiche du prestataire touché : elle se ferme seule après 3 s.
  Timer? _cardTimer;

  /// Filtres restants dépliés (bouton « + »), comme « Mes commandes ».
  bool _showAllFilters = false;
  static const int _visibleFilterCount = 3; // services sur la ligne, après « Tous »

  // Couleurs des filtres de « Mes commandes ».
  static const Color _chipBg = Color(0xFFE9EAEC);
  static const Color _chipSelectedBg = Color(0xFFF3E7C4);
  static const Color _chipSelectedText = Color(0xFF8A6A0F);

  List<Map<String, dynamic>> _artisans = [];
  List<MisonService> _services = [];
  String? _serviceFilter; // id du service, null = tous
  Map<String, dynamic>? _selected;

  /// Centre de la dernière recherche, et centre actuel de la carte.
  LatLng _fetchedAt = _dakar;
  LatLng _cameraTarget = _dakar;
  bool _showSearchHere = false;

  /// Icônes déjà dessinées : « nom du service|disponible ».
  final Map<String, BitmapDescriptor> _icons = {};

  @override
  void initState() {
    super.initState();
    getMisonServices().then((r) {
      if (mounted) setState(() => _services = (r.data ?? []).where((s) => s.isAvailable != false).toList());
    }).catchError((_) {});
    _start();
  }

  /// Affiche la fiche du prestataire pendant 3 s.
  void _showCard(Map<String, dynamic> a) {
    // Hors ligne : pas de fiche (infos pas à jour, avis et commande impossibles).
    if (_offline) {
      TopToast.show(message: 'Vous êtes hors ligne. Connectez-vous pour voir ce prestataire.');
      return;
    }
    _cardTimer?.cancel();
    setState(() => _selected = a);
    _cardTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _selected = null);
    });
  }

  @override
  void dispose() {
    _cardTimer?.cancel();
    super.dispose();
  }

  /// Derniers prestataires enregistrés (tous services), vide si aucun.
  List<Map<String, dynamic>> _savedArtisans() {
    final saved = getStringAsync(_kMapCacheKey);
    if (saved.isEmpty) return [];
    try {
      return (jsonDecode(saved) as List).whereType<Map>().map((a) => a.cast<String, dynamic>()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _start() async {
    // D'abord les prestataires de la dernière ouverture : la carte s'affiche
    // tout de suite, même hors connexion ; le serveur les remplace ensuite.
    final saved = _savedArtisans();
    if (saved.isNotEmpty) {
      await _prepareIcons(saved);
      if (mounted) {
        setState(() {
          _artisans = saved;
          _totalCount = saved.length;
        });
      }
    }
    final position = await _myPosition(ask: false);
    if (position != null) {
      _fetchedAt = _cameraTarget = position;
      _map?.moveCamera(CameraUpdate.newLatLngZoom(position, 13));
    }
    await _load(_fetchedAt);
  }

  /// Position du téléphone ; [ask] : demande l'autorisation si besoin.
  Future<LatLng?> _myPosition({required bool ask}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (ask && permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
      );
      if (mounted && !_hasLocation) setState(() => _hasLocation = true);
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Nombre total de prestataires (tous services), du dernier chargement
  /// sans filtre : le compteur n'affiche pas le nombre par service.
  int? _totalCount;

  /// Numéro de la dernière requête : une réponse plus ancienne (service
  /// changé entre-temps) est ignorée.
  int _request = 0;

  /// Service choisi : rayon élargi, pour trouver ses ouvriers même loin.
  static const int _serviceRadiusKm = 100;

  Future<void> _load(LatLng center, {bool fit = false}) async {
    final request = ++_request;
    final serviceId = _serviceFilter;
    setState(() {
      _loading = true;
      _showSearchHere = false;
    });
    try {
      final artisans = await getArtisansMap(
        lat: center.latitude,
        lng: center.longitude,
        radiusKm: serviceId == null ? _radiusKm : _serviceRadiusKm,
        serviceId: serviceId,
      );
      await _prepareIcons(artisans);
      if (!mounted || request != _request) return;
      setState(() {
        _artisans = artisans;
        if (serviceId == null) _totalCount = artisans.length;
        _fetchedAt = center;
        if (_selected != null && !artisans.any((a) => a['id'] == _selected!['id'])) _selected = null;
      });
      if (serviceId == null) setValue(_kMapCacheKey, jsonEncode(artisans));
      if (_offline) setState(() => _offline = false);
      if (fit) _fitTo(artisans, center);
    } catch (e) {
      if (request != _request || !mounted) return;
      if (isOfflineError(e)) {
        // Hors ligne : on garde ce qui est affiché (ou la dernière liste).
        final saved = _artisans.isEmpty ? _savedArtisans() : const <Map<String, dynamic>>[];
        if (saved.isNotEmpty) await _prepareIcons(saved);
        if (!mounted) return;
        setState(() {
          _offline = true;
          if (saved.isNotEmpty) {
            _artisans = saved;
            _totalCount ??= saved.length;
          }
        });
      } else {
        TopToast.show(message: 'Impossible de charger les prestataires. Réessayez.', type: TopToastType.error);
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  /// Service choisi : requête au serveur pour ses ouvriers, puis la carte
  /// se cadre sur eux (et sur le client).
  void _chooseService(String? id) {
    // Filtre choisi : les filtres dépliés se replient (le choisi reste visible
    // sur la ligne).
    if (id == _serviceFilter) {
      if (_showAllFilters) setState(() => _showAllFilters = false);
      return;
    }
    setState(() {
      _serviceFilter = id;
      _selected = null;
      _showAllFilters = false;
    });
    _load(_cameraTarget, fit: id != null);
  }

  void _fitTo(List<Map<String, dynamic>> artisans, LatLng center) {
    final points = [
      for (final a in artisans)
        if (a['latitude'] is num && a['longitude'] is num)
          LatLng((a['latitude'] as num).toDouble(), (a['longitude'] as num).toDouble()),
    ];
    if (points.isEmpty) return;
    // Réponse triée du plus proche au plus loin : 15 suffisent à cadrer.
    final shown = [center, ...points.take(15)];
    double minLat = shown.first.latitude, maxLat = minLat, minLng = shown.first.longitude, maxLng = minLng;
    for (final p in shown) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    if (maxLat - minLat < 0.01 && maxLng - minLng < 0.01) {
      _map?.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }
    _map?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      70,
    ));
  }

  Future<void> _recenter() async {
    final position = await _myPosition(ask: true);
    if (position == null) {
      TopToast.show(message: 'Activez la localisation pour voir les prestataires autour de vous.');
      return;
    }
    _map?.animateCamera(CameraUpdate.newLatLngZoom(position, 13));
    _cameraTarget = position;
    await _load(position);
  }

  void _onCameraIdle() {
    // Carte déplacée loin de la dernière recherche : proposer de chercher ici.
    final far = _distanceKm(_fetchedAt, _cameraTarget) > _radiusKm * 0.5;
    if (far != _showSearchHere) setState(() => _showSearchHere = far);
  }

  static double _distanceKm(LatLng a, LatLng b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude) / 1000;

  List<Map<String, dynamic>> get _visible =>
      _serviceFilter == null ? _artisans : _artisans.where((a) => a['service_id'] == _serviceFilter).toList();

  /// Ouvriers du service choisi : épingles plus grandes.
  bool get _big => _serviceFilter != null;

  // ---------------------------------------------------------------- icônes

  String _iconKey(Map<String, dynamic> a, {bool? big}) =>
      '${a['service_name']}|${a['is_available'] == true}|${big ?? _big}';

  Future<void> _prepareIcons(List<Map<String, dynamic>> artisans) async {
    for (final a in artisans) {
      final style = serviceStyle(a['service_name']?.toString());
      for (final big in const [false, true]) {
        final key = _iconKey(a, big: big);
        if (_icons.containsKey(key)) continue;
        // Épingles un peu plus petites : la carte en affiche beaucoup.
        _icons[key] = await serviceMarkerIcon(style, available: a['is_available'] == true, big: big, scale: 0.85);
      }
    }
  }

  Set<Marker> get _markers => {
        for (final a in _visible)
          if (a['latitude'] is num && a['longitude'] is num)
            Marker(
              markerId: MarkerId(a['id'].toString()),
              position: LatLng((a['latitude'] as num).toDouble(), (a['longitude'] as num).toDouble()),
              icon: _icons[_iconKey(a)] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
              anchor: const Offset(0.5, 1),
              zIndexInt: a['is_available'] == true ? 1 : 0,
              onTap: () => _showCard(a),
            ),
      };

  // ---------------------------------------------------------------- actions

  MisonService? _serviceOf(Map<String, dynamic> a) =>
      _services.where((s) => s.id == a['service_id']?.toString()).firstOrNull;

  void _order(Map<String, dynamic> a) {
    final service = _serviceOf(a);
    if (service == null) {
      TopToast.show(message: "Ce service n'est pas disponible pour le moment.");
      return;
    }
    // Commande proposée à ce prestataire ; s'il refuse, recherche habituelle.
    MisonBookingFormScreen(
      service: service,
      artisanId: a['id']?.toString(),
      artisanName: a['name']?.toString(),
    ).launch(context);
  }

  void _openReviews(Map<String, dynamic> a) {
    MisonArtisanReviewsScreen(artisanId: a['id'].toString(), artisanName: a['name']?.toString() ?? '').launch(context);
  }

  /// Visiteur sans compte : se connecter, puis la carte se recharge avec
  /// le détail des prestataires (nom, photo, avis).
  Future<void> _loginToSeeDetails() async {
    _cardTimer?.cancel();
    setState(() => _selected = null);
    if (await requireClientLogin(context) && mounted) _load(_fetchedAt);
  }

  // ---------------------------------------------------------------- écran

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final visible = _visible;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _cameraTarget, zoom: 12),
            // Seulement nos prestataires : commerces, lieux et transports masqués.
            style: _mapStyle,
            onMapCreated: (c) => _map = c,
            markers: _markers,
            myLocationEnabled: _hasLocation,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            onCameraMove: (p) => _cameraTarget = p.target,
            onCameraIdle: _onCameraIdle,
            onTap: (_) {
              if (_selected != null) setState(() => _selected = null);
            },
          ),
          // En-tête : recherche de service + filtres.
          Positioned(
            top: top + 10,
            left: 0,
            right: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _searchBar(_totalCount),
                ),
                10.height,
                _filters(),
                if (_offline) const Center(child: MisonOfflineBanner(margin: EdgeInsets.only(top: 10))),
                if (_showSearchHere && !_loading) ...[
                  12.height,
                  Center(
                    child: _pill(
                      icon: Icons.refresh_rounded,
                      label: 'Rechercher dans cette zone',
                      onTap: () => _load(_cameraTarget),
                    ),
                  ),
                ],
                // Chargement (service, zone) : celui des autres pages, en pastille.
                if (_loading && _totalCount != null) ...[
                  12.height,
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10)],
                      ),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: LoaderWidget(colors: [kMisonDark, kMisonGold]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Premier chargement : fond et chargement des autres pages, par-dessus
          // la carte.
          if (_loading && _totalCount == null)
            const Positioned.fill(
              child: DotGridBackground(
                child: Center(child: LoaderWidget(colors: [kMisonDark, kMisonGold])),
              ),
            ),
          // Suit la fiche : remonte quand elle s'ouvre, redescend avec elle.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            right: 16,
            bottom: (_selected != null ? 230 : 24) + MediaQuery.of(context).padding.bottom,
            child: FloatingActionButton.small(
              heroTag: 'mison_map_locate',
              backgroundColor: Colors.white,
              elevation: 3,
              onPressed: _recenter,
              child: const Icon(Icons.my_location_rounded, color: kMisonDark),
            ),
          ),
          // Fiche du prestataire : toute la largeur, collée à la barre de
          // navigation. Elle monte en apparaissant et redescend en fondu.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              reverseDuration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.bottomCenter,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: _selected == null
                  ? const SizedBox(key: ValueKey('no_card'), width: double.infinity)
                  : KeyedSubtree(key: ValueKey(_selected!['id']), child: _artisanCard(_selected!)),
            ),
          ),
          if (!_loading && visible.isEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24 + MediaQuery.of(context).padding.bottom,
              child: _emptyCard(),
            ),
        ],
      ),
    );
  }

  Widget _searchBar(int? count) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => const MisonSearchServiceScreen().launch(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            const Icon(Icons.search_rounded, color: kMisonGold),
            10.width,
            Expanded(
              child: Text('Rechercher un service', style: secondaryTextStyle(size: 14)),
            ),
            if (count != null)
              Text(
                '$count prestataire${count > 1 ? 's' : ''}',
                style: boldTextStyle(size: 12, color: kMisonDark),
              ),
          ]),
        ),
      ),
    );
  }

  /// Filtres par service, présentés comme ceux de « Mes commandes » :
  /// « Tous » + 3 services sur une ligne, bouton « + » pour déplier le reste.
  /// Choisir un service va chercher ses ouvriers au serveur.
  Widget _filters() {
    final names = <String, String>{
      for (final s in _services)
        if (s.id != null) s.id!: s.name ?? '',
      for (final a in _artisans) a['service_id'].toString(): a['service_name']?.toString() ?? '',
    };
    final ids = names.keys.toList()..sort((a, b) => names[a]!.compareTo(names[b]!));
    if (ids.isEmpty) return const SizedBox.shrink();

    // Service choisi parmi les cachés : il prend la dernière place de la ligne.
    var first = ids.take(_visibleFilterCount).toList();
    if (_serviceFilter != null && ids.contains(_serviceFilter) && !first.contains(_serviceFilter)) {
      first = [...first.take(_visibleFilterCount - 1), _serviceFilter!];
    }
    final hidden = ids.where((id) => !first.contains(id)).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(children: [
                  _chip('Tous', null),
                  for (final id in first) ...[6.width, _chip(names[id]!, id)],
                ]),
              ),
            ),
            if (hidden.isNotEmpty) ...[6.width, _moreFiltersButton()],
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _showAllFilters && hidden.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final id in hidden) _chip(names[id]!, id)],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? id) {
    final selected = _serviceFilter == id;
    return GestureDetector(
      // Re-toucher le service actif = tous les services.
      onTap: () => _chooseService(selected ? null : id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _chipSelectedBg : _chipBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? _chipSelectedText : kMisonDark,
          ),
        ),
      ),
    );
  }

  Widget _moreFiltersButton() {
    final expanded = _showAllFilters;
    return GestureDetector(
      onTap: () => setState(() => _showAllFilters = !_showAllFilters),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        decoration: BoxDecoration(shape: BoxShape.circle, color: expanded ? _chipSelectedBg : _chipBg),
        child: Icon(
          expanded ? Icons.remove_rounded : Icons.add_rounded,
          size: 18,
          color: expanded ? _chipSelectedText : kMisonDark,
        ),
      ),
    );
  }

  Widget _pill({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: kMisonDark,
      elevation: 3,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: Colors.white),
            8.width,
            Text(label, style: boldTextStyle(size: 13, color: Colors.white)),
          ]),
        ),
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Row(children: [
        const Icon(Icons.location_off_outlined, color: kMisonGold),
        12.width,
        Expanded(
          child: Text(
            "Aucun prestataire dans cette zone pour l'instant. Déplacez la carte ou choisissez un autre service.",
            style: secondaryTextStyle(size: 13),
          ),
        ),
      ]),
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))],
      );

  /// Fiche d'un prestataire pour un visiteur sans compte : service et
  /// disponibilité seulement, connexion demandée pour le reste.
  Widget _guestCard(Map<String, dynamic> a) {
    final style = serviceStyle(a['service_name']?.toString());
    final available = a['is_available'] == true;
    final busy = a['is_busy'] == true;
    final distance = (a['distance_km'] as num?)?.toDouble();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: style.color.withValues(alpha: 0.15),
              child: Icon(style.icon, color: style.color),
            ),
            12.width,
            Expanded(
              child: Text(
                a['service_name']?.toString() ?? 'Prestataire',
                style: boldTextStyle(size: 16, color: kMisonDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => setState(() => _selected = null),
            ),
          ]),
          10.height,
          Wrap(spacing: 12, runSpacing: 6, children: [
            if (distance != null) _info(Icons.near_me_outlined, '≈ ${_formatKm(distance)}'),
            _info(
              available ? Icons.circle : Icons.circle_outlined,
              available ? 'Disponible' : (busy ? 'En mission' : 'Indisponible'),
              color: available ? Colors.green : (busy ? kMisonGold : Colors.grey),
            ),
          ]),
          8.height,
          Text('Connectez-vous pour voir ce prestataire, ses avis et le commander.', style: secondaryTextStyle(size: 13)),
          14.height,
          ElevatedButton.icon(
            onPressed: _loginToSeeDetails,
            icon: const Icon(Icons.lock_outline_rounded, size: 18, color: Colors.white),
            label: Text('Se connecter', style: boldTextStyle(size: 13, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kMisonGold,
              elevation: 0,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _artisanCard(Map<String, dynamic> a) {
    // Sans compte (ou carte enregistrée avant la connexion) : fiche réduite.
    if (!appStore.isLoggedIn || a['name'] == null) return _guestCard(a);
    final style = serviceStyle(a['service_name']?.toString());
    final available = a['is_available'] == true;
    final busy = a['is_busy'] == true;
    final rating = double.tryParse(a['average_rating']?.toString() ?? '') ?? 0;
    final reviews = (a['total_reviews'] as num?)?.toInt() ?? 0;
    final distance = (a['distance_km'] as num?)?.toDouble();
    final years = (a['experience_years'] as num?)?.toInt() ?? 0;
    final photo = a['profile_picture_url']?.toString() ?? '';
    final serviceName = a['service_name']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            photo.isNotEmpty
                ? CachedImageWidget(url: photo, height: 52, width: 52, circle: true, fit: BoxFit.cover)
                : CircleAvatar(
                    radius: 26,
                    backgroundColor: style.color.withValues(alpha: 0.15),
                    child: Icon(style.icon, color: style.color),
                  ),
            12.width,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      a['name']?.toString() ?? 'Prestataire',
                      style: boldTextStyle(size: 16, color: kMisonDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (a['is_certified'] == true) ...[
                    4.width,
                    const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF1E88E5)),
                  ],
                ]),
                2.height,
                Row(children: [
                  Icon(style.icon, size: 14, color: style.color),
                  4.width,
                  Flexible(
                    child: Text(serviceName, style: secondaryTextStyle(size: 13), overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => setState(() => _selected = null),
            ),
          ]),
          10.height,
          Wrap(spacing: 12, runSpacing: 6, children: [
            _info(
                Icons.star_rounded, reviews > 0 ? '${rating.toStringAsFixed(1)} ($reviews avis)' : 'Pas encore d\'avis',
                color: Colors.amber.shade700),
            if (distance != null) _info(Icons.near_me_outlined, '≈ ${_formatKm(distance)}'),
            if (years > 0) _info(Icons.work_history_outlined, '$years an${years > 1 ? 's' : ''} d\'expérience'),
            _info(
              available ? Icons.circle : Icons.circle_outlined,
              available ? 'Disponible' : (busy ? 'En mission' : 'Indisponible'),
              color: available ? Colors.green : (busy ? kMisonGold : Colors.grey),
            ),
          ]),
          14.height,
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _openReviews(a),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kMisonGold),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Voir les avis', style: boldTextStyle(size: 13, color: kMisonGold)),
              ),
            ),
            // En mission ou indisponible : pas de commande possible.
            if (available) ...[
            10.width,
            Expanded(
              child: ElevatedButton(
                onPressed: () => _order(a),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMisonGold,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Commander',
                  style: boldTextStyle(size: 13, color: Colors.white),
                ),
              ),
            ),
            ],
          ]),
        ],
      ),
    );
  }

  static String _formatKm(double km) =>
      km < 1 ? '${(math.max(km, 0.1) * 1000).round()} m' : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';

  Widget _info(IconData icon, String text, {Color? color}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color ?? Colors.grey.shade600),
      4.width,
      Text(text, style: secondaryTextStyle(size: 12)),
    ]);
  }
}
