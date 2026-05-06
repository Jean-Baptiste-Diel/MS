import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../component/empty_error_state_widget.dart';
import '../call/mison_call_screen.dart';

class MisonOrderDetailScreen extends StatefulWidget {
  final String orderId;
  final double? distanceKm;
  const MisonOrderDetailScreen({Key? key, required this.orderId, this.distanceKm}) : super(key: key);

  @override
  State<MisonOrderDetailScreen> createState() => _MisonOrderDetailScreenState();
}

class _MisonOrderDetailScreenState extends State<MisonOrderDetailScreen> {
  late Future<MisonOrderDetailResponse> future;

  @override
  void initState() {
    super.initState();
    init();
    LiveStream().on(LIVESTREAM_ORDER_PAYMENT_UPDATE, (orderId) {
      if (orderId.toString() == widget.orderId) {
        init();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    LiveStream().dispose(LIVESTREAM_ORDER_PAYMENT_UPDATE);
    super.dispose();
  }

  void init() => future = getMisonOrderDetail(widget.orderId);

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    try { return DateFormat('dd MMM yyyy', 'fr_FR').format(DateTime.parse(iso).toLocal()); }
    catch (_) { return iso; }
  }

  String _fmtTime(String? iso) {
    if (iso == null) return '';
    try { return DateFormat('HH:mm').format(DateTime.parse(iso).toLocal()); }
    catch (_) { return ''; }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'PENDING':                      return pending;
      case 'ASSIGNED':                     return assigned_booking;
      case 'ACCEPTED':                     return accept;
      case 'AWAITING_TRAVEL_PAYMENT':      return const Color(0xFFC99700);
      case 'IN_PROGRESS':                  return in_progress;
      case 'AWAITING_REALIZATION_PAYMENT': return const Color(0xFFE67E22);
      case 'COMPLETED':                    return completed;
      case 'CANCELLED':                    return cancelled;
      case 'REJECTED':                     return rejected;
      default:                             return defaultStatus;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'PENDING':                      return 'En attente';
      case 'ASSIGNED':                     return 'Artisan assigné';
      case 'ACCEPTED':                     return 'Accepté';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'Frais de déplacement';
      case 'IN_PROGRESS':                  return 'En cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'Frais de réalisation';
      case 'COMPLETED':                    return 'Terminé';
      case 'CANCELLED':                    return 'Annulé';
      case 'REJECTED':                     return 'Refusé';
      default:                             return s ?? 'Inconnu';
    }
  }

  IconData _statusIcon(String? s) {
    switch (s) {
      case 'PENDING':                      return Icons.hourglass_empty_rounded;
      case 'ASSIGNED':                     return Icons.person_add_rounded;
      case 'ACCEPTED':                     return Icons.check_circle_rounded;
      case 'AWAITING_TRAVEL_PAYMENT':      return Icons.directions_car_rounded;
      case 'IN_PROGRESS':                  return Icons.construction_rounded;
      case 'AWAITING_REALIZATION_PAYMENT': return Icons.payments_rounded;
      case 'COMPLETED':                    return Icons.verified_rounded;
      case 'CANCELLED':                    return Icons.cancel_rounded;
      case 'REJECTED':                     return Icons.block_rounded;
      default:                             return Icons.info_rounded;
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _acceptOrder(String id) async {
    appStore.setLoading(true);
    try {
      final res = await artisanAcceptOrder(id);
      toast(res.message ?? 'Succès');
      init(); setState(() {});
    } catch (e) { toast(e.toString()); }
    finally { appStore.setLoading(false); }
  }

  void _showSetFeeModal({
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
        onConfirm: () async {
          final amount = num.tryParse(ctrl.text.trim());
          if (amount == null || amount <= 0) { toast('Veuillez saisir un montant valide'); return; }
          Navigator.pop(context);
          appStore.setLoading(true);
          try {
            final res = await apiCall(amount);
            toast(res.message ?? 'Succès');
            init(); setState(() {});
          } catch (e) { toast(e.toString()); }
          finally { appStore.setLoading(false); }
        },
      ),
    );
  }

  Future<void> _cancelOrder(String id) async {
    appStore.setLoading(true);
    try {
      await cancelMisonOrder(id);
      toast('Commande annulée');
      init(); setState(() {});
    } catch (e) { toast(e.toString()); }
    finally { appStore.setLoading(false); }
  }

  void _confirm({
    required String title,
    required String subtitle,
    required VoidCallback onConfirm,
    DialogType type = DialogType.CONFIRMATION,
  }) {
    showConfirmDialogCustom(
      context,
      title: title,
      subTitle: subtitle,
      positiveText: 'Confirmer',
      negativeText: 'Annuler',
      dialogType: type,
      onAccept: (_) => onConfirm(),
    );
  }

  void _showRatingDialog(MisonOrder order) {
    int rating = 5;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: radius(16)),
          title: Text('Noter la prestation', style: boldTextStyle()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => setS(() => rating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(i < rating ? Icons.star_rounded : Icons.star_outline_rounded, color: ratingBarColor, size: 36),
                  ),
                )),
              ),
              12.height,
              AppTextField(
                controller: ctrl,
                textFieldType: TextFieldType.MULTILINE,
                minLines: 3, maxLines: 5,
                decoration: inputDecoration(context).copyWith(hintText: 'Votre avis...', filled: true, fillColor: context.cardColor),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Annuler', style: primaryTextStyle(color: Colors.grey))),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await rateMisonOrder(order.id ?? '', rating, ctrl.text);
                  toast('Merci pour votre avis !');
                  init(); setState(() {});
                } catch (e) { toast(e.toString()); }
              },
              child: Text('Envoyer', style: boldTextStyle(color: primaryColor)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentModal(MisonOrder order) {
    final isTravel = order.isAwaitingTravelPayment;
    final title = isTravel ? 'Frais de déplacement' : 'Frais de réalisation';
    final desc  = isTravel
        ? 'Ces frais couvrent le déplacement de l\'artisan jusqu\'à votre lieu d\'intervention.'
        : 'Ces frais correspondent à la réalisation de la prestation par l\'artisan.';
    final feeRaw = order.currentFeeAmount;
    final feeNum = num.tryParse(feeRaw ?? '');
    final feeLabel = feeNum != null
        ? '${feeNum.toStringAsFixed(0)} FCFA'
        : (feeRaw != null ? '$feeRaw FCFA' : 'Montant non défini');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentBottomSheet(
        title: title,
        desc: desc,
        feeLabel: feeLabel,
        onPayWave: () async {
          Navigator.pop(context);
          appStore.setLoading(true);
          try {
            final res = await paymentCheckout(order.id ?? '');
            if (res.waveLaunchUrl != null && res.waveLaunchUrl!.isNotEmpty) {
              await launchUrl(Uri.parse(res.waveLaunchUrl!), mode: LaunchMode.externalApplication);
            } else {
              toast(res.message ?? 'Paiement Wave initié');
            }
            init(); setState(() {});
          } catch (e) { toast(e.toString()); }
          finally { appStore.setLoading(false); }
        },
        onPayOrange: () async {
          Navigator.pop(context);
          appStore.setLoading(true);
          try {
            final res = await paymentCheckoutOrange(order.id ?? '');
            if (res.deeplink != null && res.deeplink!.isNotEmpty) {
              await launchUrl(Uri.parse(res.deeplink!), mode: LaunchMode.externalApplication);
            } else {
              toast(res.message ?? 'Paiement Orange Money initié');
            }
            init(); setState(() {});
          } catch (e) { toast(e.toString()); }
          finally { appStore.setLoading(false); }
        },
      ),
    );
  }

  Future<void> _startCall(MisonOrder order) async {
    appStore.setLoading(true);
    try {
      final tokenData = await getCallToken(order.id!);
      appStore.setLoading(false);
      if (!mounted) return;
      final otherName = appStore.userType == USER_TYPE_PROVIDER
          ? order.client != null
              ? '${order.client!.firstName ?? ''} ${order.client!.lastName ?? ''}'.trim()
              : 'Client'
          : order.artisan?.fullName ?? 'Artisan';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MisonCallScreen(
            orderId: order.id!,
            otherPartyName: otherName.isNotEmpty ? otherName : 'Correspondant',
            appId: tokenData.appId ?? '',
            channel: tokenData.channel ?? '',
            token: tokenData.token ?? '',
            uid: tokenData.uid ?? 1,
          ),
        ),
      );
    } catch (e, st) {
      appStore.setLoading(false);
      log('_startCall error: $e\n$st');
      toast('Impossible d\'initier l\'appel : $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      body: Stack(
        children: [
          SnapHelperWidget<MisonOrderDetailResponse>(
            future: future,
            loadingWidget: const Center(child: CircularProgressIndicator()),
            errorBuilder: (error) => Center(
              child: NoDataWidget(
                title: error,
                imageWidget: const ErrorStateWidget(),
                retryText: 'Réessayer',
                onRetry: () { init(); setState(() {}); },
              ),
            ),
            onSuccess: (response) {
              final order = response.data;
              if (order == null) {
                return const Center(child: NoDataWidget(title: 'Commande introuvable'));
              }
              return _OrderDetailBody(
                order: order,
                distanceKm: widget.distanceKm,
                fmtDate: _fmtDate,
                fmtTime: _fmtTime,
                statusColor: _statusColor,
                statusLabel: _statusLabel,
                statusIcon: _statusIcon,
                onAccept: () => _confirm(title: 'Accepter la commande', subtitle: 'Confirmez-vous l\'acceptation ?', onConfirm: () => _acceptOrder(order.id!)),
                onSetTravelFee: () => _showSetFeeModal(
                  title: 'Frais de déplacement',
                  apiCall: (amount) => setTravelFee(order.id!, amount),
                ),
                onSetRealizationFee: () => _showSetFeeModal(
                  title: 'Frais de réalisation',
                  apiCall: (amount) => setRealizationFee(order.id!, amount),
                ),
                onCancel: () => _confirm(title: 'Annuler la commande', subtitle: 'Êtes-vous sûr de vouloir annuler ?', type: DialogType.DELETE, onConfirm: () => _cancelOrder(order.id!)),
                onPay: () => _showPaymentModal(order),
                onRate: () => _showRatingDialog(order),
                onCall: () => _startCall(order),
              );
            },
          ),
          Observer(builder: (_) => LoaderWidget().visible(appStore.isLoading)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Corps du détail — séparé pour garder le State léger
// ─────────────────────────────────────────────────────────────────────────────

class _OrderDetailBody extends StatelessWidget {
  final MisonOrder order;
  final double? distanceKm;
  final String Function(String?) fmtDate;
  final String Function(String?) fmtTime;
  final Color Function(String?) statusColor;
  final String Function(String?) statusLabel;
  final IconData Function(String?) statusIcon;
  final VoidCallback onAccept;
  final VoidCallback onSetTravelFee;
  final VoidCallback onSetRealizationFee;
  final VoidCallback onCancel;
  final VoidCallback onPay;
  final VoidCallback onRate;
  final VoidCallback onCall;

  const _OrderDetailBody({
    required this.order,
    this.distanceKm,
    required this.fmtDate,
    required this.fmtTime,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
    required this.onAccept,
    required this.onSetTravelFee,
    required this.onSetRealizationFee,
    required this.onCancel,
    required this.onPay,
    required this.onRate,
    required this.onCall,
  });

  bool get _isArtisan => appStore.userType == USER_TYPE_PROVIDER;
  bool get _isClient  => !_isArtisan;

  bool get _showPayButton =>
      _isClient && order.isAwaitingAnyPayment;

  @override
  Widget build(BuildContext context) {
    final sColor = statusColor(order.status);
    final showBottomCall = order.canCall;

    return Stack(
      children: [
      CustomScrollView(
      slivers: [
        // ── Hero header ─────────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 110,
          pinned: true,
          backgroundColor: primaryColor,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withValues(alpha: 0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    order.service?.name ?? 'Commande',
                    style: boldTextStyle(color: Colors.white, size: 20),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  6.height,
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon(order.status), color: Colors.white, size: 13),
                            5.width,
                            Text(statusLabel(order.status), style: boldTextStyle(color: Colors.white, size: 12)),
                          ],
                        ),
                      ),
                      if (order.id != null) ...[
                        12.width,
                        Text(
                          '#${order.id!.length > 8 ? order.id!.substring(0, 8).toUpperCase() : order.id!.toUpperCase()}',
                          style: secondaryTextStyle(color: Colors.white60, size: 12),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, showBottomCall ? 100 : 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Artisan card — visible par le client uniquement ──────────
                if (_isClient && order.artisan != null) ...[
                  _ArtisanHeroCard(artisan: order.artisan!, statusColor: sColor, statusLabel: statusLabel(order.status)),
                  20.height,
                ],

                // ── Badge distance — artisan sur commandes à traiter ─────────
                if (_isArtisan && distanceKm != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.near_me_rounded, size: 16, color: Colors.orange),
                        8.width,
                        Text(
                          'Prestation demandée à ${distanceKm! < 1 ? '${(distanceKm! * 1000).round()} m' : '${distanceKm!.toStringAsFixed(1)} km'} de vous',
                          style: boldTextStyle(size: 13, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                  16.height,
                ],


                // ── Frais de déplacement — bouton primaire client ─────────────
                if (_showPayButton) ...[
                  _PaymentBanner(onPay: onPay),
                  20.height,
                ],

                // ── Artisan : actions (disponible) ──────────────────────────
                if (_isArtisan && order.isPending && order.artisan == null) ...[
                  AppButton(
                    width: double.infinity,
                    color: accept,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onTap: onAccept,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                        8.width,
                        Text('Accepter cette commande', style: boldTextStyle(color: Colors.white, size: 15)),
                      ],
                    ),
                  ),
                  20.height,
                ],

                // ── Artisan : Définir frais déplacement / réalisation ────────
                if (_isArtisan && order.artisan != null) ...[
                  if (order.isAccepted) ...[
                    AppButton(
                      width: double.infinity,
                      color: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onTap: onSetTravelFee,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.directions_car_rounded, color: Colors.white, size: 20),
                          8.width,
                          Text('Définir les frais de déplacement', style: boldTextStyle(color: Colors.white, size: 15)),
                        ],
                      ),
                    ),
                    20.height,
                  ],
                  if (order.isInProgress) ...[
                    AppButton(
                      width: double.infinity,
                      color: completed,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onTap: onSetRealizationFee,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
                          8.width,
                          Text('Définir les frais de réalisation', style: boldTextStyle(color: Colors.white, size: 15)),
                        ],
                      ),
                    ),
                    20.height,
                  ],
                ],

                // ── Infos commande ──────────────────────────────────────────
                _InfoCard(children: [
                  _InfoRow(icon: Icons.calendar_today_rounded, label: 'Date', value: fmtDate(order.serviceDate)),
                  _Divider(),
                  _InfoRow(icon: Icons.access_time_rounded, label: 'Heure', value: fmtTime(order.serviceDate)),
                  if (order.serviceAddress != null && order.serviceAddress!.isNotEmpty) ...[
                    _Divider(),
                    _InfoRow(icon: Icons.location_on_rounded, label: 'Adresse', value: order.serviceAddress!),
                  ],
                ]),

                if (order.description != null && order.description!.isNotEmpty) ...[
                  16.height,
                  _InfoCard(children: [
                    _InfoRow(icon: Icons.notes_rounded, label: 'Description', value: order.description!),
                  ]),
                ],

                // ── Statut paiement ─────────────────────────────────────────
                if (order.paymentStatus != null) ...[
                  16.height,
                  _InfoCard(children: [
                    _InfoRow(
                      icon: Icons.payments_outlined,
                      label: 'Paiement',
                      value: _paymentLabel(order.paymentStatus),
                      valueColor: _paymentColor(order.paymentStatus),
                    ),
                  ]),
                ],

                // ── Client : Annuler ────────────────────────────────────────
                if (_isClient && (order.isPending || order.isAssigned)) ...[
                  20.height,
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: rejected,
                      side: BorderSide(color: rejected.withValues(alpha: 0.6)),
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: onCancel,
                    child: Text('Annuler la commande', style: boldTextStyle(color: rejected, size: 15)),
                  ),
                ],

                // ── Client : Noter ──────────────────────────────────────────
                if (_isClient && order.canRate) ...[
                  16.height,
                  AppButton(
                    width: double.infinity,
                    color: ratingBarColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onTap: onRate,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.white, size: 20),
                        8.width,
                        Text('Noter cette prestation', style: boldTextStyle(color: Colors.white, size: 15)),
                      ],
                    ),
                  ),
                ],

                // ── Évaluation existante ────────────────────────────────────
                if (order.clientRating != null) ...[
                  20.height,
                  _InfoCard(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Votre évaluation', style: boldTextStyle(size: 13, color: Colors.grey)),
                          8.height,
                          Row(
                            children: List.generate(5, (i) => Icon(
                              i < order.clientRating! ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: ratingBarColor, size: 22,
                            )),
                          ),
                          if (order.clientReview != null && order.clientReview!.isNotEmpty) ...[
                            8.height,
                            Text(order.clientReview!, style: secondaryTextStyle()),
                          ],
                        ],
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ],
      ),  // end CustomScrollView

      // ── Bouton appel fixe en bas — artisan uniquement ──────────────────
      if (showBottomCall)
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            decoration: BoxDecoration(
              color: context.scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: AppButton(
              width: double.infinity,
              height: 52,
              color: Colors.green,
              shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: onCall,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                  10.width,
                  Text(_isArtisan ? 'Appeler le client' : 'Appeler l\'artisan', style: boldTextStyle(color: Colors.white, size: 15)),
                ],
              ),
            ),
          ),
        ),
      ],  // end Stack children
    );  // end Stack
  }

  String _paymentLabel(String? s) {
    switch (s?.toUpperCase()) {
      case 'PAID':     return 'Payé';
      case 'REFUNDED': return 'Remboursé';
      default:         return 'En attente';
    }
  }

  Color _paymentColor(String? s) {
    switch (s?.toUpperCase()) {
      case 'PAID':     return completed;
      case 'REFUNDED': return Colors.orange;
      default:         return rejected;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Artisan hero card
// ─────────────────────────────────────────────────────────────────────────────

class _ArtisanHeroCard extends StatelessWidget {
  final MisonArtisanInfo artisan;
  final Color statusColor;
  final String statusLabel;

  const _ArtisanHeroCard({required this.artisan, required this.statusColor, required this.statusLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // ── Bandeau statut ─────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                8.width,
                Text(statusLabel, style: boldTextStyle(size: 13, color: statusColor)),
              ],
            ),
          ),

          // ── Artisan info ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor.withValues(alpha: 0.1),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.2), width: 2),
                    image: artisan.profilePictureUrl != null
                        ? DecorationImage(image: NetworkImage(artisan.profilePictureUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: artisan.profilePictureUrl == null
                      ? Icon(Icons.person_rounded, color: primaryColor, size: 32)
                      : null,
                ),
                16.width,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(artisan.fullName, style: boldTextStyle(size: 17)),
                      6.height,
                      if (artisan.experienceYears != null)
                        Row(children: [
                          Icon(Icons.work_outline_rounded, size: 13, color: Colors.grey),
                          4.width,
                          Text('${artisan.experienceYears} ans d\'expérience', style: secondaryTextStyle(size: 12)),
                        ]),
                      if (artisan.averageRating != null) ...[
                        4.height,
                        Row(children: [
                          Icon(Icons.star_rounded, size: 14, color: ratingBarColor),
                          4.width,
                          Text(
                            '${artisan.rating.toStringAsFixed(1)} (${artisan.totalReviews ?? 0} avis)',
                            style: secondaryTextStyle(size: 12),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bannière paiement des frais de déplacement
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentBanner extends StatelessWidget {
  final VoidCallback onPay;
  const _PaymentBanner({required this.onPay});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFC99700), Color(0xFFE5B800)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: const Color(0xFFC99700).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payments_rounded, color: Colors.white, size: 24),
                ),
                14.width,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Payer les frais de déplacement', style: boldTextStyle(color: Colors.white, size: 15)),
                      3.height,
                      Text('Couvrez les frais de déplacement de l\'artisan', style: secondaryTextStyle(color: Colors.white70, size: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Composants utilitaires
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primaryColor, size: 18),
          ),
          12.width,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: secondaryTextStyle(size: 12)),
                4.height,
                Text(value, style: boldTextStyle(size: 14, color: valueColor), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 48, color: Colors.grey.withValues(alpha: 0.15));
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
          // Poignée
          Center(
            child: Container(
              width: 40, height: 4,
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
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.35)),
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
            shapeBorder:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: onConfirm,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet paiement (Wave / Orange Money grisé)
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentBottomSheet extends StatefulWidget {
  final String title;
  final String desc;
  final String feeLabel;
  final VoidCallback onPayWave;
  final VoidCallback onPayOrange;

  const _PaymentBottomSheet({
    required this.title,
    required this.desc,
    required this.feeLabel,
    required this.onPayWave,
    required this.onPayOrange,
  });

  @override
  State<_PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends State<_PaymentBottomSheet> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final isWave   = _selected == 'wave';
    final isOrange = _selected == 'orange';
    final canPay   = isWave || isOrange;

    final btnColor = isWave
        ? const Color(0xFF1BA1F1)
        : isOrange
            ? const Color(0xFFFF7900)
            : Colors.grey.shade300;
    final btnLabel = isOrange ? 'Payer avec Orange Money' : 'Payer avec Wave';

    return Container(
      decoration: BoxDecoration(
        color: context.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poignée
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          20.height,

          Text(widget.title, style: boldTextStyle(size: 18)),
          16.height,

          // Montant
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFC99700).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC99700).withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.desc, style: secondaryTextStyle(size: 12)),
                8.height,
                Text(widget.feeLabel,
                    style: boldTextStyle(size: 20, color: const Color(0xFFC99700))),
              ],
            ),
          ),
          20.height,

          Text('Mode de paiement', style: boldTextStyle(size: 14)),
          12.height,

          // Wave
          _MethodTile(
            label: 'Wave',
            subtitle: 'Paiement mobile sécurisé',
            logoAsset: 'assets/images/wave_logo.png',
            color: const Color(0xFF1BA1F1),
            selected: isWave,
            enabled: true,
            onTap: () => setState(() => _selected = 'wave'),
          ),
          10.height,

          // Orange Money
          _MethodTile(
            label: 'Orange Money',
            subtitle: 'Paiement Orange Money',
            logoAsset: 'assets/images/orange_money.jpg',
            color: const Color(0xFFFF7900),
            selected: isOrange,
            enabled: true,
            onTap: () => setState(() => _selected = 'orange'),
          ),
          24.height,

          AppButton(
            text: btnLabel,
            color: canPay ? btnColor : Colors.grey.shade300,
            textColor: canPay ? Colors.white : Colors.grey,
            width: double.infinity,
            height: 50,
            shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: canPay
                ? (isOrange ? widget.onPayOrange : widget.onPayWave)
                : null,
          ),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final String? logoAsset;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _MethodTile({
    required this.label,
    required this.subtitle,
    this.logoAsset,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.07) : context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : Colors.grey.withValues(alpha: 0.2),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: logoAsset != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(logoAsset!, fit: BoxFit.cover),
                      )
                    : const SizedBox.shrink(),
              ),
              12.width,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: boldTextStyle(size: 14)),
                    2.height,
                    Text(subtitle, style: secondaryTextStyle(size: 11)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
