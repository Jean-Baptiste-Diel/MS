import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/auth/change_password_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/fragment/profile_fragment.dart';
import 'package:booking_system_flutter/screens/support_chat/support_chat_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
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
    const ArtisanOrdersFragment(),
    ProfileFragment(),
  ];

  void _onDestinationSelected(int index) {
    if (index == 1) {
      const SupportChatScreen().launch(context);
      return;
    }
    if (index == 2) {
      ChangePasswordScreen().launch(context);
      return;
    }
    // index 0 → Commandes (_tabs[0]), index 3 → Profil (_tabs[1])
    setState(() => _currentIndex = index == 3 ? 1 : 0);
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
            selectedIndex: _currentIndex == 1 ? 3 : 0,
            destinations: [
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
                icon: const Icon(Icons.lock_outline, color: Colors.grey),
                selectedIcon:
                    Icon(Icons.lock_outline, color: context.primaryColor),
                label: 'Sécurité',
              ),
              NavigationDestination(
                icon: Observer(
                  builder: (_) => (appStore.isLoggedIn &&
                          appStore.userProfileImage.isNotEmpty)
                      ? CircleAvatar(
                          radius: 13,
                          backgroundImage:
                              NetworkImage(appStore.userProfileImage),
                        )
                      : ic_profile2.iconImage(color: appTextSecondaryColor),
                ),
                selectedIcon: Observer(
                  builder: (_) => (appStore.isLoggedIn &&
                          appStore.userProfileImage.isNotEmpty)
                      ? CircleAvatar(
                          radius: 13,
                          backgroundImage:
                              NetworkImage(appStore.userProfileImage),
                        )
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
// Fragment : liste des commandes de l'artisan
// ─────────────────────────────────────────────────────────────────────────────

class ArtisanOrdersFragment extends StatefulWidget {
  const ArtisanOrdersFragment({Key? key}) : super(key: key);

  @override
  State<ArtisanOrdersFragment> createState() => _ArtisanOrdersFragmentState();
}

class _ArtisanOrdersFragmentState extends State<ArtisanOrdersFragment> {
  late Future<MisonOrderResponse> _future;
  String? _selectedStatus;
  UniqueKey _key = UniqueKey();

  final List<Map<String, String>> _statusFilters = const [
    {'value': '', 'label': 'Toutes'},
    {'value': 'ASSIGNED', 'label': 'Assignées'},
    {'value': 'ACCEPTED', 'label': 'Acceptées'},
    {'value': 'IN_PROGRESS', 'label': 'En cours'},
    {'value': 'COMPLETED', 'label': 'Terminées'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = getMisonOrders(status: _selectedStatus);
    _key = UniqueKey();
  }

  void _reload() {
    setState(() => _load());
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarWidget(
        'Mes Commandes',
        textColor: Colors.white,
        showBack: false,
        textSize: 18,
        elevation: 3.0,
        color: context.primaryColor,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onSelected: (value) {
              _selectedStatus = value.isEmpty ? null : value;
              _reload();
            },
            itemBuilder: (_) => _statusFilters.map((f) {
              final isSelected = _selectedStatus == f['value'] ||
                  (_selectedStatus == null && f['value'] == '');
              return PopupMenuItem<String>(
                value: f['value'],
                child: Row(
                  children: [
                    isSelected
                        ? Icon(Icons.check, color: primaryColor, size: 18)
                        : const SizedBox(width: 18),
                    8.width,
                    Text(f['label']!),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      body: Stack(
        children: [
          SnapHelperWidget<MisonOrderResponse>(
            key: _key,
            future: _future,
            loadingWidget: const Center(child: CircularProgressIndicator()),
            errorBuilder: (error) => NoDataWidget(
              title: error,
              imageWidget: const ErrorStateWidget(),
              retryText: language.reload,
              onRetry: _reload,
            ),
            onSuccess: (response) {
              final orders = response.data ?? [];
              if (orders.isEmpty) {
                return NoDataWidget(
                  title: 'Aucune commande',
                  subTitle: 'Aucune commande ne vous a été assignée pour le moment.',
                  imageWidget: const EmptyStateWidget(),
                );
              }
              return AnimatedListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(
                    left: 16, right: 16, top: 16, bottom: 24),
                itemCount: orders.length,
                shrinkWrap: true,
                listAnimationType: ListAnimationType.FadeIn,
                fadeInConfiguration:
                    FadeInConfiguration(duration: 2.seconds),
                itemBuilder: (_, i) {
                  final order = orders[i];
                  return GestureDetector(
                    onTap: () => MisonOrderDetailScreen(orderId: order.id ?? '')
                        .launch(context),
                    child: _ArtisanOrderCard(
                      order: order,
                      onApprove: order.isAssigned
                          ? () => _confirmAction(
                                title: 'Accepter la commande',
                                subtitle:
                                    'Confirmez-vous l\'acceptation de cette commande ?',
                                action: () => artisanDecisionMisonOrder(
                                    order.id!, 'APPROVE'),
                              )
                          : null,
                      onReject: order.isAssigned
                          ? () => _confirmAction(
                                title: 'Refuser la commande',
                                subtitle:
                                    'Confirmez-vous le refus de cette commande ?',
                                action: () => artisanDecisionMisonOrder(
                                    order.id!, 'REJECT'),
                              )
                          : null,
                      onStart: order.isAccepted
                          ? () => _confirmAction(
                                title: 'Démarrer la commande',
                                subtitle:
                                    'Confirmez-vous le démarrage de cette commande ?',
                                action: () => artisanStartOrder(order.id!),
                              )
                          : null,
                      onComplete: order.isInProgress
                          ? () => _confirmAction(
                                title: 'Terminer la commande',
                                subtitle:
                                    'Confirmez-vous la fin de cette commande ?',
                                action: () => artisanCompleteOrder(order.id!),
                              )
                          : null,
                    ),
                  );
                },
                onSwipeRefresh: () async {
                  _reload();
                  await 1.seconds.delay;
                },
              );
            },
          ),
          Observer(
              builder: (_) =>
                  LoaderWidget().visible(appStore.isLoading)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card d'une commande pour l'artisan
// ─────────────────────────────────────────────────────────────────────────────

class _ArtisanOrderCard extends StatelessWidget {
  final MisonOrder order;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onStart;
  final VoidCallback? onComplete;

  const _ArtisanOrderCard({
    required this.order,
    this.onApprove,
    this.onReject,
    this.onStart,
    this.onComplete,
  });

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('dd MMM yyyy', 'fr_FR').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return '';
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'ASSIGNED':
        return assigned_booking;
      case 'ACCEPTED':
        return accept;
      case 'IN_PROGRESS':
        return in_progress;
      case 'COMPLETED':
        return completed;
      case 'REJECTED':
        return rejected;
      default:
        return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'ASSIGNED':
        return 'Assignée';
      case 'ACCEPTED':
        return 'Acceptée';
      case 'IN_PROGRESS':
        return 'En cours';
      case 'COMPLETED':
        return 'Terminée';
      case 'REJECTED':
        return 'Refusée';
      default:
        return s ?? '';
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
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                    Icon(Icons.person_outline,
                        size: 16, color: context.primaryColor),
                    6.width,
                    Text(clientName,
                        style: boldTextStyle(size: 14, color: context.primaryColor)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(order.status),
                    style: boldTextStyle(
                        size: 12, color: _statusColor(order.status)),
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
                    color: primaryColor.withValues(alpha: 0.1),
                    image: order.service?.imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(order.service!.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: order.service?.imageUrl == null
                      ? Icon(Icons.handyman,
                          color: primaryColor, size: 22)
                      : null,
                ),
                12.width,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.service?.name ?? 'Service',
                        style: boldTextStyle(size: 15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      6.height,
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 12, color: Colors.grey),
                          4.width,
                          Text(_formatDate(order.serviceDate),
                              style: secondaryTextStyle(size: 12)),
                          12.width,
                          Icon(Icons.access_time,
                              size: 12, color: Colors.grey),
                          4.width,
                          Text(_formatTime(order.serviceDate),
                              style: secondaryTextStyle(size: 12)),
                        ],
                      ),
                      if (order.serviceAddress != null &&
                          order.serviceAddress!.isNotEmpty) ...[
                        4.height,
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 12, color: Colors.grey),
                            4.width,
                            Expanded(
                              child: Text(
                                order.serviceAddress!,
                                style: secondaryTextStyle(size: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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

          // Action buttons
          if (onApprove != null || onReject != null || onStart != null || onComplete != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  // ASSIGNED: Accepter + Refuser
                  if (onApprove != null || onReject != null)
                    Row(
                      children: [
                        if (onReject != null)
                          Expanded(
                            child: AppButton(
                              color: rejected.withValues(alpha: 0.12),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shapeBorder: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              onTap: onReject,
                              child: Text('Refuser',
                                  style:
                                      boldTextStyle(color: rejected, size: 14)),
                            ),
                          ),
                        if (onReject != null && onApprove != null) 10.width,
                        if (onApprove != null)
                          Expanded(
                            child: AppButton(
                              color: accept,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shapeBorder: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              onTap: onApprove,
                              child: Text('Accepter',
                                  style: boldTextStyle(
                                      color: Colors.white, size: 14)),
                            ),
                          ),
                      ],
                    ),
                  // ACCEPTED: Démarrer
                  if (onStart != null)
                    AppButton(
                      width: double.infinity,
                      color: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shapeBorder: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onTap: onStart,
                      child: Text('Démarrer',
                          style: boldTextStyle(color: Colors.white, size: 15)),
                    ),
                  // IN_PROGRESS: Terminer
                  if (onComplete != null)
                    AppButton(
                      width: double.infinity,
                      color: completed,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shapeBorder: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onTap: onComplete,
                      child: Text('Terminer',
                          style: boldTextStyle(color: Colors.white, size: 15)),
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
