import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_service_selection_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_worker_request_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../component/empty_error_state_widget.dart';

class MisonBookingFragment extends StatefulWidget {
  const MisonBookingFragment({Key? key}) : super(key: key);

  @override
  State<MisonBookingFragment> createState() => _MisonBookingFragmentState();
}

class _MisonBookingFragmentState extends State<MisonBookingFragment>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showNewRequestSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            16.height,
            Text('Nouvelle demande', style: boldTextStyle(size: 18)),
            8.height,
            Text('Choisissez le type de demande',
                style: secondaryTextStyle()),
            24.height,
            _RequestTypeCard(
              icon: Icons.handshake_outlined,
              title: 'Mise en relation',
              subtitle: 'Trouvez un artisan qualifié selon votre besoin',
              onTap: () {
                finish(context);
                const MisonServiceSelectionScreen().launch(context);
              },
            ),
            16.height,
            _RequestTypeCard(
              icon: Icons.engineering_outlined,
              title: 'Demande d\'ouvrier',
              subtitle: 'Besoin de main d\'œuvre directe pour vos travaux',
              onTap: () {
                finish(context);
                const MisonWorkerRequestScreen().launch(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mes Commandes',
            style: boldTextStyle(color: Colors.white, size: 18)),
        backgroundColor: context.primaryColor,
        elevation: 3,
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: boldTextStyle(size: 13, color: Colors.white),
          unselectedLabelStyle:
              primaryTextStyle(size: 13, color: Colors.white60),
          tabs: const [
            Tab(text: 'Mise en relation'),
            Tab(text: 'Demande d\'ouvrier'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewRequestSheet(context),
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Nouvelle Demande',
            style: boldTextStyle(color: Colors.white, size: 14)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: const [
              _MiseEnRelationTab(),
              _DemandeOuvrierTab(),
            ],
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
// Onglet 1 : Mise en relation (GET /api/orders)
// ─────────────────────────────────────────────────────────────────────────────

class _MiseEnRelationTab extends StatefulWidget {
  const _MiseEnRelationTab();

  @override
  State<_MiseEnRelationTab> createState() => _MiseEnRelationTabState();
}

class _MiseEnRelationTabState extends State<_MiseEnRelationTab>
    with AutomaticKeepAliveClientMixin {
  late Future<MisonOrderResponse> _future;
  String? _selectedStatus;
  UniqueKey _key = UniqueKey();

  final List<Map<String, String>> _filters = const [
    {'value': '', 'label': 'Tous'},
    {'value': 'PENDING', 'label': 'En attente'},
    {'value': 'ASSIGNED', 'label': 'Assigné'},
    {'value': 'ACCEPTED', 'label': 'Accepté'},
    {'value': 'IN_PROGRESS', 'label': 'En cours'},
    {'value': 'COMPLETED', 'label': 'Terminé'},
    {'value': 'CANCELLED', 'label': 'Annulé'},
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = getMisonOrders(status: _selectedStatus);
    _key = UniqueKey();
  }

  void _showCancelDialog(MisonOrder order) {
    showConfirmDialogCustom(
      context,
      title: 'Annuler la commande',
      subTitle: 'Êtes-vous sûr de vouloir annuler cette commande ?',
      positiveText: 'Oui, annuler',
      negativeText: 'Non',
      dialogType: DialogType.DELETE,
      onAccept: (_) async {
        toast('Commande annulée');
        setState(() => _load());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Filtre par statut
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: _filters.map((f) {
              final isSelected = _selectedStatus == f['value'] ||
                  (_selectedStatus == null && f['value'] == '');
              return GestureDetector(
                onTap: () {
                  _selectedStatus =
                      f['value']!.isEmpty ? null : f['value'];
                  setState(() => _load());
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryColor
                        : primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    f['label']!,
                    style: boldTextStyle(
                      size: 12,
                      color: isSelected ? Colors.white : primaryColor,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: SnapHelperWidget<MisonOrderResponse>(
            key: _key,
            future: _future,
            loadingWidget:
                const Center(child: CircularProgressIndicator()),
            errorBuilder: (error) => NoDataWidget(
              title: error,
              imageWidget: const ErrorStateWidget(),
              retryText: language.reload,
              onRetry: () => setState(() => _load()),
            ),
            onSuccess: (response) {
              final orders = response.data ?? [];
              if (orders.isEmpty) {
                return NoDataWidget(
                  title: 'Aucune commande',
                  subTitle:
                      'Vous n\'avez pas encore de commande de mise en relation',
                  imageWidget: const EmptyStateWidget(),
                );
              }
              return AnimatedListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(
                    left: 16, right: 16, top: 8, bottom: 80),
                itemCount: orders.length,
                shrinkWrap: true,
                listAnimationType: ListAnimationType.FadeIn,
                fadeInConfiguration:
                    FadeInConfiguration(duration: 2.seconds),
                itemBuilder: (_, i) {
                  final order = orders[i];
                  return GestureDetector(
                    onTap: () => MisonOrderDetailScreen(
                            orderId: order.id ?? '')
                        .launch(context),
                    child: MisonOrderItemComponent(
                      order: order,
                      onCancel: () => _showCancelDialog(order),
                    ),
                  );
                },
                onSwipeRefresh: () async {
                  setState(() => _load());
                  await 1.seconds.delay;
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet 2 : Demande d'ouvrier (GET /api/worker-requests)
// ─────────────────────────────────────────────────────────────────────────────

class _DemandeOuvrierTab extends StatefulWidget {
  const _DemandeOuvrierTab();

  @override
  State<_DemandeOuvrierTab> createState() => _DemandeOuvrierTabState();
}

class _DemandeOuvrierTabState extends State<_DemandeOuvrierTab>
    with AutomaticKeepAliveClientMixin {
  late Future<MisonWorkerRequestResponse> _future;
  UniqueKey _key = UniqueKey();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = getWorkerRequests();
    _key = UniqueKey();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SnapHelperWidget<MisonWorkerRequestResponse>(
      key: _key,
      future: _future,
      loadingWidget: const Center(child: CircularProgressIndicator()),
      errorBuilder: (error) => NoDataWidget(
        title: error,
        imageWidget: const ErrorStateWidget(),
        retryText: language.reload,
        onRetry: () => setState(() => _load()),
      ),
      onSuccess: (response) {
        final requests = response.data ?? [];
        if (requests.isEmpty) {
          return NoDataWidget(
            title: 'Aucune demande',
            subTitle:
                'Vous n\'avez pas encore de demande d\'ouvrier',
            imageWidget: const EmptyStateWidget(),
          );
        }
        return AnimatedListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(
              left: 16, right: 16, top: 16, bottom: 80),
          itemCount: requests.length,
          shrinkWrap: true,
          listAnimationType: ListAnimationType.FadeIn,
          fadeInConfiguration:
              FadeInConfiguration(duration: 2.seconds),
          itemBuilder: (_, i) {
            return _WorkerRequestCard(request: requests[i]);
          },
          onSwipeRefresh: () async {
            setState(() => _load());
            await 1.seconds.delay;
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card demande d'ouvrier
// ─────────────────────────────────────────────────────────────────────────────

class _WorkerRequestCard extends StatelessWidget {
  final MisonWorkerRequest request;

  const _WorkerRequestCard({required this.request});

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      return DateFormat('dd MMM yyyy', 'fr_FR')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '—';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '—';
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'PENDING':   return pending;
      case 'ASSIGNED':  return assigned_booking;
      case 'COMPLETED': return completed;
      case 'CANCELLED': return cancelled;
      default:          return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'PENDING':   return 'En attente';
      case 'ASSIGNED':  return 'Assigné';
      case 'COMPLETED': return 'Terminé';
      case 'CANCELLED': return 'Annulé';
      default:          return s ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
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
              color: primaryColor.withValues(alpha: 0.06),
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
                    Icon(Icons.engineering_outlined,
                        size: 16, color: primaryColor),
                    6.width,
                    Text('Demande d\'ouvrier',
                        style: boldTextStyle(
                            size: 14, color: primaryColor)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(request.status)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(request.status),
                    style: boldTextStyle(
                        size: 12,
                        color: _statusColor(request.status)),
                  ),
                ),
              ],
            ),
          ),

          // Contenu
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Service + nb ouvriers
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.handyman,
                          color: primaryColor, size: 22),
                    ),
                    12.width,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.service?.name ?? 'Service',
                            style: boldTextStyle(size: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          4.height,
                          Row(
                            children: [
                              Icon(Icons.people_outline,
                                  size: 13, color: Colors.grey),
                              4.width,
                              Text(
                                '${request.workerCount ?? 1} ouvrier(s)',
                                style: secondaryTextStyle(size: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                12.height,

                // Description
                if (request.description != null &&
                    request.description!.isNotEmpty) ...[
                  Text(
                    request.description!,
                    style: secondaryTextStyle(size: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  10.height,
                ],

                // Date / heure / adresse
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _InfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: _formatDate(request.serviceDate)),
                      6.height,
                      _InfoRow(
                          icon: Icons.access_time,
                          label: _formatTime(request.serviceDate)),
                      if (request.serviceAddress != null &&
                          request.serviceAddress!.isNotEmpty) ...[
                        6.height,
                        _InfoRow(
                            icon: Icons.location_on_outlined,
                            label: request.serviceAddress!),
                      ],
                    ],
                  ),
                ),

                // Artisans assignés
                if (request.hasArtisans) ...[
                  12.height,
                  Row(
                    children: [
                      Icon(Icons.engineering_outlined,
                          size: 14, color: primaryColor),
                      6.width,
                      Text(
                        'Artisans assignés (${request.assignedArtisans!.length})',
                        style: boldTextStyle(size: 13, color: primaryColor),
                      ),
                    ],
                  ),
                  8.height,
                  ...request.assignedArtisans!.map((a) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: primaryColor.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  primaryColor.withValues(alpha: 0.15),
                              child: Text(
                                (a.firstName?.isNotEmpty == true
                                        ? a.firstName![0]
                                        : '?')
                                    .toUpperCase(),
                                style: boldTextStyle(
                                    size: 14, color: primaryColor),
                              ),
                            ),
                            12.width,
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.fullName,
                                    style: boldTextStyle(size: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (a.email != null &&
                                      a.email!.isNotEmpty) ...[
                                    2.height,
                                    Text(
                                      a.email!,
                                      style: secondaryTextStyle(size: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(Icons.check_circle,
                                size: 16, color: completed),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.grey),
        6.width,
        Expanded(
          child: Text(label,
              style: secondaryTextStyle(size: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card mise en relation (existante)
// ─────────────────────────────────────────────────────────────────────────────

class MisonOrderItemComponent extends StatelessWidget {
  final MisonOrder order;
  final VoidCallback? onCancel;

  const MisonOrderItemComponent(
      {Key? key, required this.order, this.onCancel})
      : super(key: key);

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      return DateFormat('dd MMM yyyy', 'fr_FR')
          .format(DateTime.parse(isoDate).toLocal());
    } catch (_) {
      return isoDate;
    }
  }

  String _formatTime(String? isoDate) {
    if (isoDate == null) return '';
    try {
      return DateFormat('HH:mm')
          .format(DateTime.parse(isoDate).toLocal());
    } catch (_) {
      return '';
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'PENDING':    return pending;
      case 'ASSIGNED':   return assigned_booking;
      case 'ACCEPTED':   return accept;
      case 'IN_PROGRESS':return in_progress;
      case 'COMPLETED':  return completed;
      case 'CANCELLED':  return cancelled;
      case 'REJECTED':   return rejected;
      default:           return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'PENDING':    return 'En attente';
      case 'ASSIGNED':   return 'Assigné';
      case 'ACCEPTED':   return 'Accepté';
      case 'IN_PROGRESS':return 'En cours';
      case 'COMPLETED':  return 'Terminé';
      case 'CANCELLED':  return 'Annulé';
      case 'REJECTED':   return 'Refusé';
      default:           return s ?? 'Inconnu';
    }
  }

  Color _paymentColor(String? s) {
    switch (s?.toUpperCase()) {
      case 'PAID':     return completed;
      case 'REFUNDED': return Colors.orange;
      default:         return rejected;
    }
  }

  String _paymentLabel(String? s) {
    switch (s?.toUpperCase()) {
      case 'PAID':     return 'Payé';
      case 'REFUNDED': return 'Remboursé';
      default:         return 'En attente';
    }
  }

  bool get _canCancel =>
      order.status == 'PENDING' || order.status == 'ASSIGNED';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
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
            decoration: const BoxDecoration(
              color: Color(0xFFF5F5F8),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mise en relation',
                    style: boldTextStyle(size: 14)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status)
                        .withValues(alpha: 0.15),
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

          // Service info
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor.withValues(alpha: 0.1),
                    border: Border.all(
                        color: const Color(0xFFF0E8E0), width: 2),
                    image: order.service?.imageUrl != null
                        ? DecorationImage(
                            image:
                                NetworkImage(order.service!.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: order.service?.imageUrl == null
                      ? Icon(Icons.handyman,
                          color: primaryColor, size: 24)
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
                      8.height,
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 13,
                              color: const Color(0xFF888888)),
                          5.width,
                          Text(_formatDate(order.serviceDate),
                              style: secondaryTextStyle(size: 12)),
                          14.width,
                          Icon(Icons.access_time,
                              size: 13,
                              color: const Color(0xFF888888)),
                          5.width,
                          Text(_formatTime(order.serviceDate),
                              style: secondaryTextStyle(size: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Statuts
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Statut commande:',
                        style: secondaryTextStyle(size: 13)),
                    Text(_statusLabel(order.status),
                        style: boldTextStyle(
                            size: 13,
                            color: _statusColor(order.status))),
                  ],
                ),
                10.height,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Statut paiement:',
                        style: secondaryTextStyle(size: 13)),
                    Text(_paymentLabel(order.paymentStatus),
                        style: boldTextStyle(
                            size: 13,
                            color: _paymentColor(order.paymentStatus))),
                  ],
                ),
              ],
            ),
          ),

          // Bouton annuler
          if (_canCancel) ...[
            14.height,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppButton(
                width: double.infinity,
                color: const Color.fromARGB(255, 248, 36, 32),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shapeBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                onTap: onCancel,
                child: Text('Annuler',
                    style:
                        boldTextStyle(color: Colors.white, size: 15)),
              ),
            ),
          ],
          18.height,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet : choix du type de demande
// ─────────────────────────────────────────────────────────────────────────────

class _RequestTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RequestTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: context.dividerColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: primaryColor, size: 24),
            ),
            16.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: boldTextStyle(size: 15)),
                  4.height,
                  Text(subtitle, style: secondaryTextStyle(size: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
