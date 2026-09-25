import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_search_service_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../component/app_empty_state.dart';
import '../../../utils/constant.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class MisonBookingFragment extends StatelessWidget {
  const MisonBookingFragment({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Logo centré + fond de la page, comme les pages prestataire
      appBar: const MisonAppBar(title: 'Mes Commandes'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => const MisonSearchServiceScreen().launch(context),
        backgroundColor: kMisonGold,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Nouvelle Commande',
            style: boldTextStyle(color: Colors.white, size: 14)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Stack(
        children: [
          const _MiseEnRelationTab(),
          Observer(
              builder: (_) => LoaderWidget(colors: const [kMisonDark, kMisonGold])
                  .visible(appStore.isLoading)),
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

  /// Nombre de filtres toujours visibles ; les autres s'affichent avec « + ».
  static const int _visibleFilterCount = 4;

  // Couleurs des filtres (style WhatsApp, version dorée)
  static const Color _chipBg = Color(0xFFE9EAEC);
  static const Color _chipText = kMisonDark;
  static const Color _chipSelectedBg = Color(0xFFF3E7C4);
  static const Color _chipSelectedText = Color(0xFF8A6A0F);
  bool _showAllFilters = false;

  final List<Map<String, String>> _filters = const [
    // « Tous » : sélectionné (en couleur) quand aucun statut n'est choisi
    {'value': '', 'label': 'Tous'},
    // Libellés courts pour que les 4 premiers tiennent sur une ligne
    {'value': 'PENDING', 'label': 'Recherche'},
    {'value': 'ACCEPTED', 'label': 'Trouvé'},
    {'value': 'IN_PROGRESS', 'label': 'En cours'},
    {'value': 'PAYMENT', 'label': 'Paiement'},
    {'value': 'COMPLETED', 'label': 'Terminé'},
    {'value': 'CANCELLED', 'label': 'Annulé'},
  ];

  /// Statuts de commande couverts par chaque filtre.
  static const Map<String, Set<String>> _filterStatuses = {
    'PENDING': {'PENDING', 'ASSIGNED'},
    'ACCEPTED': {'ACCEPTED'},
    'IN_PROGRESS': {'IN_PROGRESS'},
    'PAYMENT': {'AWAITING_TRAVEL_PAYMENT', 'AWAITING_REALIZATION_PAYMENT'},
    'COMPLETED': {'COMPLETED'},
    'CANCELLED': {'CANCELLED', 'REJECTED'},
  };

  bool _matchesFilter(MisonOrder o) {
    final status = (o.status ?? '').trim().toUpperCase();
    return _filterStatuses[_selectedStatus]?.contains(status) ?? false;
  }

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
          TopToast.show(message: 'Commande annulée');
          setState(() => _load());
        } catch (e) {
          TopToast.show(message: 'Erreur: ${e.toString()}', type: TopToastType.error);
        }
      },
    );
  }

  /// Filtres de la ligne principale. Si le filtre choisi fait partie des
  /// filtres cachés, il remplace le dernier de la ligne pour rester visible.
  List<Map<String, String>> get _visibleFilters {
    final first = _filters.take(_visibleFilterCount).toList();
    final selected = _filters.where((f) => f['value'] == _selectedStatus);
    if (selected.isEmpty || first.contains(selected.first)) return first;
    return [...first.take(_visibleFilterCount - 1), selected.first];
  }

  /// Filtres affichés en dessous avec « + » (tous ceux absents de la ligne).
  List<Map<String, String>> get _hiddenFilters {
    final visible = _visibleFilters;
    return _filters.where((f) => !visible.contains(f)).toList();
  }

  Widget _buildFilterChip(Map<String, String> f) {
    final isAll = f['value']!.isEmpty;
    final isSelected = isAll ? _selectedStatus == null : _selectedStatus == f['value'];
    return GestureDetector(
      onTap: () {
        setState(() {
          // « Tous » ou re-toucher le filtre actif = toutes les commandes
          _selectedStatus =
              (isAll || _selectedStatus == f['value']) ? null : f['value'];
        });
      },
      // Style WhatsApp : gris clair, doré clair quand sélectionné
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? _chipSelectedBg : _chipBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          f['label']!,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? _chipSelectedText : _chipText,
          ),
        ),
      ),
    );
  }

  Widget _buildMoreFiltersButton() {
    final expanded = _showAllFilters;
    return GestureDetector(
      onTap: () => setState(() => _showAllFilters = !_showAllFilters),
      // Bouton rond « + » style WhatsApp (« − » quand les filtres sont dépliés)
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: expanded ? _chipSelectedBg : _chipBg,
        ),
        child: Icon(
          expanded ? Icons.remove_rounded : Icons.add_rounded,
          size: 18,
          color: expanded ? _chipSelectedText : _chipText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Filtres par statut : 4 visibles + bouton « + » pour afficher le reste
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Une seule ligne : filtres réduits pour tenir + « + » fixe à droite
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          for (final f in _visibleFilters) ...[
                            _buildFilterChip(f),
                            6.width,
                          ],
                        ],
                      ),
                    ),
                  ),
                  _buildMoreFiltersButton(),
                ],
              ),
              // Filtres restants, dépliés en dessous
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _showAllFilters
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              _hiddenFilters.map(_buildFilterChip).toList(),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
        Expanded(
          child: SnapHelperWidget<MisonOrderResponse>(
            key: _key,
            future: _future,
            loadingWidget:
                const Center(child: CircularProgressIndicator()),
            errorBuilder: (error) => AppEmptyState(
              type: AppEmptyStateType.error,
              title: error,
              retryLabel: language.reload,
              onRetry: () => setState(() => _load()),
            ),
            onSuccess: (response) {
              final all = response.data ?? [];
              final orders = _selectedStatus == null
                  ? all
                  : all.where(_matchesFilter).toList();

              if (orders.isEmpty) {
                return AppEmptyState(
                  type: AppEmptyStateType.empty,
                  title: _selectedStatus == null
                      ? 'Aucune commande'
                      : 'Aucune commande avec ce statut',
                  subtitle: _selectedStatus == null
                      ? 'Vous n\'avez pas encore de commande'
                      : null,
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
    switch (s?.trim().toUpperCase()) {
      case 'PENDING':                      return pending;
      case 'ASSIGNED':                     return pending;
      case 'REJECTED':                     return cancelled;
      case 'ACCEPTED':                     return accept;
      case 'AWAITING_TRAVEL_PAYMENT':      return kMisonGold;
      case 'IN_PROGRESS':                  return in_progress;
      case 'AWAITING_REALIZATION_PAYMENT': return kMisonGold;
      case 'COMPLETED':                    return completed;
      case 'CANCELLED':                    return cancelled;
      default:                             return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s?.trim().toUpperCase()) {
      case 'PENDING':                      return 'Recherche d\'ouvrier';
      case 'ASSIGNED':                     return 'Recherche d\'ouvrier';
      case 'REJECTED':                     return 'Commande refusée';
      case 'ACCEPTED':                     return 'Ouvrier trouvé';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'En attente de paiement';
      case 'IN_PROGRESS':                  return 'Intervention en cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'En attente du paiement de la prestation';
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
              color: kMisonGold.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Mise en relation',
                      style: boldTextStyle(size: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                8.width,
                Flexible(
                  child: Container(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
                    color: kMisonGold.withValues(alpha: 0.1),
                    border: Border.all(
                        color: const Color(0xFFF0E8E0), width: 2),
                    image: order.service?.imageUrl != null
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(order.service!.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: order.service?.imageUrl == null
                      ? Icon(Icons.handyman, color: kMisonGold, size: 24)
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

          // Statuts + notation
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: context.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Statut:', style: secondaryTextStyle(size: 13)),
                    Text(_statusLabel(order.status),
                        style: boldTextStyle(size: 13, color: _statusColor(order.status))),
                  ],
                ),
                if (order.clientRating != null) ...[
                  10.height,
                  Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                  10.height,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: List.generate(5, (i) => Icon(
                          i < order.clientRating! ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: ratingBarColor,
                          size: 18,
                        )),
                      ),
                      if (order.clientReview != null && order.clientReview!.isNotEmpty)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(
                              order.clientReview!,
                              style: secondaryTextStyle(size: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
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
