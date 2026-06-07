import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_service_selection_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../component/empty_error_state_widget.dart';
import '../../../utils/constant.dart';

class MisonBookingFragment extends StatelessWidget {
  const MisonBookingFragment({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mes Commandes',
            style: boldTextStyle(color: Colors.white, size: 18)),
        backgroundColor: context.primaryColor,
        elevation: 3,
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => const MisonServiceSelectionScreen().launch(context),
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Nouvelle Commande',
            style: boldTextStyle(color: Colors.white, size: 14)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Stack(
        children: [
          const _MiseEnRelationTab(),
          Observer(
              builder: (_) => LoaderWidget().visible(appStore.isLoading)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Liste des commandes mise en relation
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
    {'value': 'PENDING', 'label': 'Recherche artisan'},
    {'value': 'ACCEPTED', 'label': 'Artisan trouvé'},
    {'value': 'AWAITING_TRAVEL_PAYMENT', 'label': 'Paiement déplacement'},
    {'value': 'IN_PROGRESS', 'label': 'En intervention'},
    {'value': 'AWAITING_REALIZATION_PAYMENT', 'label': 'Paiement prestation'},
    {'value': 'COMPLETED', 'label': 'Terminé'},
    {'value': 'CANCELLED', 'label': 'Annulé'},
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    LiveStream().on(LIVESTREAM_ORDERS_LIST_REFRESH, (_) {
      if (mounted) setState(() => _load());
    });
  }

  @override
  void dispose() {
    LiveStream().dispose(LIVESTREAM_ORDERS_LIST_REFRESH);
    super.dispose();
  }

  void _load() {
    _future = getMisonOrders();
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
        try {
          await cancelMisonOrder(order.id ?? '');
          toast('Commande annulée');
          setState(() => _load());
        } catch (e) {
          toast('Erreur: ${e.toString()}');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Filtres par statut
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: _filters.map((f) {
              final isSelected = _selectedStatus == f['value'] ||
                  (_selectedStatus == null && f['value'] == '');
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedStatus =
                        f['value']!.isEmpty ? null : f['value'];
                  });
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
              final all = response.data ?? [];
              final orders = _selectedStatus == null
                  ? all
                  : all.where((o) => o.status == _selectedStatus).toList();

              if (orders.isEmpty) {
                return NoDataWidget(
                  title: _selectedStatus == null
                      ? 'Aucune commande'
                      : 'Aucune commande avec ce statut',
                  subTitle: _selectedStatus == null
                      ? 'Vous n\'avez pas encore de commande'
                      : null,
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
// Card commande mise en relation
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
      case 'PENDING':                      return pending;
      case 'ACCEPTED':                     return accept;
      case 'AWAITING_TRAVEL_PAYMENT':      return const Color(0xFFC99700);
      case 'IN_PROGRESS':                  return in_progress;
      case 'AWAITING_REALIZATION_PAYMENT': return const Color(0xFFE67E22);
      case 'COMPLETED':                    return completed;
      case 'CANCELLED':                    return cancelled;
      default:                             return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'PENDING':                      return 'Recherche d\'artisan';
      case 'ACCEPTED':                     return 'Artisan trouvé';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'En attente du paiement déplacement';
      case 'IN_PROGRESS':                  return 'Intervention en cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'En attente du paiement prestation';
      case 'COMPLETED':                    return 'Prestation terminée';
      case 'CANCELLED':                    return 'Commande annulée';
      default:                             return s ?? 'Inconnu';
    }
  }

  bool get _canCancel => order.status == 'PENDING';

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
                Text('Mise en relation', style: boldTextStyle(size: 14)),
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
                            image: NetworkImage(order.service!.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: order.service?.imageUrl == null
                      ? Icon(Icons.handyman, color: primaryColor, size: 24)
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: context.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Statut:', style: secondaryTextStyle(size: 13)),
                    Text(_statusLabel(order.status),
                        style: boldTextStyle(size: 13, color: _statusColor(order.status))),
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
                    style: boldTextStyle(color: Colors.white, size: 15)),
              ),
            ),
          ],
          18.height,
        ],
      ),
    );
  }
}
