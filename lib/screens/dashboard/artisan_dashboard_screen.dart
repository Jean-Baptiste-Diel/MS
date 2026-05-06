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
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../component/empty_error_state_widget.dart';

class ArtisanDashboardScreen extends StatefulWidget {
  const ArtisanDashboardScreen({Key? key}) : super(key: key);

  @override
  State<ArtisanDashboardScreen> createState() => _ArtisanDashboardScreenState();
}

class _ArtisanDashboardScreenState extends State<ArtisanDashboardScreen> {
  int _currentIndex = 0;

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
        body: IndexedStack(
          index: _currentIndex,
          children: _tabs,
        ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: context.scaffoldBackgroundColor,
            indicatorColor: context.primaryColor.withValues(alpha: 0.1),
            labelTextStyle: WidgetStateProperty.all(primaryTextStyle(size: 12)),
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex == 2 ? 3 : _currentIndex,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.dashboard_outlined, color: Colors.grey),
                selectedIcon: Icon(Icons.dashboard_rounded, color: context.primaryColor),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: ic_ticket.iconImage(color: appTextSecondaryColor),
                selectedIcon: ic_ticket.iconImage(color: context.primaryColor),
                label: 'Commandes',
              ),
              NavigationDestination(
                icon: ic_chat.iconImage(color: appTextSecondaryColor),
                selectedIcon: ic_chat.iconImage(color: context.primaryColor),
                label: 'Support',
              ),
              NavigationDestination(
                icon: Observer(
                  builder: (_) => (appStore.isLoggedIn && appStore.userProfileImage.isNotEmpty)
                      ? CircleAvatar(radius: 13, backgroundImage: NetworkImage(appStore.userProfileImage))
                      : ic_profile2.iconImage(color: appTextSecondaryColor),
                ),
                selectedIcon: Observer(
                  builder: (_) => (appStore.isLoggedIn && appStore.userProfileImage.isNotEmpty)
                      ? CircleAvatar(radius: 13, backgroundImage: NetworkImage(appStore.userProfileImage))
                      : ic_profile2.iconImage(color: context.primaryColor),
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

class _ArtisanHomeFragmentState extends State<ArtisanHomeFragment> {
  late Future<MisonOrderResponse> _future;
  UniqueKey _key = UniqueKey();
  bool _isAvailable = true;
  Position? _artisanPosition;

  @override
  void initState() {
    super.initState();
    _load();
    _restoreBadge();
    _fetchPosition();
    LiveStream().on(LIVESTREAM_ARTISAN_HOME_REFRESH, (_) {
      if (mounted) setState(() => _load());
    });
  }

  @override
  void dispose() {
    LiveStream().dispose(LIVESTREAM_ARTISAN_HOME_REFRESH);
    super.dispose();
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
      backgroundColor: context.scaffoldBackgroundColor,
      body: RefreshIndicator(
        color: primaryColor,
        onRefresh: () async { setState(() => _load()); },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              backgroundColor: primaryColor,
              automaticallyImplyLeading: false,
              actions: [
                ValueListenableBuilder<int>(
                  valueListenable: artisanNotifBadge,
                  builder: (_, count, __) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 26),
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
                              color: const Color(0xFFE53935),
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
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor, primaryColor.withValues(alpha: 0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                  child: Observer(
                    builder: (_) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$_greeting, ${appStore.userFirstName.isNotEmpty ? appStore.userFirstName : 'Artisan'} 👋',
                                    style: boldTextStyle(color: Colors.white, size: 19),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  4.height,
                                  Text(
                                    DateFormat('EEEE dd MMMM yyyy', 'fr_FR').format(DateTime.now()),
                                    style: secondaryTextStyle(color: Colors.white.withValues(alpha: 0.75), size: 12),
                                  ),
                                ],
                              ),
                            ),
                            12.width,
                            // Disponibilité toggle
                            GestureDetector(
                              onTap: () => setState(() => _isAvailable = !_isAvailable),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _isAvailable
                                      ? Colors.green.withValues(alpha: 0.25)
                                      : Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _isAvailable ? Colors.greenAccent : Colors.white38,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _isAvailable ? Colors.greenAccent : Colors.white54,
                                      ),
                                    ),
                                    6.width,
                                    Text(
                                      _isAvailable ? 'Disponible' : 'Indisponible',
                                      style: boldTextStyle(color: Colors.white, size: 11),
                                    ),
                                  ],
                                ),
                              ),
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
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorBuilder: (error) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: NoDataWidget(
                    title: error,
                    imageWidget: const ErrorStateWidget(),
                    retryText: language.reload,
                    onRetry: () => setState(() => _load()),
                  ),
                ),
                onSuccess: (response) {
                  final orders = response.data ?? [];
                  return _DashboardBody(orders: orders, artisanPosition: _artisanPosition);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final List<MisonOrder> orders;
  final Position? artisanPosition;
  const _DashboardBody({required this.orders, this.artisanPosition});

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
    final enCours   = missions.where((o) => o.isAccepted || o.isAwaitingTravelPayment || o.isInProgress || o.isAwaitingRealizationPayment).length;
    final terminees = missions.where((o) => o.isCompleted).length;
    final refusees  = missions.where((o) => o.isRejected).length;

    final recent = missions.take(5).toList();

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
              Row(children: [
                _StatCard(label: 'Total', value: total, color: primaryColor, icon: Icons.receipt_long_rounded),
                12.width,
                _StatCard(label: 'En cours', value: enCours, color: in_progress, icon: Icons.timelapse_rounded),
              ]),
              12.height,
              Row(children: [
                _StatCard(label: 'Terminées', value: terminees, color: completed, icon: Icons.check_circle_rounded),
                12.width,
                _StatCard(label: 'Refusées', value: refusees, color: rejected, icon: Icons.cancel_rounded),
              ]),
            ],
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
                    color: Colors.orange,
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

        // ── Dernières commandes
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
          child: _SectionTitle(title: 'Historique récent'),
        ),

        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: NoDataWidget(
              title: 'Aucune commande',
              subTitle: 'Aucune commande ne vous a été assignée pour le moment.',
              imageWidget: const EmptyStateWidget(),
            ),
          )
        else
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recent.length,
            separatorBuilder: (_, __) => 12.height,
            itemBuilder: (ctx, i) => _RecentOrderTile(order: recent[i]),
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

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try { return DateFormat('dd MMM · HH:mm', 'fr_FR').format(DateTime.parse(iso)); }
    catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '', distanceKm: distanceKm).launch(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.assignment_late_rounded, color: Colors.orange, size: 22),
            ),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.service?.name ?? 'Service',
                      style: boldTextStyle(size: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  4.height,
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: Colors.grey),
                      4.width,
                      Flexible(child: Text(order.client?.fullName ?? '',
                          style: secondaryTextStyle(size: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      8.width,
                      Icon(Icons.schedule, size: 12, color: Colors.grey),
                      4.width,
                      Flexible(child: Text(_formatDate(order.serviceDate),
                          style: secondaryTextStyle(size: 12),
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
                color: Colors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Voir', style: boldTextStyle(color: Colors.white, size: 11)),
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
  const _StatCard({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
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
                  Text(label, style: secondaryTextStyle(size: 12)),
                ],
              ),
            ),
          ],
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
      case 'ASSIGNED':                     return assigned_booking;
      case 'ACCEPTED':                     return accept;
      case 'AWAITING_TRAVEL_PAYMENT':      return const Color(0xFFC99700);
      case 'IN_PROGRESS':                  return in_progress;
      case 'AWAITING_REALIZATION_PAYMENT': return const Color(0xFFE67E22);
      case 'COMPLETED':                    return completed;
      case 'REJECTED':                     return rejected;
      default:                             return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'ASSIGNED':                     return 'Assignée';
      case 'ACCEPTED':                     return 'Acceptée';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'Frais déplacement';
      case 'IN_PROGRESS':                  return 'En cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'Frais réalisation';
      case 'COMPLETED':                    return 'Terminée';
      case 'REJECTED':                     return 'Refusée';
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
                color: primaryColor.withValues(alpha: 0.1),
                image: order.service?.imageUrl != null
                    ? DecorationImage(image: NetworkImage(order.service!.imageUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: order.service?.imageUrl == null
                  ? Icon(Icons.handyman, color: primaryColor, size: 20)
                  : null,
            ),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.service?.name ?? 'Service', style: boldTextStyle(size: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  4.height,
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: Colors.grey),
                      4.width,
                      Flexible(
                        child: Text(order.client?.fullName ?? '',
                            style: secondaryTextStyle(size: 12),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      8.width,
                      Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
                      4.width,
                      Flexible(
                        child: Text(_formatDate(order.serviceDate),
                            style: secondaryTextStyle(size: 12),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            12.width,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _statusColor(order.status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_statusLabel(order.status),
                  style: boldTextStyle(size: 11, color: _statusColor(order.status))),
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
    with SingleTickerProviderStateMixin {
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
      toast(res.message ?? 'Succès');
      _reload();
    } catch (e) {
      toast(e.toString());
    } finally {
      appStore.setLoading(false);
    }
  }

  void _confirmAction({
    required String title,
    required String subtitle,
    required Future<MisonActionResponse> Function() action,
  }) {
    showConfirmDialogCustom(
      context,
      title: title,
      subTitle: subtitle,
      positiveText: 'Confirmer',
      negativeText: 'Annuler',
      onAccept: (_) => _doAction(action),
    );
  }

  void _showFeeModal({
    required String title,
    required Future<MisonActionResponse> Function(num) apiCall,
  }) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeeBottomSheet(
        title: title,
        ctrl: ctrl,
        onConfirm: () {
          final amount = num.tryParse(ctrl.text.trim());
          if (amount == null || amount <= 0) { toast('Montant invalide'); return; }
          Navigator.pop(context);
          _doAction(() => apiCall(amount));
        },
      ),
    );
  }

  Widget _buildCard(MisonOrder order) {
    final distanceKm = (order.isPending && order.artisan == null) ? _distanceTo(order) : null;
    return GestureDetector(
      onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '', distanceKm: distanceKm).launch(context),
      child: _ArtisanOrderCard(
        order: order,
        distanceKm: distanceKm,
        onApprove: (order.isPending && order.artisan == null)
            ? () => _confirmAction(
                  title: 'Accepter la commande',
                  subtitle: 'Confirmez-vous l\'acceptation de cette commande ?',
                  action: () => artisanAcceptOrder(order.id!),
                )
            : null,
        onSetTravelFee: order.isAccepted
            ? () => _showFeeModal(
                  title: 'Frais de déplacement',
                  apiCall: (amount) => setTravelFee(order.id!, amount),
                )
            : null,
        onSetRealizationFee: order.isInProgress
            ? () => _showFeeModal(
                  title: 'Frais de réalisation',
                  apiCall: (amount) => setRealizationFee(order.id!, amount),
                )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.primaryColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text('Mes Commandes', style: boldTextStyle(color: Colors.white, size: 18)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: boldTextStyle(size: 14, color: Colors.white),
          unselectedLabelStyle: secondaryTextStyle(size: 13, color: Colors.white70),
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
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: NoDataWidget(
              title: snapshot.error.toString(),
              imageWidget: const ErrorStateWidget(),
              retryText: 'Réessayer',
              onRetry: widget.onReload,
            ),
          );
        }
        final all = snapshot.data?.data ?? [];
        final filtered = all.where(widget.filter).toList();
        return RefreshIndicator(
          color: primaryColor,
          onRefresh: () async => widget.onReload(),
          child: filtered.isEmpty
              ? CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      child: Center(
                        child: NoDataWidget(
                          title: 'Aucune commande',
                          subTitle: 'Aucune commande dans "${widget.tabLabel}" pour le moment.',
                          imageWidget: const EmptyStateWidget(),
                          retryText: 'Actualiser',
                          onRetry: widget.onReload,
                        ),
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
  final VoidCallback? onSetTravelFee;
  final VoidCallback? onSetRealizationFee;

  const _ArtisanOrderCard({
    required this.order,
    this.distanceKm,
    this.onApprove,
    this.onSetTravelFee,
    this.onSetRealizationFee,
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
      case 'ASSIGNED':                     return assigned_booking;
      case 'ACCEPTED':                     return accept;
      case 'AWAITING_TRAVEL_PAYMENT':      return const Color(0xFFC99700);
      case 'IN_PROGRESS':                  return in_progress;
      case 'AWAITING_REALIZATION_PAYMENT': return const Color(0xFFE67E22);
      case 'COMPLETED':                    return completed;
      case 'REJECTED':                     return rejected;
      default:                             return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'ASSIGNED':                     return 'Assignée';
      case 'ACCEPTED':                     return 'Acceptée';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'Frais déplacement';
      case 'IN_PROGRESS':                  return 'En cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'Frais réalisation';
      case 'COMPLETED':                    return 'Terminée';
      case 'REJECTED':                     return 'Refusée';
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
              color: context.primaryColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 16, color: context.primaryColor),
                    6.width,
                    Text(clientName, style: boldTextStyle(size: 14, color: context.primaryColor)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_statusLabel(order.status),
                      style: boldTextStyle(size: 12, color: _statusColor(order.status))),
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
                    color: primaryColor.withValues(alpha: 0.1),
                    image: order.service?.imageUrl != null
                        ? DecorationImage(image: NetworkImage(order.service!.imageUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: order.service?.imageUrl == null
                      ? Icon(Icons.handyman, color: primaryColor, size: 22)
                      : null,
                ),
                12.width,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.service?.name ?? 'Service', style: boldTextStyle(size: 15),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      6.height,
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
                          4.width,
                          Text(_formatDate(order.serviceDate), style: secondaryTextStyle(size: 12)),
                          12.width,
                          Icon(Icons.access_time, size: 12, color: Colors.grey),
                          4.width,
                          Text(_formatTime(order.serviceDate), style: secondaryTextStyle(size: 12)),
                        ],
                      ),
                      if (order.serviceAddress != null && order.serviceAddress!.isNotEmpty) ...[
                        4.height,
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 12, color: Colors.grey),
                            4.width,
                            Expanded(
                              child: Text(order.serviceAddress!, style: secondaryTextStyle(size: 12),
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

          // Distance badge (commandes à traiter uniquement)
          if (distanceKm != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.near_me_rounded, size: 14, color: Colors.orange),
                    6.width,
                    Text(
                      'Prestation demandée à ${distanceKm! < 1 ? '${(distanceKm! * 1000).round()} m' : '${distanceKm!.toStringAsFixed(1)} km'} de vous',
                      style: boldTextStyle(size: 12, color: Colors.orange),
                    ),
                  ],
                ),
              ),
            ),

          // Action buttons
          if (onApprove != null || onSetTravelFee != null || onSetRealizationFee != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  if (onApprove != null)
                    AppButton(
                      width: double.infinity,
                      color: accept,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: onApprove,
                      child: Text('Accepter', style: boldTextStyle(color: Colors.white, size: 14)),
                    ),
                  if (onSetTravelFee != null)
                    AppButton(
                      width: double.infinity,
                      color: const Color(0xFFC99700),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: onSetTravelFee,
                      child: Text('Définir frais de déplacement', style: boldTextStyle(color: Colors.white, size: 14)),
                    ),
                  if (onSetRealizationFee != null)
                    AppButton(
                      width: double.infinity,
                      color: completed,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: onSetRealizationFee,
                      child: Text('Définir frais de réalisation', style: boldTextStyle(color: Colors.white, size: 14)),
                    ),
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

class _FeeBottomSheet extends StatelessWidget {
  final String title;
  final TextEditingController ctrl;
  final VoidCallback onConfirm;

  const _FeeBottomSheet({
    required this.title,
    required this.ctrl,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          20.height,
          Text(title, style: boldTextStyle(size: 18)),
          20.height,
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: boldTextStyle(size: 16),
            decoration: InputDecoration(
              hintText: 'Montant en FCFA',
              hintStyle: secondaryTextStyle(size: 14),
              suffixText: 'FCFA',
              suffixStyle: secondaryTextStyle(size: 13),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.grey.withValues(alpha: 0.35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primaryColor, width: 1.5),
              ),
            ),
          ),
          20.height,
          AppButton(
            text: 'Confirmer',
            color: primaryColor,
            textColor: Colors.white,
            width: double.infinity,
            height: 50,
            shapeBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            onTap: onConfirm,
          ),
        ],
      ),
    );
  }
}
