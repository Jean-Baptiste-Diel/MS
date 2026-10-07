import 'package:booking_system_flutter/component/mison_start_prestation_sheet.dart';
import 'package:booking_system_flutter/component/unread_badge.dart';
import 'package:booking_system_flutter/services/chat_unread_store.dart';
import 'dart:async';

import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/utils/artisan_arrival_reporter.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/fragment/profile_fragment.dart';
import 'package:booking_system_flutter/screens/notification/notification_screen.dart';
import 'package:booking_system_flutter/screens/support_chat/support_chat_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:booking_system_flutter/component/mison_page_loader.dart';
import 'package:booking_system_flutter/utils/auto_refresh_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../component/app_empty_state.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

// Couleurs de la marque (logo)
const Color _brandGold = Color(0xFFC49716);

// Texte / icônes de l'en-tête blanc
const Color _headerDark = Color(0xFF3A3A3A);

class ArtisanDashboardScreen extends StatefulWidget {
  const ArtisanDashboardScreen({Key? key}) : super(key: key);

  @override
  State<ArtisanDashboardScreen> createState() => _ArtisanDashboardScreenState();
}

class _ArtisanDashboardScreenState extends State<ArtisanDashboardScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    ChatUnreadStore.start(); // pastilles « messages non lus »
    openColdStartAcceptedCall(); // iPhone : appel décroché app fermée
  }

  final List<Widget> _tabs = [
    const ArtisanHomeFragment(),
    const ArtisanOrdersFragment(),
    ProfileFragment(),
  ];

  void _onDestinationSelected(int index) {
    if (index == 2) {
      const SupportChatScreen().launch(context);
      return;
    }
    setState(() => _currentIndex = index == 3 ? 2 : index);
  }

  @override
  Widget build(BuildContext context) {
    return DoublePressBackWidget(
      message: language.lblBackPressMsg,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DotGridBackground(
          child: IndexedStack(
            index: _currentIndex,
            children: _tabs,
          ),
        ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: context.scaffoldBackgroundColor,
            indicatorColor: _brandGold.withValues(alpha: 0.15),
            labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? boldTextStyle(size: 12, color: _brandGold) // onglet actif en doré
                    : primaryTextStyle(size: 12, color: Colors.grey),
              ),
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex == 2 ? 3 : _currentIndex,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.dashboard_outlined, color: Colors.grey),
                selectedIcon: Icon(Icons.dashboard_rounded, color: _brandGold),
                label: 'Accueil',
              ),
              NavigationDestination(
                // Messages non lus des clients (chats de commande)
                icon: UnreadBadge(
                  count: ChatUnreadStore.ordersTotal,
                  child: ic_ticket.iconImage(color: appTextSecondaryColor),
                ),
                selectedIcon: UnreadBadge(
                  count: ChatUnreadStore.ordersTotal,
                  child: ic_ticket.iconImage(color: _brandGold),
                ),
                label: 'Commandes',
              ),
              NavigationDestination(
                icon: UnreadBadge(
                  count: ChatUnreadStore.support,
                  child: ic_chat.iconImage(color: appTextSecondaryColor),
                ),
                selectedIcon: UnreadBadge(
                  count: ChatUnreadStore.support,
                  child: ic_chat.iconImage(color: _brandGold),
                ),
                label: 'Support',
              ),
              NavigationDestination(
                icon: Observer(
                  builder: (_) => (appStore.isLoggedIn && appStore.userProfileImage.isNotEmpty)
                      ? CircleAvatar(radius: 13, backgroundImage: CachedNetworkImageProvider(appStore.userProfileImage))
                      : ic_profile2.iconImage(color: appTextSecondaryColor),
                ),
                selectedIcon: Observer(
                  builder: (_) => (appStore.isLoggedIn && appStore.userProfileImage.isNotEmpty)
                      ? CircleAvatar(radius: 13, backgroundImage: CachedNetworkImageProvider(appStore.userProfileImage))
                      : ic_profile2.iconImage(color: _brandGold),
                ),
                label: language.profile,
              ),
            ],
            onDestinationSelected: _onDestinationSelected,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fragment : Accueil artisan — stats, urgences, historique
// ─────────────────────────────────────────────────────────────────────────────

class ArtisanHomeFragment extends StatefulWidget {
  const ArtisanHomeFragment({Key? key}) : super(key: key);

  @override
  State<ArtisanHomeFragment> createState() => _ArtisanHomeFragmentState();
}

class _ArtisanHomeFragmentState extends State<ArtisanHomeFragment> with AutoRefreshMixin {
  late Future<MisonOrderResponse> _future;
  UniqueKey _key = UniqueKey();
  bool _isAvailable = true;
  Position? _artisanPosition;
  final ScrollController _scrollController = ScrollController();
  bool _isCollapsed = false;

  // Diffusion continue de la position — tourne tant que l'ouvrier a une
  // commande active, indépendamment de l'écran affiché (dashboard, chat…)
  Timer? _bgLocationTimer;
  String? _bgTrackedOrderId;

  // Prestataire LIBRE, app ouverte : position envoyée au serveur toutes les
  // 20 s, pour apparaître (en mouvement) sur la carte des clients qui cherchent.
  static const _presenceInterval = Duration(seconds: 20);
  Timer? _presenceTimer;
  bool _hasActiveOrder = false;
  bool _presenceInFlight = false;
  AppLifecycleListener? _presenceLifecycle;

  static const double _expandedHeight = 208.0;
  static const double _toolbarHeight = 72.0;

  @override
  void initState() {
    super.initState();
    _load();
    _restoreBadge();
    _fetchPosition();
    _loadAvailability();
    _scrollController.addListener(() {
      final collapsed = _scrollController.hasClients &&
          _scrollController.offset > (_expandedHeight - _toolbarHeight);
      if (collapsed != _isCollapsed) setState(() => _isCollapsed = collapsed);
    });
    LiveStream().on(LIVESTREAM_ARTISAN_HOME_REFRESH, (_) {
      if (mounted) setState(() => _load());
    });
    startAutoRefresh();
    // Position envoyée tout de suite (ouverture, retour dans l'app), puis
    // toutes les 20 s : la recherche part de là où il se trouve vraiment.
    _presenceTimer = Timer.periodic(_presenceInterval, (_) => _sendPresence());
    _presenceLifecycle = AppLifecycleListener(onResume: _sendPresence);
  }

  // ── Bouton « Disponible / Indisponible » : enregistré sur le serveur ─────
  bool _availabilitySaving = false;

  Future<void> _loadAvailability() async {
    try {
      final available = await getArtisanAvailability();
      if (mounted) setState(() => _isAvailable = available);
      _sendPresence();
    } catch (e) {
      log('[Availability] $e');
    }
  }

  Future<void> _setAvailability(bool value) async {
    if (_availabilitySaving) return;
    final previous = _isAvailable;
    setState(() {
      _isAvailable = value;
      _availabilitySaving = true;
    });
    try {
      final saved = await setArtisanAvailability(value);
      if (!mounted) return;
      setState(() => _isAvailable = saved);
      if (saved) _sendPresence(); // de nouveau disponible : position à jour tout de suite
      TopToast.show(
        message: saved
            ? 'Vous êtes disponible : les nouvelles commandes vous sont proposées.'
            : 'Vous êtes indisponible : vous ne recevez plus de nouvelles commandes.',
        type: TopToastType.success,
      );
      onAutoRefresh(); // commandes disponibles affichées / masquées
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAvailable = previous);
      TopToast.show(message: "Impossible d'enregistrer votre disponibilité. Réessayez.", type: TopToastType.error);
    } finally {
      if (mounted) setState(() => _availabilitySaving = false);
    }
  }

  Future<void> _sendPresence() async {
    final foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!foreground || !_isAvailable || _hasActiveOrder || _presenceInFlight) return;
    _presenceInFlight = true;
    try {
      // Jamais de demande d'autorisation ici : seulement si déjà accordée.
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      await postArtisanLocation(pos.latitude, pos.longitude);
    } catch (e) {
      log('[Presence] $e');
    } finally {
      _presenceInFlight = false;
    }
  }

  /// Actualisation silencieuse (nouvelles commandes, statuts) sans clignotement.
  @override
  Future<void> onAutoRefresh() async {
    final res = await getMisonOrders();
    if (mounted) setState(() => _future = Future.value(res));
  }

  @override
  void dispose() {
    stopAutoRefresh();
    _scrollController.dispose();
    LiveStream().dispose(LIVESTREAM_ARTISAN_HOME_REFRESH);
    _bgLocationTimer?.cancel();
    _presenceTimer?.cancel();
    _presenceLifecycle?.dispose();
    super.dispose();
  }

  // ── Diffusion continue de la position de l'ouvrier vers Firestore ──────────
  // Démarre/arrête automatiquement selon qu'il a (ou non) une commande en
  // cours, sans dépendre de l'écran de détail de la commande.
  void _syncLocationBroadcast(List<MisonOrder> orders) {
    // Occupé (commande acceptée ou en cours) : il n'apparaît plus comme libre.
    final wasBusy = _hasActiveOrder;
    _hasActiveOrder = orders.any((o) => o.artisan != null && o.keepsArtisanBusy);
    if (wasBusy && !_hasActiveOrder) _sendPresence();
    MisonOrder? activeOrder;
    for (final o in orders) {
      // Position envoyée seulement en route (plus une fois sur place).
      if (o.canTrack) { activeOrder = o; break; }
    }

    if (activeOrder == null || activeOrder.id == null) {
      _bgLocationTimer?.cancel();
      _bgLocationTimer = null;
      _bgTrackedOrderId = null;
      return;
    }

    if (_bgTrackedOrderId == activeOrder.id && _bgLocationTimer != null) return;

    _bgLocationTimer?.cancel();
    _bgTrackedOrderId = activeOrder.id;
    final orderId = activeOrder.id!;

    Future<void> pushPosition() async {
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        await FirebaseFirestore.instance
            .collection('artisan_locations')
            .doc(orderId)
            .set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        ArtisanArrivalReporter.check(
          orderId: orderId,
          destLat: double.tryParse(activeOrder!.latitude ?? ''),
          destLng: double.tryParse(activeOrder.longitude ?? ''),
          position: pos,
        );
      } catch (e) {
        log('[Tracking] Erreur (dashboard): $e');
      }
    }

    pushPosition();
    _bgLocationTimer = Timer.periodic(const Duration(seconds: 5), (_) => pushPosition());
  }

  Future<void> _fetchPosition() async {
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos == null) {
        final perm = await Geolocator.checkPermission();
        if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 5)),
          );
        }
      }
      if (pos == null) {
        final lat = getDoubleAsync(LATITUDE);
        final lon = getDoubleAsync(LONGITUDE);
        if (lat != 0.0 && lon != 0.0) {
          pos = Position(
            latitude: lat, longitude: lon,
            timestamp: DateTime.now(),
            accuracy: 0, altitude: 0, altitudeAccuracy: 0,
            heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
          );
        }
      }
      if (pos != null && mounted) setState(() => _artisanPosition = pos);
    } catch (_) {
      try {
        final lat = getDoubleAsync(LATITUDE);
        final lon = getDoubleAsync(LONGITUDE);
        if (lat != 0.0 && lon != 0.0 && mounted) {
          setState(() => _artisanPosition = Position(
            latitude: lat, longitude: lon,
            timestamp: DateTime.now(),
            accuracy: 0, altitude: 0, altitudeAccuracy: 0,
            heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
          ));
        }
      } catch (_) {}
    }
  }

  Future<void> _restoreBadge() async {
    final saved = getIntAsync(ARTISAN_NOTIF_BADGE_KEY);
    if (saved > 0) artisanNotifBadge.value = saved;
    // Compteur réel des notifications non lues (historique serveur)
    try {
      final res = await getMisonNotifications();
      artisanNotifBadge.value = res.unreadCount;
      await setValue(ARTISAN_NOTIF_BADGE_KEY, res.unreadCount);
    } catch (_) {}
  }

  void _load() {
    _future = getMisonOrders();
    _key = UniqueKey();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: _brandGold,
        onRefresh: () async { setState(() => _load()); },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              expandedHeight: _expandedHeight,
              floating: false,
              pinned: true,
              // Même fond que la page : l'en-tête se fond dans la grille de points
              backgroundColor: const Color(0xFFFFFFFF),
              toolbarHeight: _toolbarHeight,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.dark,
              automaticallyImplyLeading: false,
              // Logo centré en haut (salutation à gauche une fois replié)
              centerTitle: !_isCollapsed,
              title: !_isCollapsed
                  ? Image.asset('assets/logo/logo_transparent.png', height: 58)
                  : Observer(
                      builder: (_) => Text(
                        '$_greeting, ${appStore.userFirstName.isNotEmpty ? appStore.userFirstName : 'Ouvrier'}',
                        style: boldTextStyle(color: _headerDark, size: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              actions: [
                ValueListenableBuilder<int>(
                  valueListenable: artisanNotifBadge,
                  builder: (_, count, __) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined, color: _brandGold, size: 26),
                        onPressed: () {
                          artisanNotifBadge.value = 0;
                          setValue(ARTISAN_NOTIF_BADGE_KEY, 0);
                          NotificationScreen().launch(context);
                        },
                      ),
                      if (count > 0)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            decoration: BoxDecoration(
                              color: _brandGold,
                              shape: count > 9 ? BoxShape.rectangle : BoxShape.circle,
                              borderRadius: count > 9 ? BorderRadius.circular(10) : null,
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                            ),
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              style: boldTextStyle(color: Colors.white, size: 11),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                16.width,
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: Colors.transparent,
                  padding: const EdgeInsets.fromLTRB(20, _toolbarHeight, 20, 16),
                  child: Observer(
                    builder: (_) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Salutation, puis le nom en dessous
                                  Text(
                                    '$_greeting,',
                                    style: secondaryTextStyle(size: 17),
                                  ),
                                  2.height,
                                  Text(
                                    appStore.userFullName.isNotEmpty
                                        ? appStore.userFullName
                                        : (appStore.userFirstName.isNotEmpty ? appStore.userFirstName : 'Ouvrier'),
                                    style: boldTextStyle(color: _headerDark, size: 24),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  4.height,
                                  Text(
                                    DateFormat('EEEE dd MMMM yyyy', 'fr_FR').format(DateTime.now()),
                                    style: secondaryTextStyle(size: 14),
                                  ),
                                ],
                              ),
                            ),
                            12.width,
                            // Disponibilité : bouton on / off à droite de la salutation
                            _AvailabilityToggle(
                              value: _isAvailable,
                              onChanged: _setAvailability,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: SnapHelperWidget<MisonOrderResponse>(
                key: _key,
                future: _future,
                loadingWidget: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: MisonPageLoader(),
                ),
                errorBuilder: (error) => AppEmptyState(
                  type: AppEmptyStateType.error,
                  title: error,
                  retryLabel: language.reload,
                  onRetry: () => setState(() => _load()),
                ),
                onSuccess: (response) {
                  final orders = response.data ?? [];
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _syncLocationBroadcast(orders);
                  });
                  return _DashboardBody(orders: orders, artisanPosition: _artisanPosition, isAvailable: _isAvailable);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bouton de disponibilité on / off ─────────────────────────────────────────

/// Pilule qui s'enfonce à l'appui, avec un rond qui glisse (icône marche/arrêt).
class _AvailabilityToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _AvailabilityToggle({required this.value, required this.onChanged});

  @override
  State<_AvailabilityToggle> createState() => _AvailabilityToggleState();
}

class _AvailabilityToggleState extends State<_AvailabilityToggle> {
  bool _pressed = false;

  static const double _width = 112;
  static const double _height = 30;
  static const double _knob = 22;

  @override
  Widget build(BuildContext context) {
    final on = widget.value;
    final Color base = on ? Colors.green.shade600 : Colors.grey.shade500;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        widget.onChanged(!on);
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: _width,
          height: _height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_height / 2),
            // Relief : dégradé clair en haut, plus foncé en bas
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(base, Colors.white, 0.18)!, base],
            ),
            boxShadow: [
              BoxShadow(
                color: base.withValues(alpha: _pressed ? 0.25 : 0.45),
                blurRadius: _pressed ? 3 : 8,
                offset: Offset(0, _pressed ? 1 : 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Texte du côté opposé au rond
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                alignment: on ? Alignment.centerLeft : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    on ? 'Disponible' : 'Indisponible',
                    style: boldTextStyle(color: Colors.white, size: 10),
                  ),
                ),
              ),
              // Rond qui glisse
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(Icons.power_settings_new_rounded, color: base, size: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filtre appliqué à l'historique en touchant une carte de statistiques.
enum _StatFilter { total, enCours, terminees, annulees }

class _DashboardBody extends StatefulWidget {
  final List<MisonOrder> orders;
  final Position? artisanPosition;
  /// Bouton « Disponible / Indisponible » de l'accueil.
  final bool isAvailable;
  const _DashboardBody({required this.orders, this.artisanPosition, this.isAvailable = true});

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody> {
  /// null = historique récent (5 dernières missions)
  _StatFilter? _filter;

  List<MisonOrder> get orders => widget.orders;
  Position? get artisanPosition => widget.artisanPosition;

  void _toggleFilter(_StatFilter f) =>
      setState(() => _filter = _filter == f ? null : f);

  double? _distanceTo(MisonOrder order) {
    if (artisanPosition == null) return null;
    final lat = double.tryParse(order.latitude ?? '');
    final lon = double.tryParse(order.longitude ?? '');
    if (lat == null || lon == null) return null;
    return Geolocator.distanceBetween(
          artisanPosition!.latitude, artisanPosition!.longitude, lat, lon) /
        1000;
  }

  @override
  Widget build(BuildContext context) {
    // Commandes disponibles (PENDING sans artisan) = à traiter
    final urgentes  = orders.where((o) => o.isPending && o.artisan == null).toList();
    // Missions de cet artisan (déjà acceptées)
    final missions  = orders.where((o) => o.artisan != null).toList();

    final total     = missions.length;
    final enCours   = missions.where((o) => o.isActiveWithArtisan).length;
    final terminees = missions.where((o) => o.isCompleted).length;
    // Annulées par le client (CANCELLED). REJECTED n'est jamais posé par le
    // serveur (seulement par les données de démo) : filtrer dessus seul
    // donnait une liste toujours vide.
    bool isAnnulee(MisonOrder o) => o.isCancelled || o.isRejected;
    final annulees  = missions.where(isAnnulee).length;
    // Occupé avec un client (même règle que le serveur) : pas de nouvelle
    // commande tant que la prestation en cours n'est pas terminée.
    final isBusy = missions.any((o) => o.keepsArtisanBusy);

    // Historique : filtré selon la carte touchée
    final List<MisonOrder> history;
    final String historyTitle;
    final String emptySubtitle;
    switch (_filter) {
      case _StatFilter.total:
        history = missions;
        historyTitle = 'Toutes les commandes';
        emptySubtitle = 'Aucune commande ne vous a été assignée pour le moment.';
        break;
      case _StatFilter.enCours:
        history = missions.where((o) => o.isActiveWithArtisan).toList();
        historyTitle = 'Commandes en cours';
        emptySubtitle = "Vous n'avez aucune commande en cours.";
        break;
      case _StatFilter.terminees:
        history = missions.where((o) => o.isCompleted).toList();
        historyTitle = 'Commandes terminées';
        emptySubtitle = "Vous n'avez encore terminé aucune commande.";
        break;
      case _StatFilter.annulees:
        history = missions.where(isAnnulee).toList();
        historyTitle = 'Commandes annulées';
        emptySubtitle = "Aucune de vos commandes n'a été annulée.";
        break;
      case null:
        history = missions.take(5).toList();
        historyTitle = 'Historique récent';
        emptySubtitle = 'Aucune commande ne vous a été assignée pour le moment.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Stats
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(title: 'Statistiques'),
              16.height,
              // Chaque carte filtre l'historique ci-dessous (re-toucher = annuler)
              Row(children: [
                _StatCard(label: 'Total', value: total, color: _brandGold, icon: Icons.receipt_long_rounded,
                    isSelected: _filter == _StatFilter.total,
                    onTap: () => _toggleFilter(_StatFilter.total)),
                12.width,
                _StatCard(label: 'En cours', value: enCours, color: in_progress, icon: Icons.timelapse_rounded,
                    isSelected: _filter == _StatFilter.enCours,
                    onTap: () => _toggleFilter(_StatFilter.enCours)),
              ]),
              12.height,
              Row(children: [
                _StatCard(label: 'Terminées', value: terminees, color: completed, icon: Icons.check_circle_rounded,
                    isSelected: _filter == _StatFilter.terminees,
                    onTap: () => _toggleFilter(_StatFilter.terminees)),
                12.width,
                _StatCard(label: 'Annulées', value: annulees, color: rejected, icon: Icons.cancel_rounded,
                    isSelected: _filter == _StatFilter.annulees,
                    onTap: () => _toggleFilter(_StatFilter.annulees)),
              ]),
            ],
          ),
        ),

        // ── Indisponible (bouton de l'accueil) : pas de nouvelles commandes
        if (!widget.isAvailable && !isBusy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.do_not_disturb_on_outlined, size: 18, color: Colors.grey.shade600),
                  8.width,
                  Expanded(
                    child: Text(
                      'Vous êtes indisponible : vous ne recevez plus de nouvelles commandes. '
                      'Vos commandes en cours continuent normalement.',
                      style: secondaryTextStyle(size: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Occupé : explique pourquoi aucune nouvelle commande n'apparaît
        if (isBusy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _brandGold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _brandGold.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: _brandGold),
                  8.width,
                  Expanded(
                    child: Text(
                      'Vous avez une commande en cours. Les nouvelles commandes vous '
                      'seront proposées une fois la prestation terminée.',
                      style: secondaryTextStyle(size: 13, color: _brandGold),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Commandes urgentes (ASSIGNED)
        if (urgentes.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
            child: Row(
              children: [
                _SectionTitle(title: 'À traiter'),
                8.width,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _brandGold,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${urgentes.length}', style: boldTextStyle(color: Colors.white, size: 11)),
                ),
              ],
            ),
          ),
          ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: urgentes.length,
            separatorBuilder: (_, __) => 10.height,
            itemBuilder: (ctx, i) => _UrgentOrderTile(
              order: urgentes[i],
              distanceKm: _distanceTo(urgentes[i]),
            ),
          ),
        ],

        // ── Historique (récent ou filtré par une carte)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _SectionTitle(
                  title: _filter == null ? historyTitle : '$historyTitle (${history.length})',
                ),
              ),
              if (_filter != null)
                GestureDetector(
                  onTap: () => setState(() => _filter = null),
                  child: Text('Voir récent',
                      style: boldTextStyle(size: 13, color: _brandGold)),
                ),
            ],
          ),
        ),

        if (history.isEmpty)
          AppEmptyState(
            type: AppEmptyStateType.empty,
            title: 'Aucune commande',
            subtitle: emptySubtitle,
          )
        else
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: history.length,
            separatorBuilder: (_, __) => 12.height,
            itemBuilder: (ctx, i) => _RecentOrderTile(order: history[i]),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: boldTextStyle(size: 16));
  }
}

class _UrgentOrderTile extends StatelessWidget {
  final MisonOrder order;
  final double? distanceKm;
  const _UrgentOrderTile({required this.order, this.distanceKm});

  /// Date + heure ; « tout de suite » : pas d'heure (le client veut maintenant).
  String _formatDate(String? iso, {bool immediate = false}) {
    if (iso == null) return '';
    try {
      final date = DateTime.parse(iso);
      return immediate
          ? 'Tout de suite · ${DateFormat('dd MMM', 'fr_FR').format(date)}'
          : DateFormat('dd MMM · HH:mm', 'fr_FR').format(date);
    }
    catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '', distanceKm: distanceKm).launch(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _brandGold.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _brandGold.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _brandGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.assignment_late_rounded, color: _brandGold, size: 22),
            ),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.service?.name ?? 'Service',
                      style: boldTextStyle(size: 16),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  4.height,
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: Colors.grey),
                      4.width,
                      Flexible(child: Text(order.client?.fullName ?? '',
                          style: secondaryTextStyle(size: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      8.width,
                      Icon(Icons.schedule, size: 12, color: Colors.grey),
                      4.width,
                      Flexible(child: Text(_formatDate(order.serviceDate, immediate: order.isImmediate),
                          style: secondaryTextStyle(size: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
              ),
            ),
            12.width,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _brandGold,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Voir', style: boldTextStyle(color: Colors.white, size: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : context.cardColor,
          borderRadius: BorderRadius.circular(16),
          // Carte active : bordure de sa couleur
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value', style: boldTextStyle(size: 22, color: color)),
                  2.height,
                  Text(label, style: secondaryTextStyle(size: 14)),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  final MisonOrder order;
  const _RecentOrderTile({required this.order});

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try { return DateFormat('dd MMM yyyy', 'fr_FR').format(DateTime.parse(iso)); }
    catch (_) { return iso; }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'PENDING':                      return pending;
      case 'ACCEPTED':                     return accept;
      case 'AWAITING_TRAVEL_PAYMENT':      return _brandGold;
      case 'IN_PROGRESS':                  return in_progress;
      case 'AWAITING_REALIZATION_PAYMENT': return _brandGold;
      case 'COMPLETED':                    return completed;
      case 'CANCELLED':                    return cancelled;
      default:                             return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'PENDING':                      return 'Recherche d\'ouvrier';
      case 'ACCEPTED':                     return 'Ouvrier trouvé';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'En attente de paiement';
      case 'IN_PROGRESS':                  return 'Intervention en cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'En attente du paiement de la prestation';
      case 'COMPLETED':                    return 'Prestation terminée';
      case 'CANCELLED':                    return 'Commande annulée';
      default:                             return s ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '').launch(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _brandGold.withValues(alpha: 0.1),
                image: order.service?.imageUrl != null
                    ? DecorationImage(image: CachedNetworkImageProvider(order.service!.imageUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: order.service?.imageUrl == null
                  ? Icon(Icons.handyman, color: _brandGold, size: 20)
                  : null,
            ),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(order.service?.name ?? 'Service',
                            style: boldTextStyle(size: 16),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      4.width,
                      Text(_formatDate(order.serviceDate),
                          style: secondaryTextStyle(size: 13),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  6.height,
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: Colors.grey),
                      4.width,
                      Expanded(
                        child: Text(order.client?.fullName ?? '',
                            style: secondaryTextStyle(size: 14),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      8.width,
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor(order.status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_statusLabel(order.status),
                            style: boldTextStyle(size: 12, color: _statusColor(order.status)),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fragment : liste des commandes de l'artisan (2 onglets)
// ─────────────────────────────────────────────────────────────────────────────

class ArtisanOrdersFragment extends StatefulWidget {
  const ArtisanOrdersFragment({Key? key}) : super(key: key);

  @override
  State<ArtisanOrdersFragment> createState() => _ArtisanOrdersFragmentState();
}

class _ArtisanOrdersFragmentState extends State<ArtisanOrdersFragment>
    with SingleTickerProviderStateMixin, AutoRefreshMixin {
  late TabController _tabController;

  late Future<MisonOrderResponse> _allFuture;
  UniqueKey _key = UniqueKey();

  Position? _artisanPosition;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
    _fetchPosition();
    LiveStream().on(LIVESTREAM_ARTISAN_ORDERS_REFRESH, (_) {
      if (mounted) _reload();
    });
    startAutoRefresh();
  }

  @override
  Future<void> onAutoRefresh() async {
    final res = await getMisonOrders();
    if (mounted) setState(() => _allFuture = Future.value(res));
  }

  Future<void> _fetchPosition() async {
    try {
      // 1. Utiliser la dernière position connue (instantané, pas de permission)
      Position? pos = await Geolocator.getLastKnownPosition();

      // 2. Si non disponible, essayer la position GPS
      if (pos == null) {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 5)),
          );
        }
      }

      // 3. Fallback sur les coordonnées stockées lors du sign-up
      if (pos == null) {
        final lat = getDoubleAsync(LATITUDE);
        final lon = getDoubleAsync(LONGITUDE);
        if (lat != 0.0 && lon != 0.0) {
          pos = Position(
            latitude: lat, longitude: lon,
            timestamp: DateTime.now(),
            accuracy: 0, altitude: 0, altitudeAccuracy: 0,
            heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
          );
        }
      }

      if (pos != null && mounted) setState(() => _artisanPosition = pos);
    } catch (_) {
      // Tenter le fallback SharedPrefs même en cas d'erreur GPS
      try {
        final lat = getDoubleAsync(LATITUDE);
        final lon = getDoubleAsync(LONGITUDE);
        if (lat != 0.0 && lon != 0.0 && mounted) {
          setState(() => _artisanPosition = Position(
            latitude: lat, longitude: lon,
            timestamp: DateTime.now(),
            accuracy: 0, altitude: 0, altitudeAccuracy: 0,
            heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
          ));
        }
      } catch (_) {}
    }
  }

  double? _distanceTo(MisonOrder order) {
    if (_artisanPosition == null) return null;
    final lat = double.tryParse(order.latitude ?? '');
    final lon = double.tryParse(order.longitude ?? '');
    if (lat == null || lon == null) return null;
    final meters = Geolocator.distanceBetween(
      _artisanPosition!.latitude, _artisanPosition!.longitude, lat, lon,
    );
    return meters / 1000;
  }

  @override
  void dispose() {
    stopAutoRefresh();
    _tabController.dispose();
    LiveStream().dispose(LIVESTREAM_ARTISAN_ORDERS_REFRESH);
    super.dispose();
  }

  void _load() {
    _allFuture = getMisonOrders();
    _key = UniqueKey();
  }

  void _reload() => setState(() => _load());

  Future<void> _doAction(Future<MisonActionResponse> Function() action) async {
    appStore.setLoading(true);
    try {
      final res = await action();
      TopToast.show(message: res.message ?? 'Succès', type: TopToastType.success);
      _reload();
    } catch (e) {
      TopToast.show(message: e.toString(), type: TopToastType.error);
    } finally {
      appStore.setLoading(false);
    }
  }

  /// Confirmation aux couleurs Mison avant d'accepter, démarrer ou se désister.
  Future<void> _confirmAction({
    required String title,
    required String subtitle,
    required Future<MisonActionResponse> Function() action,
    IconData icon = Icons.check_circle_outline_rounded,
    String confirmLabel = 'Confirmer',
    bool danger = false,
  }) async {
    final ok = await showMisonConfirmSheet(
      context,
      title: title,
      subtitle: subtitle,
      icon: icon,
      confirmLabel: confirmLabel,
      danger: danger,
    );
    if (ok) _doAction(action);
  }

  Widget _buildCard(MisonOrder order) {
    final distanceKm = _distanceTo(order);
    return GestureDetector(
      onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '', distanceKm: distanceKm).launch(context),
      child: _ArtisanOrderCard(
        order: order,
        distanceKm: distanceKm,
        onApprove: ((order.isPending && order.artisan == null) ||
                order.needsArtisanConfirmation)
            ? () => _confirmAction(
                  title: order.needsArtisanConfirmation
                      ? 'Confirmer la commande'
                      : 'Accepter la commande',
                  subtitle: order.needsArtisanConfirmation
                      ? 'Cette commande vous a été affectée par Mison. La confirmez-vous ?'
                      : 'Confirmez-vous l\'acceptation de cette commande ?',
                  action: () => artisanAcceptOrder(order.id!),
                  icon: Icons.assignment_turned_in_outlined,
                  confirmLabel: order.needsArtisanConfirmation ? 'Oui, je confirme' : "Oui, j'accepte",
                )
            : null,
        // Seulement une fois arrivé chez le client (avant : « Aller chez le
        // client » depuis le détail de la commande).
        onStart: (order.hasArrived && !order.needsArtisanConfirmation)
            ? () async {
                // Même panneau que l'annulation : vérifications puis démarrage.
                if (await showMisonStartPrestationSheet(context, orderId: order.id!)) _reload();
              }
            : null,
        onRelease: order.canReleaseByArtisan
            ? () => _confirmAction(
                  title: 'Se désister',
                  subtitle: 'La commande sera reproposée aux autres ouvriers. Confirmez-vous ?',
                  action: () async {
                    await cancelMisonOrder(order.id!);
                    return MisonActionResponse(message: 'Vous vous êtes désisté de cette commande');
                  },
                  icon: Icons.event_busy_rounded,
                  confirmLabel: 'Oui, me désister',
                  danger: true,
                )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Logo centré + fond de la page, comme l'accueil
      appBar: MisonAppBar(
        title: 'Mes Commandes',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _brandGold,
          indicatorWeight: 3,
          labelColor: _headerDark,
          unselectedLabelColor: Colors.grey,
          labelStyle: boldTextStyle(size: 14, color: _headerDark),
          unselectedLabelStyle: secondaryTextStyle(size: 13),
          tabs: const [
            Tab(text: 'À traiter'),
            Tab(text: 'Mes missions'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              // ── Onglet "À traiter" : PENDING sans artisan assigné
              _OrderTab(
                key: ValueKey('pending_$_key'),
                future: _allFuture,
                filter: (o) => o.isPending && o.artisan == null,
                tabLabel: 'À traiter',
                buildCard: _buildCard,
                onReload: _reload,
              ),
              // ── Onglet "Mes missions" : artisan assigné
              _OrderTab(
                key: ValueKey('missions_$_key'),
                future: _allFuture,
                filter: (o) => o.artisan != null,
                tabLabel: 'Mes missions',
                buildCard: _buildCard,
                onReload: _reload,
              ),
            ],
          ),
          Observer(builder: (_) => LoaderWidget().visible(appStore.isLoading)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet générique : filtre la liste de commandes et affiche les cartes
// ─────────────────────────────────────────────────────────────────────────────

class _OrderTab extends StatefulWidget {
  final Future<MisonOrderResponse> future;
  final bool Function(MisonOrder) filter;
  final String tabLabel;
  final Widget Function(MisonOrder) buildCard;
  final VoidCallback onReload;

  const _OrderTab({
    Key? key,
    required this.future,
    required this.filter,
    required this.tabLabel,
    required this.buildCard,
    required this.onReload,
  }) : super(key: key);

  @override
  State<_OrderTab> createState() => _OrderTabState();
}

class _OrderTabState extends State<_OrderTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<MisonOrderResponse>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MisonPageLoader();
        }
        if (snapshot.hasError) {
          return AppEmptyState(
            type: AppEmptyStateType.error,
            title: snapshot.error.toString(),
            onRetry: widget.onReload,
          );
        }
        final all = snapshot.data?.data ?? [];
        final filtered = all.where(widget.filter).toList();
        return RefreshIndicator(
          color: _brandGold,
          onRefresh: () async => widget.onReload(),
          child: filtered.isEmpty
              ? CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      child: AppEmptyState(
                        type: AppEmptyStateType.empty,
                        title: 'Aucune commande',
                        subtitle: 'Aucune commande dans "${widget.tabLabel}" pour le moment.',
                        retryLabel: 'Actualiser',
                        onRetry: widget.onReload,
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => widget.buildCard(filtered[i]),
                ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card d'une commande pour l'artisan
// ─────────────────────────────────────────────────────────────────────────────

class _ArtisanOrderCard extends StatelessWidget {
  final MisonOrder order;
  final double? distanceKm;
  final VoidCallback? onApprove;
  final VoidCallback? onStart;
  final VoidCallback? onRelease;

  const _ArtisanOrderCard({
    required this.order,
    this.distanceKm,
    this.onApprove,
    this.onStart,
    this.onRelease,
  });

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try { return DateFormat('dd MMM yyyy', 'fr_FR').format(DateTime.parse(iso)); }
    catch (_) { return iso; }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try { return DateFormat('HH:mm').format(DateTime.parse(iso)); }
    catch (_) { return ''; }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'PENDING':                      return pending;
      case 'ACCEPTED':                     return accept;
      case 'AWAITING_TRAVEL_PAYMENT':      return _brandGold;
      case 'IN_PROGRESS':                  return in_progress;
      case 'AWAITING_REALIZATION_PAYMENT': return _brandGold;
      case 'COMPLETED':                    return completed;
      case 'CANCELLED':                    return cancelled;
      default:                             return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'PENDING':                      return 'Recherche d\'ouvrier';
      case 'ACCEPTED':                     return 'Ouvrier trouvé';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'En attente de paiement';
      case 'IN_PROGRESS':                  return 'Intervention en cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'En attente du paiement de la prestation';
      case 'COMPLETED':                    return 'Prestation terminée';
      case 'CANCELLED':                    return 'Commande annulée';
      default:                             return s ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientName = order.client?.fullName ?? 'Client';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: _brandGold.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Commande pas encore acceptée : « Prestation demandée chez : » puis le nom
                if (order.isPending || order.needsArtisanConfirmation) ...[
                  Text('Prestation demandée chez :', style: secondaryTextStyle(size: 13)),
                  3.height,
                ],
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: _headerDark),
                    6.width,
                    Expanded(
                      child: Text(
                        clientName,
                        style: boldTextStyle(size: 16, color: _headerDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                6.height,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(order.status),
                    style: boldTextStyle(size: 14, color: _statusColor(order.status)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Service + date/time
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _brandGold.withValues(alpha: 0.1),
                    image: order.service?.imageUrl != null
                        ? DecorationImage(image: CachedNetworkImageProvider(order.service!.imageUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: order.service?.imageUrl == null
                      ? Icon(Icons.handyman, color: _brandGold, size: 22)
                      : null,
                ),
                12.width,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.service?.name ?? 'Service', style: boldTextStyle(size: 16),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      6.height,
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
                          4.width,
                          Text(_formatDate(order.serviceDate), style: secondaryTextStyle(size: 14)),
                          12.width,
                          // « Tout de suite » : pas d'heure
                          if (order.isImmediate)
                            Text('Tout de suite', style: boldTextStyle(size: 14, color: _brandGold))
                          else ...[
                            Icon(Icons.access_time, size: 12, color: Colors.grey),
                            4.width,
                            Text(_formatTime(order.serviceDate), style: secondaryTextStyle(size: 14)),
                          ],
                        ],
                      ),
                      if (order.serviceAddress != null && order.serviceAddress!.isNotEmpty) ...[
                        4.height,
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 12, color: Colors.grey),
                            4.width,
                            Expanded(
                              child: Text(order.serviceAddress!, style: secondaryTextStyle(size: 14),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Distance badge (commandes à traiter uniquement) : plus utile une
          // fois chez le client (prestation en cours) ni en attente du paiement.
          if (distanceKm != null &&
              order.status != 'CANCELLED' &&
              order.status != 'REJECTED' &&
              order.status != 'COMPLETED' &&
              !order.isInProgress &&
              !order.isAwaitingRealizationPayment)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _brandGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _brandGold.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.near_me_rounded, size: 14, color: _brandGold),
                    6.width,
                    Text(
                      'Prestation demandée à ${distanceKm! < 1 ? '${(distanceKm! * 1000).round()} m' : '${distanceKm!.toStringAsFixed(1)} km'} de vous',
                      style: boldTextStyle(size: 14, color: _brandGold),
                    ),
                  ],
                ),
              ),
            ),

          // Action buttons
          if (onApprove != null || onStart != null || onRelease != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  if (onApprove != null)
                    AppButton(
                      width: double.infinity,
                      color: _brandGold, // bouton Accepter / Confirmer en doré
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: onApprove,
                      child: Text(
                        order.needsArtisanConfirmation ? 'Confirmer' : 'Accepter',
                        style: boldTextStyle(color: Colors.white, size: 14),
                      ),
                    ),
                  if (onStart != null)
                    AppButton(
                      width: double.infinity,
                      color: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: onStart,
                      child: Text('Commencer la prestation', style: boldTextStyle(color: Colors.white, size: 14)),
                    ),
                  if (onRelease != null) ...[
                    8.height,
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: rejected,
                        side: BorderSide(color: rejected.withValues(alpha: 0.5)),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: onRelease,
                      child: Text('Se désister', style: boldTextStyle(color: rejected, size: 14)),
                    ),
                  ],
                ],
              ),
            )
          else
            16.height,
        ],
      ),
    );
  }
}

