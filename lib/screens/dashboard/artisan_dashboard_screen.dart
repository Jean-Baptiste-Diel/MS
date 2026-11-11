import 'package:booking_system_flutter/utils/feature_flags.dart';
import 'package:booking_system_flutter/screens/cash/cash_debt_screen.dart';
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
import 'package:booking_system_flutter/utils/app_update.dart';
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

class _ArtisanDashboardScreenState extends State<ArtisanDashboardScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Doit encore à MISON (espèces, échéance passée) : écran de paiement bloquant.
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && FeatureFlags.cashTracking) CashDebtScreen.checkAndShow(context);
    });
    ChatUnreadStore.start(); // pastilles « messages non lus »
    openColdStartAcceptedCall(); // appel décroché app fermée (iPhone et Android)
    // App relancée alors qu'il est déjà chez le client : « Commencer la prestation ».
    Future.delayed(const Duration(seconds: 1), ArtisanArrivalReporter.promptPendingStart);
    // Nouvelle version (facultative) ou version trop ancienne (bloquante).
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) checkAppUpdate(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && FeatureFlags.cashTracking) CashDebtScreen.checkAndShow(context);
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


  static const double _expandedHeight = 150.0;
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

  /// Avatar (photo ou initiales), « Bon après-midi · lun. 5 oct. », nom,
  /// bouton Disponible et cloche des notifications.
  Widget _buildHeader() {
    final name = appStore.userFullName.isNotEmpty
        ? appStore.userFullName
        : (appStore.userFirstName.isNotEmpty ? appStore.userFirstName : 'Ouvrier');
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final date = DateFormat('EEE d MMM', 'fr_FR').format(DateTime.now());
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _brandGold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            image: appStore.userProfileImage.isNotEmpty
                ? DecorationImage(image: CachedNetworkImageProvider(appStore.userProfileImage), fit: BoxFit.cover)
                : null,
          ),
          alignment: Alignment.center,
          child: appStore.userProfileImage.isNotEmpty
              ? null
              : Text(initials, style: boldTextStyle(color: _headerDark, size: 13)),
        ),
        12.width,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$_greeting · $date', style: secondaryTextStyle(size: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              2.height,
              Text(name, style: boldTextStyle(color: _headerDark, size: 20), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        8.width,
        _AvailabilityToggle(value: _isAvailable, onChanged: _setAvailability),
      ],
    );
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
                  alignment: Alignment.bottomLeft,
                  // Sous la barre du haut (logo) : barre d'état du téléphone comprise.
                  padding: EdgeInsets.fromLTRB(20, _toolbarHeight + MediaQuery.of(context).padding.top + 4, 20, 12),
                  child: Observer(builder: (_) => _buildHeader()),
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
                  return _DashboardBody(
                    orders: orders,
                    artisanPosition: _artisanPosition,
                    isAvailable: _isAvailable,
                    onChanged: () => setState(() => _load()),
                  );
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
  /// Commande acceptée / refusée : l'accueil se recharge.
  final VoidCallback? onChanged;
  const _DashboardBody({required this.orders, this.artisanPosition, this.isAvailable = true, this.onChanged});

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

  Set<String> get _dismissed => dismissedProposedOrders();

  Future<void> _accept(MisonOrder order) async {
    final ok = await showMisonConfirmSheet(
      context,
      title: order.isPendingDirectRequest ? 'Accepter la demande' : 'Accepter la commande',
      subtitle: order.isPendingDirectRequest
          ? 'Ce client vous a choisi. Acceptez-vous sa demande ?'
          : "Confirmez-vous l'acceptation de cette commande ?",
      icon: Icons.assignment_turned_in_outlined,
      confirmLabel: "Oui, j'accepte",
    );
    if (!ok) return;
    appStore.setLoading(true);
    try {
      final res = await artisanAcceptOrder(order.id!);
      TopToast.show(message: res.message ?? 'Commande acceptée', type: TopToastType.success);
      widget.onChanged?.call();
    } catch (e) {
      TopToast.show(message: e.toString(), type: TopToastType.error);
    } finally {
      appStore.setLoading(false);
    }
  }

  Future<void> _refuse(MisonOrder order) async {
    if (order.isPendingDirectRequest) {
      // Demande qui lui est adressée : le client est prévenu.
      final ok = await showMisonConfirmSheet(
        context,
        title: 'Refuser la demande',
        subtitle: "Le client sera prévenu et sa demande sera proposée à d'autres prestataires.",
        icon: Icons.event_busy_rounded,
        confirmLabel: 'Oui, refuser',
        danger: true,
      );
      if (!ok) return;
      appStore.setLoading(true);
      try {
        await cancelMisonOrder(order.id!);
        TopToast.show(message: 'Demande refusée', type: TopToastType.success);
        widget.onChanged?.call();
      } catch (e) {
        TopToast.show(message: e.toString(), type: TopToastType.error);
      } finally {
        appStore.setLoading(false);
      }
      return;
    }
    // Commande proposée à plusieurs ouvriers : on la retire de l'accueil.
    await dismissProposedOrder(order.id ?? '');
    if (mounted) setState(() {});
  }

  /// Gains de la semaine (depuis lundi) : prix des commandes terminées.
  int _weekEarnings(List<MisonOrder> missions) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    var total = 0;
    for (final o in missions.where((o) => o.isCompleted)) {
      final at = DateTime.tryParse(o.updatedAt ?? o.serviceDate ?? '')?.toLocal();
      if (at == null || at.isBefore(monday)) continue;
      total += o.agreedPrice ?? (num.tryParse(o.realizationFee ?? '')?.round() ?? 0);
    }
    return total;
  }

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
    final dismissed = _dismissed;
    final urgentesAll = orders.where((o) => o.isPending && o.artisan == null).toList();
    // La plus récente en grand (« Nouvelle commande »), les autres en dessous.
    final proposees = urgentesAll.where((o) => !dismissed.contains(o.id)).toList();
    final newOrder = proposees.isNotEmpty ? proposees.first : null;
    final urgentes = proposees.skip(1).toList();
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
        historyTitle = 'Commandes récentes';
        emptySubtitle = 'Aucune commande ne vous a été assignée pour le moment.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Gains de la semaine et compteurs (chaque compteur filtre la liste)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _WeekCard(
            earnings: _weekEarnings(missions),
            counters: [
              _Counter('Total', total, _headerDark, _filter == _StatFilter.total, () => _toggleFilter(_StatFilter.total)),
              _Counter('En cours', enCours, in_progress, _filter == _StatFilter.enCours, () => _toggleFilter(_StatFilter.enCours)),
              _Counter('Terminées', terminees, completed, _filter == _StatFilter.terminees, () => _toggleFilter(_StatFilter.terminees)),
              _Counter('Annulées', annulees, rejected, _filter == _StatFilter.annulees, () => _toggleFilter(_StatFilter.annulees)),
            ],
          ),
        ),

        // ── Nouvelle commande (la plus récente proposée), en grand
        if (newOrder != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _NewOrderCard(
              order: newOrder,
              distanceKm: _distanceTo(newOrder),
              onAccept: () => _accept(newOrder),
              onRefuse: () => _refuse(newOrder),
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
                _SectionTitle(title: 'Autres commandes à traiter'),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _GroupedList(
              children: [
                for (final o in urgentes) _UrgentOrderTile(order: o, distanceKm: _distanceTo(o)),
              ],
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
                )
              else if (missions.length > history.length)
                // « Voir tout » : toutes les commandes de l'ouvrier.
                GestureDetector(
                  onTap: () => _toggleFilter(_StatFilter.total),
                  child: Text('Voir tout', style: boldTextStyle(size: 13, color: _kAccent)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: _GroupedList(children: [for (final o in history) _RecentOrderTile(order: o)]),
          ),
      ],
    );
  }
}

// Couleur des actions de l'accueil (bordure « Nouvelle commande », Accepter, Voir tout) : le doré MISON.
const Color _kAccent = _brandGold;

// Commandes proposées (à plusieurs ouvriers) que l'ouvrier a refusées : plus
// affichées, ni sur l'accueil ni dans « Mes commandes › Missions ».
const _kDismissedOrdersKey = 'artisan_home_dismissed_orders';
Set<String> dismissedProposedOrders() => getStringListAsync(_kDismissedOrdersKey)?.toSet() ?? {};
Future<void> dismissProposedOrder(String id) =>
    setValue(_kDismissedOrdersKey, {...dismissedProposedOrders(), id}.toList());

/// « Nouvelle commande » : n°, service, adresse, créneau, montant, Refuser / Accepter.
class _NewOrderCard extends StatelessWidget {
  final MisonOrder order;
  final double? distanceKm;
  final VoidCallback onAccept;
  final VoidCallback onRefuse;
  const _NewOrderCard({required this.order, this.distanceKm, required this.onAccept, required this.onRefuse});

  String get _slot {
    final date = DateTime.tryParse(order.serviceDate ?? '')?.toLocal();
    if (date == null) return '';
    if (order.isImmediate) return 'Tout de suite · ${DateFormat('EEE d MMM', 'fr_FR').format(date)}';
    return DateFormat("EEE d MMM 'à' HH:mm", 'fr_FR').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final ref = (order.id ?? '').length >= 8 ? order.id!.substring(0, 8).toUpperCase() : (order.id ?? '');
    return GestureDetector(
      onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '', distanceKm: distanceKm).launch(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kAccent, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.isPendingDirectRequest ? 'DEMANDE POUR VOUS' : 'NOUVELLE COMMANDE',
                    style: boldTextStyle(size: 12, color: _kAccent, letterSpacing: 0.8),
                  ),
                ),
                Text('#$ref', style: secondaryTextStyle(size: 12)),
              ],
            ),
            10.height,
            Text(order.service?.name ?? 'Service', style: boldTextStyle(size: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
            6.height,
            if (_slot.isNotEmpty)
              Row(children: [
                const Icon(Icons.schedule, size: 15, color: Colors.grey),
                6.width,
                Expanded(child: Text(_slot, style: secondaryTextStyle(size: 13))),
              ]),
            16.height,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRefuse,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB3261E),
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Refuser', style: boldTextStyle(color: const Color(0xFFB3261E))),
                  ),
                ),
                12.width,
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Accepter', style: boldTextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Counter {
  final String label;
  final int value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Counter(this.label, this.value, this.color, this.selected, this.onTap);
}

/// « Gains cette semaine » et les compteurs Total / En cours / Terminées / Annulées.
class _WeekCard extends StatelessWidget {
  final int earnings;
  final List<_Counter> counters;
  const _WeekCard({required this.earnings, required this.counters});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Gains cette semaine', style: secondaryTextStyle(size: 14))),
              Text(NumberFormat.decimalPattern('fr_FR').format(earnings), style: boldTextStyle(size: 22)),
              6.width,
              Text('FCFA', style: secondaryTextStyle(size: 13)),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              for (final c in counters)
                Expanded(
                  child: GestureDetector(
                    onTap: c.onTap,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c.value}', style: boldTextStyle(size: 18, color: c.color)),
                          // Compteur choisi (liste filtrée) : libellé en gras de sa couleur.
                          Text(
                            c.label,
                            style: c.selected ? boldTextStyle(size: 12, color: c.color) : secondaryTextStyle(size: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Carte blanche qui regroupe des lignes (commandes), séparées par un trait.
class _GroupedList extends StatelessWidget {
  final List<Widget> children;
  const _GroupedList({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 66, endIndent: 14),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: boldTextStyle(size: 17, color: _headerDark));
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
    return InkWell(
      onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '', distanceKm: distanceKm).launch(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: _brandGold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.assignment_late_rounded, color: _brandGold, size: 20),
            ),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.service?.name ?? 'Service', style: boldTextStyle(size: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  3.height,
                  Text(
                    [
                      _formatDate(order.serviceDate, immediate: order.isImmediate),
                      if (distanceKm != null) '${distanceKm!.toStringAsFixed(1)} km',
                    ].where((t) => t.isNotEmpty).join(' · '),
                    style: secondaryTextStyle(size: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            8.width,
            const Icon(Icons.chevron_right_rounded, color: _brandGold),
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
  /// Action du moment (ex. « Confirmer », « Commencer ») : petit bouton doré.
  final String? actionLabel;
  final VoidCallback? onAction;
  const _RecentOrderTile({required this.order, this.actionLabel, this.onAction});

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

  /// Statut vu par l'ouvrier, en court.
  String _statusLabel(String? s) {
    switch (s) {
      case 'PENDING':                      return 'En attente';
      case 'ASSIGNED':                     return 'À confirmer';
      case 'ACCEPTED':                     return 'Acceptée';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'Paiement en attente';
      case 'IN_PROGRESS':                  return 'En cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'Paiement en attente';
      case 'COMPLETED':                    return 'Terminée';
      case 'CANCELLED':                    return 'Annulée';
      case 'REJECTED':                     return 'Annulée';
      default:                             return s ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(order.status);
    final client = order.client?.fullName ?? '';
    return InkWell(
      onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '').launch(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: _brandGold.withValues(alpha: 0.1),
                image: order.service?.imageUrl != null
                    ? DecorationImage(image: CachedNetworkImageProvider(order.service!.imageUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: order.service?.imageUrl == null ? const Icon(Icons.handyman, color: _brandGold, size: 20) : null,
            ),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.service?.name ?? 'Service', style: boldTextStyle(size: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  3.height,
                  Text(
                    [client, _formatDate(order.serviceDate)].where((t) => t.isNotEmpty).join(' · '),
                    style: secondaryTextStyle(size: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    8.height,
                    GestureDetector(
                      onTap: onAction,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: _brandGold, borderRadius: BorderRadius.circular(20)),
                        child: Text(actionLabel!, style: boldTextStyle(size: 13, color: Colors.white)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            8.width,
            // Statut : point de couleur + libellé court.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                5.width,
                Text(_statusLabel(order.status), style: boldTextStyle(size: 12, color: color)),
              ],
            ),
            4.width,
            const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
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

  // ── Répartition entre les onglets ───────────────────────────────────────
  bool _isProposed(MisonOrder o) => o.isPending && o.artisan == null && !dismissedProposedOrders().contains(o.id);
  bool _isFinished(MisonOrder o) => o.isCompleted || o.isCancelled || o.isRejected;
  bool _isOngoing(MisonOrder o) => o.artisan != null && !_isFinished(o);

  /// Missions : les commandes proposées d'abord, puis ses missions, de la plus
  /// proche à la plus lointaine.
  int _missionOrder(MisonOrder a, MisonOrder b) {
    final pa = _isProposed(a) ? 0 : 1;
    final pb = _isProposed(b) ? 0 : 1;
    if (pa != pb) return pa - pb;
    final da = DateTime.tryParse(a.serviceDate ?? '') ?? DateTime(2100);
    final db = DateTime.tryParse(b.serviceDate ?? '') ?? DateTime(2100);
    return pa == 0 ? db.compareTo(da) : da.compareTo(db);
  }

  /// Onglet Missions : carte « Nouvelle commande » pour une commande proposée,
  /// sinon sa mission dans une carte (comme les lignes de l'historique).
  Widget _buildMissionCard(MisonOrder order) {
    if (_isProposed(order) || (order.isPending && order.artisan == null)) return _buildCard(order);
    return _GroupedList(children: [_buildCard(order)]);
  }

  Widget _buildCard(MisonOrder order) {
    final distanceKm = _distanceTo(order);
    // Commande proposée : carte « Nouvelle commande » (bordure dorée, Refuser / Accepter).
    if (order.isPending && order.artisan == null) {
      return _NewOrderCard(
        order: order,
        distanceKm: distanceKm,
        onAccept: () => _confirmAction(
          title: order.isPendingDirectRequest ? 'Accepter la demande' : 'Accepter la commande',
          subtitle: order.isPendingDirectRequest
              ? 'Ce client vous a choisi. Acceptez-vous sa demande ?'
              : "Confirmez-vous l'acceptation de cette commande ?",
          action: () => artisanAcceptOrder(order.id!),
          icon: Icons.assignment_turned_in_outlined,
          confirmLabel: "Oui, j'accepte",
        ),
        onRefuse: order.isPendingDirectRequest
            ? () => _confirmAction(
                  title: 'Refuser la demande',
                  subtitle: "Le client sera prévenu et sa demande sera proposée à d'autres prestataires.",
                  action: () async {
                    await cancelMisonOrder(order.id!);
                    return MisonActionResponse(message: 'Demande refusée');
                  },
                  icon: Icons.event_busy_rounded,
                  confirmLabel: 'Oui, refuser',
                  danger: true,
                )
            : () async {
                await dismissProposedOrder(order.id ?? '');
                _reload();
              },
      );
    }
    // Ses commandes : ligne comme « Commandes récentes » de l'accueil ; seule
    // l'action du moment reste sur la ligne (le reste est dans le détail).
    if (order.artisan != null) {
      if (order.needsArtisanConfirmation) {
        return _RecentOrderTile(
          order: order,
          actionLabel: 'Confirmer',
          onAction: () => _confirmAction(
            title: 'Confirmer la commande',
            subtitle: 'Cette commande vous a été affectée par MISON. La confirmez-vous ?',
            action: () => artisanAcceptOrder(order.id!),
            icon: Icons.assignment_turned_in_outlined,
            confirmLabel: 'Oui, je confirme',
          ),
        );
      }
      if (order.hasArrived) {
        return _RecentOrderTile(
          order: order,
          actionLabel: 'Commencer',
          onAction: () async {
            if (await showMisonStartPrestationSheet(context, orderId: order.id!)) _reload();
          },
        );
      }
      return _RecentOrderTile(order: order);
    }
    return GestureDetector(
      onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '', distanceKm: distanceKm).launch(context),
      child: _ArtisanOrderCard(
        order: order,
        distanceKm: distanceKm,
        onApprove: ((order.isPending && order.artisan == null) ||
                order.needsArtisanConfirmation)
            ? () => _confirmAction(
                  title: order.isPendingDirectRequest
                      ? 'Accepter la demande'
                      : order.needsArtisanConfirmation
                          ? 'Confirmer la commande'
                          : 'Accepter la commande',
                  subtitle: order.isPendingDirectRequest
                      ? 'Ce client vous a choisi. Acceptez-vous sa demande ?'
                      : order.needsArtisanConfirmation
                          ? 'Cette commande vous a été affectée par MISON. La confirmez-vous ?'
                          : 'Confirmez-vous l\'acceptation de cette commande ?',
                  action: () => artisanAcceptOrder(order.id!),
                  icon: Icons.assignment_turned_in_outlined,
                  confirmLabel: order.needsArtisanConfirmation && !order.isPendingDirectRequest
                      ? 'Oui, je confirme'
                      : "Oui, j'accepte",
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
        onRelease: order.isPendingDirectRequest
            ? () => _confirmAction(
                  title: 'Refuser la demande',
                  subtitle: 'Le client sera prévenu et sa demande sera proposée à d\'autres prestataires.',
                  action: () async {
                    await cancelMisonOrder(order.id!);
                    return MisonActionResponse(message: 'Demande refusée');
                  },
                  icon: Icons.event_busy_rounded,
                  confirmLabel: 'Oui, refuser',
                  danger: true,
                )
            : order.canReleaseByArtisan
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
            Tab(text: 'Missions'),
            Tab(text: 'Historique'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              // ── Onglet « Missions » : commandes proposées, puis ses missions en
              //    cours et à venir (réservé directement, en attente de paiement…)
              _OrderTab(
                key: ValueKey('pending_$_key'),
                future: _allFuture,
                filter: (o) => _isProposed(o) || _isOngoing(o),
                sort: _missionOrder,
                tabLabel: 'Missions',
                buildCard: _buildMissionCard,
                onReload: _reload,
              ),
              // ── Onglet « Historique » : ses commandes terminées ou annulées
              _OrderTab(
                key: ValueKey('missions_$_key'),
                future: _allFuture,
                filter: (o) => o.artisan != null && _isFinished(o),
                tabLabel: 'Historique',
                buildCard: _buildCard,
                onReload: _reload,
                grouped: true,
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
  /// Lignes regroupées dans une carte, comme « Commandes récentes » de l'accueil.
  final bool grouped;
  /// Ordre d'affichage (sinon celui du serveur).
  final int Function(MisonOrder, MisonOrder)? sort;

  const _OrderTab({
    Key? key,
    required this.future,
    required this.filter,
    required this.tabLabel,
    required this.buildCard,
    required this.onReload,
    this.grouped = false,
    this.sort,
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
        if (widget.sort != null) filtered.sort(widget.sort);
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
              : widget.grouped
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [_GroupedList(children: [for (final o in filtered) widget.buildCard(o)])],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => 12.height,
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
                        order.needsArtisanConfirmation && !order.isPendingDirectRequest ? 'Confirmer' : 'Accepter',
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
                      child: Text(
                        order.isPendingDirectRequest ? 'Refuser' : 'Se désister',
                        style: boldTextStyle(color: rejected, size: 14),
                      ),
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

