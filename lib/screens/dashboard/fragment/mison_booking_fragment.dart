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

/// Fragment pour afficher la liste des commandes Mison
/// Utilise getMisonOrders() pour récupérer les données de l'API
class MisonBookingFragment extends StatefulWidget {
  const MisonBookingFragment({Key? key}) : super(key: key);

  @override
  State<MisonBookingFragment> createState() => _MisonBookingFragmentState();
}

class _MisonBookingFragmentState extends State<MisonBookingFragment> {
  late Future<MisonOrderResponse> future;
  String? selectedStatus;
  UniqueKey _futureKey = UniqueKey();

  final List<Map<String, String>> statusFilters = [
    {'value': '', 'label': 'Tous'},
    {'value': 'PENDING', 'label': 'En attente'},
    {'value': 'ASSIGNED', 'label': 'Assigné'},
    {'value': 'ACCEPTED', 'label': 'Accepté'},
    {'value': 'IN_PROGRESS', 'label': 'En cours'},
    {'value': 'COMPLETED', 'label': 'Terminé'},
    {'value': 'CANCELLED', 'label': 'Annulé'},
  ];

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() {
    future = getMisonOrders(status: selectedStatus);
    _futureKey = UniqueKey();
  }

  void _showCancelDialog(BuildContext context, MisonOrder order) {
    showConfirmDialogCustom(
      context,
      title: 'Annuler la commande',
      subTitle: 'Êtes-vous sûr de vouloir annuler cette commande ?',
      positiveText: 'Oui, annuler',
      negativeText: 'Non',
      dialogType: DialogType.DELETE,
      onAccept: (_) async {
        appStore.setLoading(true);
        // TODO: Call API to cancel order
        // await cancelMisonOrder(order.id ?? '');
        toast('Commande annulée');
        appStore.setLoading(false);
        init();
        setState(() {});
      },
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
              selectedStatus = value.isEmpty ? null : value;
              init();
              setState(() {});
            },
            itemBuilder: (context) => statusFilters.map((filter) {
              return PopupMenuItem<String>(
                value: filter['value'],
                child: Row(
                  children: [
                    if (selectedStatus == filter['value'] || 
                        (selectedStatus == null && filter['value'] == ''))
                      Icon(Icons.check, color: primaryColor, size: 18),
                    if (!(selectedStatus == filter['value'] || 
                        (selectedStatus == null && filter['value'] == '')))
                      const SizedBox(width: 18),
                    8.width,
                    Text(filter['label']!),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          const MisonServiceSelectionScreen().launch(context);
        },
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Nouvelle Demande', style: boldTextStyle(color: Colors.white, size: 14)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Stack(
        children: [
          SnapHelperWidget<MisonOrderResponse>(
            key: _futureKey,
            future: future,
            loadingWidget: const Center(child: CircularProgressIndicator()),
            errorBuilder: (error) {
              return NoDataWidget(
                title: error,
                imageWidget: const ErrorStateWidget(),
                retryText: language.reload,
                onRetry: () {
                  init();
                  setState(() {});
                },
              );
            },
            onSuccess: (response) {
              final orders = response.data ?? [];

              if (orders.isEmpty) {
                return NoDataWidget(
                  title: 'Aucune commande',
                  subTitle: 'Vous n\'avez pas encore de commande',
                  imageWidget: const EmptyStateWidget(),
                );
              }

              return AnimatedListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                itemCount: orders.length,
                shrinkWrap: true,
                listAnimationType: ListAnimationType.FadeIn,
                fadeInConfiguration: FadeInConfiguration(duration: 2.seconds),
                itemBuilder: (_, index) {
                  final order = orders[index];
                  return GestureDetector(
                    onTap: () {
                      MisonOrderDetailScreen(orderId: order.id ?? '').launch(context);
                    },
                    child: MisonOrderItemComponent(
                      order: order,
                      onCancel: () => _showCancelDialog(context, order),
                    ),
                  );
                },
                onSwipeRefresh: () async {
                  init();
                  setState(() {});
                  return await 1.seconds.delay;
                },
              );
            },
          ),
          Observer(builder: (_) => LoaderWidget().visible(appStore.isLoading)),
        ],
      ),
    );
  }
}

/// Widget pour afficher un item de commande dans la liste
class MisonOrderItemComponent extends StatelessWidget {
  final MisonOrder order;
  final VoidCallback? onCancel;

  const MisonOrderItemComponent({Key? key, required this.order, this.onCancel})
      : super(key: key);

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd MMM, yyyy', 'fr_FR').format(date);
    } catch (e) {
      return isoDate;
    }
  }

  String _formatTime(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('HH:mm').format(date);
    } catch (e) {
      return '';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'PENDING':
        return pending;
      case 'ASSIGNED':
        return assigned_booking;
      case 'ACCEPTED':
        return accept;
      case 'IN_PROGRESS':
        return in_progress;
      case 'COMPLETED':
        return completed;
      case 'CANCELLED':
        return cancelled;
      case 'REJECTED':
        return rejected;
      default:
        return defaultStatus;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'PENDING':
        return 'En attente';
      case 'ASSIGNED':
        return 'Assigné';
      case 'ACCEPTED':
        return 'Accepté';
      case 'IN_PROGRESS':
        return 'En cours';
      case 'COMPLETED':
        return 'Terminé';
      case 'CANCELLED':
        return 'Annulé';
      case 'REJECTED':
        return 'Refusé';
      default:
        return status ?? 'Inconnu';
    }
  }

  String _getPaymentStatusLabel(String? status) {
    switch (status?.toUpperCase()) {
      case 'PAID':
        return 'Payé';
      case 'PENDING':
        return 'En attente';
      case 'REFUNDED':
        return 'Remboursé';
      default:
        return status ?? 'En attente';
    }
  }

  Color _getPaymentStatusColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'PAID':
        return completed;
      case 'PENDING':
        return const Color.fromARGB(255, 243, 31, 31);
      case 'REFUNDED':
        return Colors.orange;
      default:
        return const Color.fromARGB(255, 243, 31, 31);
    }
  }

  bool _canCancel() {
    return order.status == 'PENDING' || order.status == 'ASSIGNED';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header "Votre Commande"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                Text('Votre Commande', style: boldTextStyle(size: 14)),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 14, color: Color(0xFF888888)),
                  ),
                ),
              ],
            ),
          ),

          // Service info row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Service image
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor.withOpacity(0.1),
                    border:
                        Border.all(color: const Color(0xFFF0E8E0), width: 2),
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
                // Service name and date/time
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
                              size: 13, color: const Color(0xFF888888)),
                          5.width,
                          Text(
                            _formatDate(order.serviceDate),
                            style: secondaryTextStyle(size: 12),
                          ),
                          14.width,
                          Icon(Icons.access_time,
                              size: 13, color: const Color(0xFF888888)),
                          5.width,
                          Text(
                            _formatTime(order.serviceDate),
                            style: secondaryTextStyle(size: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Status section
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                // Booking status row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Statut commande:',
                        style: secondaryTextStyle(size: 13)),
                    Text(
                      _getStatusLabel(order.status),
                      style: boldTextStyle(
                        size: 13,
                        color: _getStatusColor(order.status),
                      ),
                    ),
                  ],
                ),
                10.height,
                // Payment status row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Statut paiement:',
                        style: secondaryTextStyle(size: 13)),
                    Text(
                      _getPaymentStatusLabel(order.paymentStatus),
                      style: boldTextStyle(
                        size: 13,
                        color: _getPaymentStatusColor(order.paymentStatus),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Cancel button
          if (_canCancel()) ...[
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
