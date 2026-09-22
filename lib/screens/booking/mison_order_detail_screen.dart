import 'dart:async';
import 'dart:convert';
import 'dart:math' show sin, cos, sqrt, atan2;

import 'package:booking_system_flutter/component/app_empty_state.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:booking_system_flutter/utils/firebase_messaging_utils.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../call/mison_call_screen.dart';
import '../chat/mison_order_chat_screen.dart';
import '../map/mison_artisan_navigation_screen.dart';
import '../map/mison_tracking_screen.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class MisonOrderDetailScreen extends StatefulWidget {
  final String orderId;
  final double? distanceKm;
  const MisonOrderDetailScreen({Key? key, required this.orderId, this.distanceKm}) : super(key: key);

  @override
  State<MisonOrderDetailScreen> createState() => _MisonOrderDetailScreenState();
}

class _MisonOrderDetailScreenState extends State<MisonOrderDetailScreen> with WidgetsBindingObserver {
  late Future<MisonOrderDetailResponse> future;
  Timer? _locationTimer;
  Position? _artisanPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    init();
    if (appStore.userType == USER_TYPE_PROVIDER) _fetchArtisanPosition();
    LiveStream().on(LIVESTREAM_ORDER_PAYMENT_UPDATE, (orderId) {
      if (orderId.toString() == widget.orderId) {
        init();
        if (mounted) setState(() {});
      }
    });
    // Statut de commande changé côté serveur (ex: prestation terminée par l'ouvrier)
    // — ces events ne portent pas l'orderId, on rafraîchit systématiquement.
    LiveStream().on(LIVESTREAM_ORDERS_LIST_REFRESH, (_) {
      init();
      if (mounted) setState(() {});
    });
    LiveStream().on(LIVESTREAM_UPDATE_BOOKING_LIST, (_) {
      init();
      if (mounted) setState(() {});
    });
    LiveStream().on(LIVESTREAM_ARTISAN_ORDERS_REFRESH, (_) {
      init();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    LiveStream().dispose(LIVESTREAM_ORDER_PAYMENT_UPDATE);
    LiveStream().dispose(LIVESTREAM_ORDERS_LIST_REFRESH);
    LiveStream().dispose(LIVESTREAM_UPDATE_BOOKING_LIST);
    LiveStream().dispose(LIVESTREAM_ARTISAN_ORDERS_REFRESH);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Le client revient dans l'app après avoir payé via Wave/Orange Money
    // (app externe) : on rafraîchit le statut de la commande.
    if (state == AppLifecycleState.resumed) {
      init();
      if (mounted) setState(() {});
    }
  }

  void init() => future = getMisonOrderDetail(widget.orderId);

  // ── Distance ouvrier → commande (fiable même sans passer par le dashboard) ──

  Future<void> _fetchArtisanPosition() async {
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
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
    } catch (_) {}
  }

  double? _distanceToOrder(MisonOrder order) {
    if (_artisanPosition == null) return null;
    final lat = double.tryParse(order.latitude ?? '');
    final lon = double.tryParse(order.longitude ?? '');
    if (lat == null || lon == null) return null;
    return Geolocator.distanceBetween(
          _artisanPosition!.latitude, _artisanPosition!.longitude, lat, lon) /
        1000;
  }

  // ── Tracking GPS artisan → Firestore ────────────────────────────────────────

  Future<void> _startTracking(String orderId) async {
    if (_locationTimer != null) return;

    // Vérifie/demande la permission GPS avant de démarrer
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
      log('[Tracking] Permission GPS refusée, tracking impossible');
      return;
    }

    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
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
        log('[Tracking] Position envoyée: ${pos.latitude}, ${pos.longitude}');
      } catch (e) {
        log('[Tracking] Erreur: $e');
      }
    });
  }

  void _stopTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

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
      case 'PENDING':                      return 'Recherche d\'ouvrier';
      case 'ACCEPTED':                     return 'Ouvrier trouvé';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'En attente de paiement';
      case 'IN_PROGRESS':                  return 'Intervention en cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'En attente du paiement de la prestation';
      case 'COMPLETED':                    return 'Prestation terminée';
      case 'CANCELLED':                    return 'Commande annulée';
      default:                             return s ?? 'Inconnu';
    }
  }

  IconData _statusIcon(String? s) {
    switch (s) {
      case 'PENDING':                      return Icons.hourglass_empty_rounded;
      case 'ACCEPTED':                     return Icons.check_circle_rounded;
      case 'AWAITING_TRAVEL_PAYMENT':      return Icons.directions_car_rounded;
      case 'IN_PROGRESS':                  return Icons.construction_rounded;
      case 'AWAITING_REALIZATION_PAYMENT': return Icons.payments_rounded;
      case 'COMPLETED':                    return Icons.verified_rounded;
      case 'CANCELLED':                    return Icons.cancel_rounded;
      default:                             return Icons.info_rounded;
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _acceptOrder(String id) async {
    appStore.setLoading(true);
    try {
      final res = await artisanAcceptOrder(id);
      TopToast.show(message: res.message ?? 'Succès', type: TopToastType.success);
      init(); setState(() {});
    } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
    finally { appStore.setLoading(false); }
  }

  Future<void> _startOrder(String id) async {
    appStore.setLoading(true);
    try {
      final res = await artisanStartOrder(id);
      TopToast.show(message: res.message ?? 'Prestation démarrée', type: TopToastType.success);
      init(); setState(() {});
    } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
    finally { appStore.setLoading(false); }
  }

  Future<void> _openChat(MisonOrder order) async {
    final peerName = appStore.userType == USER_TYPE_PROVIDER
        ? (order.client?.fullName.isNotEmpty == true ? order.client!.fullName : 'Client')
        : (order.artisan?.fullName.isNotEmpty == true ? order.artisan!.fullName : 'Ouvrier');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MisonOrderChatScreen(orderId: order.id!, peerName: peerName),
      ),
    );
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
          if (amount == null || amount <= 0) { TopToast.show(message: 'Veuillez saisir un montant valide'); return; }
          Navigator.pop(context);
          appStore.setLoading(true);
          try {
            final res = await apiCall(amount);
            TopToast.show(message: res.message ?? 'Succès', type: TopToastType.success);
            init(); setState(() {});
          } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
          finally { appStore.setLoading(false); }
        },
      ),
    );
  }

  Future<void> _cancelOrder(String id) async {
    final isArtisan = appStore.userType == USER_TYPE_PROVIDER;
    appStore.setLoading(true);
    try {
      await cancelMisonOrder(id);
      TopToast.show(
        message: isArtisan
            ? 'Vous vous êtes désisté de cette commande'
            : 'Commande annulée',
      );
      init(); setState(() {});
    } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
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


  void _showPaymentModal(MisonOrder order) {
    const title = 'Frais de prestation';
    const desc  = 'Ces frais correspondent à la prestation réalisée par l\'ouvrier.';
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
              TopToast.show(message: res.message ?? 'Paiement Wave initié');
            }
            init(); setState(() {});
          } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
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
              TopToast.show(message: res.message ?? 'Paiement Orange Money initié');
            }
            init(); setState(() {});
          } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
          finally { appStore.setLoading(false); }
        },
      ),
    );
  }

  Future<void> _startCall(MisonOrder order) async {
    // Await the SharedPreferences write before the API call triggers FCM.
    // data-only FCM (content-available:1) can arrive in the background isolate
    // before the async write completes if not awaited here.
    await MisonCallScreen.markOutgoing(order.id!);
    appStore.setLoading(true);
    try {
      final tokenData = await getCallToken(order.id!);
      appStore.setLoading(false);
      if (tokenData.appId == null || tokenData.appId!.isEmpty || (tokenData.token ?? '').isEmpty) {
        MisonCallScreen.clearOutgoing(order.id!);
        TopToast.show(message: 'Service d\'appel indisponible pour le moment');
        return;
      }
      if (!mounted) return;
      final otherName = appStore.userType == USER_TYPE_PROVIDER
          ? order.client != null
              ? '${order.client!.firstName ?? ''} ${order.client!.lastName ?? ''}'.trim()
              : 'Client'
          : order.artisan?.fullName ?? 'Ouvrier';
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
            isCaller: true,
          ),
        ),
      );
    } catch (e, st) {
      MisonCallScreen.clearOutgoing(order.id!);
      appStore.setLoading(false);
      log('_startCall error: $e\n$st');
      TopToast.show(message: 'Impossible d\'initier l\'appel : $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DotGridBackground(
        child: Stack(
        children: [
          SnapHelperWidget<MisonOrderDetailResponse>(
            future: future,
            loadingWidget: const Center(child: CircularProgressIndicator()),
            errorBuilder: (error) => AppEmptyState(
              type: AppEmptyStateType.error,
              title: error,
              onRetry: () { init(); setState(() {}); },
            ),
            onSuccess: (response) {
              final order = response.data;
              if (order == null) {
                return const AppEmptyState(
                  type: AppEmptyStateType.empty,
                  title: 'Commande introuvable',
                );
              }
              // Ouvrier : démarrer / arrêter le tracking selon le statut
              if (appStore.userType == USER_TYPE_PROVIDER) {
                if (order.canTrack) {
                  _startTracking(order.id!);
                } else {
                  _stopTracking();
                }
              }
              return _OrderDetailBody(
                order: order,
                distanceKm: _distanceToOrder(order) ?? widget.distanceKm,
                fmtDate: _fmtDate,
                fmtTime: _fmtTime,
                statusColor: _statusColor,
                statusLabel: _statusLabel,
                statusIcon: _statusIcon,
                onAccept: () => _confirm(title: 'Accepter la commande', subtitle: 'Confirmez-vous l\'acceptation ?', onConfirm: () => _acceptOrder(order.id!)),
                onStart: () => _confirm(
                  title: 'Démarrer la prestation',
                  subtitle: 'Prêt à vous rendre sur le lieu de la prestation',
                  onConfirm: () => _startOrder(order.id!),
                ),
                onChat: () => _openChat(order),
                onSetRealizationFee: () => _showSetFeeModal(
                  title: 'Frais de prestation',
                  apiCall: (amount) => setRealizationFee(order.id!, amount),
                ),
                onCancel: () => _confirm(
                  title: appStore.userType == USER_TYPE_PROVIDER
                      ? 'Se désister de la commande'
                      : 'Annuler la commande',
                  subtitle: appStore.userType == USER_TYPE_PROVIDER
                      ? 'La commande sera reproposée aux autres ouvriers. Confirmez-vous ?'
                      : 'Êtes-vous sûr de vouloir annuler ?',
                  type: DialogType.DELETE,
                  onConfirm: () => _cancelOrder(order.id!),
                ),
                onPay: () => _showPaymentModal(order),
                onRated: () { init(); setState(() {}); },
                onCall: () => _startCall(order),
                onTrack: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => MisonTrackingScreen(
                    orderId: order.id!,
                    serviceAddress: order.serviceAddress ?? '',
                    artisanName: order.artisan?.fullName ?? 'Ouvrier',
                    serviceLat: double.tryParse(order.latitude ?? ''),
                    serviceLng: double.tryParse(order.longitude ?? ''),
                  ),
                )),
                onNavigate: () {
                  final lat = double.tryParse(order.latitude ?? '');
                  final lng = double.tryParse(order.longitude ?? '');
                  if (lat == null || lng == null) {
                    TopToast.show(message: 'Coordonnées de destination introuvables');
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => MisonArtisanNavigationScreen(
                      serviceAddress: order.serviceAddress ?? '',
                      destLat: lat,
                      destLng: lng,
                      orderId: order.id!,
                    ),
                  ));
                },
              );
            },
          ),
          Observer(builder: (_) => LoaderWidget().visible(appStore.isLoading)),
        ],
        ),
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
  final VoidCallback onStart;
  final VoidCallback onChat;
  final VoidCallback onSetRealizationFee;
  final VoidCallback onCancel;
  final VoidCallback onPay;
  final VoidCallback onRated;
  final VoidCallback onCall;
  final VoidCallback onTrack;
  final VoidCallback onNavigate;

  const _OrderDetailBody({
    required this.order,
    this.distanceKm,
    required this.fmtDate,
    required this.fmtTime,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
    required this.onAccept,
    required this.onStart,
    required this.onChat,
    required this.onSetRealizationFee,
    required this.onCancel,
    required this.onPay,
    required this.onRated,
    required this.onCall,
    required this.onTrack,
    required this.onNavigate,
  });

  bool get _isArtisan => appStore.userType == USER_TYPE_PROVIDER;
  bool get _isClient  => !_isArtisan;

  bool get _showPayButton =>
      _isClient && order.isAwaitingAnyPayment;

  bool get _canCancel =>
      _isArtisan ? order.canReleaseByArtisan : order.canCancelByClient;

  @override
  Widget build(BuildContext context) {
    final sColor = statusColor(order.status);
    final showBottomCall = order.canCall;
    final showTrackButton = _isClient && order.canTrack;
    final showAcceptButton = _isArtisan &&
        ((order.isPending && order.artisan == null) || order.needsArtisanConfirmation);
    final showStartButton = _isArtisan && order.artisan != null && order.canStart && !order.needsArtisanConfirmation;
    final showSetFeeButton = _isArtisan && order.artisan != null && order.isInProgress;
    final showPrimaryAction = showAcceptButton || showStartButton || showSetFeeButton || _showPayButton || showTrackButton;
    final showBottomBar = showBottomCall || showPrimaryAction;

    late final String primaryActionLabel;
    late final IconData primaryActionIcon;
    late final Color primaryActionColor;
    late final VoidCallback primaryActionTap;
    if (showAcceptButton) {
      primaryActionLabel = order.needsArtisanConfirmation ? 'Confirmer cette commande' : 'Accepter cette commande';
      primaryActionIcon = Icons.check_circle_outline_rounded;
      primaryActionColor = accept;
      primaryActionTap = onAccept;
    } else if (showStartButton) {
      primaryActionLabel = 'Démarrer la prestation';
      primaryActionIcon = Icons.play_circle_outline_rounded;
      primaryActionColor = Colors.green;
      primaryActionTap = onStart;
    } else if (showSetFeeButton) {
      primaryActionLabel = 'Définir les frais de prestation';
      primaryActionIcon = Icons.receipt_long_rounded;
      primaryActionColor = completed;
      primaryActionTap = onSetRealizationFee;
    } else if (_showPayButton) {
      primaryActionLabel = 'Payer la prestation';
      primaryActionIcon = Icons.payment_rounded;
      primaryActionColor = primaryColor;
      primaryActionTap = onPay;
    } else if (showTrackButton) {
      primaryActionLabel = 'Suivre en direct';
      primaryActionIcon = Icons.open_in_full_rounded;
      primaryActionColor = primaryColor;
      primaryActionTap = onTrack;
    }

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
                      Flexible(
                        child: Container(
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
                              Flexible(
                                child: Text(
                                  statusLabel(order.status),
                                  style: boldTextStyle(color: Colors.white, size: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isClient && order.artisan != null) ...[
                        8.width,
                        Flexible(
                          child: Text(
                            'Ouvrier : ${order.artisan!.fullName}',
                            style: secondaryTextStyle(color: Colors.white70, size: 14),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else if (order.id != null) ...[
                        8.width,
                        Text(
                          '#${order.id!.length > 8 ? order.id!.substring(0, 8).toUpperCase() : order.id!.toUpperCase()}',
                          style: secondaryTextStyle(color: Colors.white60, size: 14),
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
            padding: EdgeInsets.fromLTRB(16, 20, 16, showBottomBar ? 100 : 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Client : Noter — en haut quand prestation terminée ───────
                if (_isClient && order.canRate) ...[
                  _RatingBoomChip(order: order, onRated: onRated),
                  20.height,
                ],

                // ── Ouvrier section — client uniquement ──────────────────────
                if (_isClient && order.artisan != null) ...[
                  if (order.canTrack && !order.isAwaitingAnyPayment)
                    _LiveTrackingCard(
                      order: order,
                      artisan: order.artisan!,
                      onTrack: onTrack,
                    )
                  else
                    _ArtisanHeroCard(artisan: order.artisan!, statusColor: sColor, statusLabel: statusLabel(order.status)),
                  20.height,
                ],




                // ── Naviguer vers le client — ouvrier en déplacement ──────────
                if (_isArtisan && order.canTrack) ...[
                  GestureDetector(
                    onTap: onNavigate,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green.withValues(alpha: 0.12),
                            ),
                            child: const Icon(Icons.navigation_rounded, color: Colors.green, size: 20),
                          ),
                          12.width,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Naviguer vers le client', style: boldTextStyle(size: 16, color: Colors.green)),
                                Text('Voir l\'itinéraire sur la carte', style: secondaryTextStyle(size: 13)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.green),
                        ],
                      ),
                    ),
                  ),
                  16.height,
                ],

                // ── Ouvrier : accepter (commande libre ou affectée par l'admin)
                if (_isArtisan &&
                    ((order.isPending && order.artisan == null) ||
                        order.needsArtisanConfirmation)) ...[
                  if (order.needsArtisanConfirmation) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.assignment_ind_rounded, size: 18, color: primaryColor),
                          8.width,
                          Expanded(
                            child: Text(
                              'Cette commande vous a été affectée par Mison. Confirmez-la pour la démarrer.',
                              style: secondaryTextStyle(size: 14, color: primaryColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                // ── Infos commande ──────────────────────────────────────────
                _InfoCard(children: [
                  _InfoRow(icon: Icons.calendar_today_rounded, label: 'Date', value: fmtDate(order.serviceDate)),
                  _Divider(),
                  _InfoRow(icon: Icons.access_time_rounded, label: 'Heure', value: fmtTime(order.serviceDate)),
                  if (_isArtisan && order.status != 'CANCELLED' && order.status != 'REJECTED') ...[
                    _Divider(),
                    _InfoRow(
                      icon: Icons.social_distance_rounded,
                      label: 'Distance',
                      value: distanceKm == null
                          ? '—'
                          : (distanceKm! < 1 ? '${(distanceKm! * 1000).round()} m' : '${distanceKm!.toStringAsFixed(1)} km'),
                    ),
                  ],
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

                // ── Annulation — client et ouvrier ──────────────────────────
                if (_canCancel) ...[
                  20.height,
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: rejected,
                      side: BorderSide(color: rejected.withValues(alpha: 0.6)),
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: onCancel,
                    child: Text(
                      _isArtisan ? 'Se désister de la commande' : 'Annuler la commande',
                      style: boldTextStyle(color: rejected, size: 16),
                    ),
                  ),
                  if (_isArtisan) ...[
                    8.height,
                    Text(
                      'La commande sera reproposée aux autres ouvriers du service.',
                      style: secondaryTextStyle(size: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
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
                          Text('Votre évaluation', style: boldTextStyle(size: 15, color: Colors.grey)),
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

      // ── Barre fixe en bas : démarrer + appel + chat ─────────────────────
      if (showBottomBar)
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
            child: Row(
              children: [
                if (showPrimaryAction) ...[
                  Expanded(
                    child: AppButton(
                      width: double.infinity,
                      height: 52,
                      color: primaryActionColor,
                      shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onTap: primaryActionTap,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(primaryActionIcon, color: Colors.white, size: 20),
                          8.width,
                          Flexible(
                            child: Text(
                              primaryActionLabel,
                              style: boldTextStyle(color: Colors.white, size: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showBottomCall) 12.width,
                ],
                if (showBottomCall) ...[
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: AppButton(
                      width: 52,
                      height: 52,
                      padding: EdgeInsets.zero,
                      color: Colors.white,
                      shapeBorder: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Colors.green, width: 1.5),
                      ),
                      onTap: onCall,
                      child: const Icon(Icons.call_rounded, color: Colors.green, size: 20),
                    ),
                  ),
                  if (order.canChat) ...[
                    12.width,
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: AppButton(
                        width: 52,
                        height: 52,
                        padding: EdgeInsets.zero,
                        color: primaryColor,
                        shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        onTap: onChat,
                        child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],  // end Stack children
    );  // end Stack
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Ouvrier hero card
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
                Text(statusLabel, style: boldTextStyle(size: 15, color: statusColor)),
              ],
            ),
          ),

          // ── Ouvrier info ───────────────────────────────────────────────────
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
                        ? DecorationImage(image: CachedNetworkImageProvider(artisan.profilePictureUrl!), fit: BoxFit.cover)
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
                          Text('${artisan.experienceYears} ans d\'expérience', style: secondaryTextStyle(size: 14)),
                        ]),
                      if (artisan.averageRating != null) ...[
                        4.height,
                        Row(children: [
                          Icon(Icons.star_rounded, size: 14, color: ratingBarColor),
                          4.width,
                          Text(
                            '${artisan.rating.toStringAsFixed(1)} (${artisan.totalReviews ?? 0} avis)',
                            style: secondaryTextStyle(size: 14),
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
  const _InfoRow({required this.icon, required this.label, required this.value});

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
                Text(label, style: secondaryTextStyle(size: 14)),
                4.height,
                Text(value, style: boldTextStyle(size: 16), maxLines: 3, overflow: TextOverflow.ellipsis),
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
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            style: boldTextStyle(size: 16),
            decoration: InputDecoration(
              hintText: 'Montant en FCFA',
              hintStyle: secondaryTextStyle(size: 14),
              suffixIcon: IconButton(
                icon: Icon(Icons.check_circle_outline, color: primaryColor),
                onPressed: () => FocusScope.of(context).unfocus(),
                tooltip: 'Fermer le clavier',
              ),
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
                Text(widget.desc, style: secondaryTextStyle(size: 14)),
                8.height,
                Text(widget.feeLabel,
                    style: boldTextStyle(size: 20, color: const Color(0xFFC99700))),
              ],
            ),
          ),
          20.height,

          Text('Mode de paiement', style: boldTextStyle(size: 16)),
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
          // 10.height,

          // Orange Money
          // _MethodTile(
          //   label: 'Orange Money',
          //   subtitle: 'Paiement Orange Money',
          //   logoAsset: 'assets/images/orange_money.jpg',
          //   color: const Color(0xFFFF7900),
          //   selected: isOrange,
          //   enabled: true,
          //   onTap: () => setState(() => _selected = 'orange'),
          // ),
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
                    Text(label, style: boldTextStyle(size: 16)),
                    2.height,
                    Text(subtitle, style: secondaryTextStyle(size: 13)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Rating boom chip — s'ouvre inline au tap, sans modal
// ─────────────────────────────────────────────────────────────────────────────

class _RatingBoomChip extends StatefulWidget {
  final MisonOrder order;
  final VoidCallback onRated;

  const _RatingBoomChip({required this.order, required this.onRated});

  @override
  State<_RatingBoomChip> createState() => _RatingBoomChipState();
}

class _RatingBoomChipState extends State<_RatingBoomChip> {
  bool _expanded = false;
  bool _dismissed = false;
  int _rating = 5;
  final _ctrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      // Le commentaire est facultatif : seule la note est requise.
      await rateMisonOrder(widget.order.id ?? '', _rating, _ctrl.text.trim());
      TopToast.show(message: 'Merci pour votre avis !');
      widget.onRated();
    } catch (e) {
      TopToast.show(message: e.toString(), type: TopToastType.error);
      setState(() => _submitting = false);
    }
  }

  String _ratingLabel(int r) {
    switch (r) {
      case 1: return 'Très décevant';
      case 2: return 'Décevant';
      case 3: return 'Correct';
      case 4: return 'Bien';
      case 5: return 'Excellent !';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ratingBarColor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: ratingBarColor.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // ── En-tête toujours visible ───────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ratingBarColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(Icons.star_rounded, color: ratingBarColor, size: 20),
                  ),
                  12.width,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Donner votre avis', style: boldTextStyle(size: 16)),
                            8.width,
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('Facultatif', style: secondaryTextStyle(size: 12)),
                            ),
                          ],
                        ),
                        4.height,
                        Text('Comment s\'est passée la prestation ?', style: secondaryTextStyle(size: 13)),
                      ],
                    ),
                  ),
                  // Masquer l'invitation — l'évaluation n'est jamais imposée.
                  IconButton(
                    tooltip: 'Ignorer',
                    icon: Icon(Icons.close_rounded, color: appTextSecondaryColor, size: 20),
                    onPressed: () => setState(() => _dismissed = true),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: ratingBarColor, size: 24),
                  ),
                ],
              ),
            ),
          ),

          // ── Contenu dépliable ──────────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                children: [
                  Divider(color: ratingBarColor.withValues(alpha: 0.15), height: 1),
                  20.height,

                  // Étoiles interactives
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) => GestureDetector(
                      onTap: () => setState(() => _rating = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            i < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                            key: ValueKey('$i-${i < _rating}'),
                            color: i < _rating ? ratingBarColor : Colors.grey.shade300,
                            size: 44,
                          ),
                        ),
                      ),
                    )),
                  ),
                  8.height,
                  Text(
                    _ratingLabel(_rating),
                    style: boldTextStyle(size: 15, color: ratingBarColor),
                  ),
                  16.height,

                  // Champ avis
                  TextField(
                    controller: _ctrl,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: 'Partagez votre expérience (optionnel)',
                      hintStyle: secondaryTextStyle(size: 14),
                      filled: true,
                      fillColor: context.scaffoldBackgroundColor,
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: ratingBarColor, width: 1.5),
                      ),
                    ),
                  ),
                  16.height,

                  // Bouton envoyer
                  AppButton(
                    width: double.infinity,
                    color: ratingBarColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                              8.width,
                              Text(
                                _ctrl.text.trim().isEmpty ? 'Envoyer ma note' : 'Envoyer mon avis',
                                style: boldTextStyle(color: Colors.white, size: 16),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini-map tracking card — client, quand order.canTrack
// ─────────────────────────────────────────────────────────────────────────────

class _LiveTrackingCard extends StatefulWidget {
  final MisonOrder order;
  final MisonArtisanInfo artisan;
  final VoidCallback onTrack;

  const _LiveTrackingCard({
    required this.order,
    required this.artisan,
    required this.onTrack,
  });

  @override
  State<_LiveTrackingCard> createState() => _LiveTrackingCardState();
}

class _LiveTrackingCardState extends State<_LiveTrackingCard> {
  final _mapController = MapController();
  LatLng? _artisanPos;
  LatLng? _destPos;
  double _bearing = 0;
  StreamSubscription<DocumentSnapshot>? _sub;

  // Route OSRM
  List<LatLng> _routePoints    = [];
  double?      _roadDistanceM;
  int?         _etaSeconds;
  bool         _fetchingRoute  = false;
  DateTime?    _lastRouteFetch;

  // Alertes
  bool _hadFirstUpdate    = false;
  bool _wasNearby         = false;
  bool _nearbyAlertShown  = false;
  bool _arrivedAlertShown = false;

  @override
  void initState() {
    super.initState();
    final lat = double.tryParse(widget.order.latitude ?? '');
    final lng = double.tryParse(widget.order.longitude ?? '');
    if (lat != null && lng != null) _destPos = LatLng(lat, lng);

    _sub = FirebaseFirestore.instance
        .collection('artisan_locations')
        .doc(widget.order.id)
        .snapshots()
        .listen(_onLocation);
  }

  void _onLocation(DocumentSnapshot snap) {
    if (!snap.exists || !mounted) return;
    final data = snap.data() as Map<String, dynamic>;
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final pos = LatLng(lat, lng);
    final previous = _artisanPos;
    if (previous != null) {
      final movedMeters = _haversineBetween(previous, pos);
      // On ignore le bruit GPS (petits sauts) pour une flèche stable
      if (movedMeters > 3) {
        _bearing = _bearingBetween(previous, pos);
      }
    }
    setState(() => _artisanPos = pos);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
    _fetchRoute();
    _checkNearby();
  }

  double _haversineBetween(LatLng a, LatLng b) {
    const r = 6371000.0;
    const toRad = 3.141592653589793 / 180;
    final phi1 = a.latitude * toRad;
    final phi2 = b.latitude * toRad;
    final dPhi = (b.latitude - a.latitude) * toRad;
    final dLambda = (b.longitude - a.longitude) * toRad;
    final x = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return r * 2 * atan2(sqrt(x), sqrt(1 - x));
  }

  // Cap (direction) en degrés, 0° = nord, sens horaire — comme Google Maps
  double _bearingBetween(LatLng start, LatLng end) {
    const toRad = 3.141592653589793 / 180;
    final lat1 = start.latitude * toRad;
    final lat2 = end.latitude * toRad;
    final dLng = (end.longitude - start.longitude) * toRad;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    final deg = atan2(y, x) * 180 / pi;
    return (deg + 360) % 360;
  }

  Future<void> _fetchRoute() async {
    if (_artisanPos == null || _destPos == null) return;
    if (_fetchingRoute) return;
    final now = DateTime.now();
    if (_lastRouteFetch != null &&
        now.difference(_lastRouteFetch!) < const Duration(seconds: 30)) return;

    _fetchingRoute  = true;
    _lastRouteFetch = now;
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${_artisanPos!.longitude},${_artisanPos!.latitude};'
          '${_destPos!.longitude},${_destPos!.latitude}'
          '?steps=false&geometries=geojson&overview=full';

      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || !mounted) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return;

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      if (mounted) {
        setState(() {
          _routePoints   = coords;
          _roadDistanceM = (route['distance'] as num).toDouble();
          _etaSeconds    = (route['duration'] as num).toInt();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
      }
    } catch (_) {
    } finally {
      _fetchingRoute = false;
    }
  }

  void _checkNearby() {
    if (_destPos == null || _artisanPos == null) return;
    final dist = _roadDistanceM ?? _haversineDist();
    if (dist == null) return;

    final isArrived = dist < 100;
    final isNearby  = dist < 500;

    if (_hadFirstUpdate) {
      if (isArrived && !_arrivedAlertShown) {
        _arrivedAlertShown = true;
        _nearbyAlertShown  = true;
        showSimpleLocalNotification(
          id: 9002,
          title: '${widget.artisan.fullName} est arrivé !',
          body: 'Votre ouvrier est arrivé à votre adresse.',
        );
      } else if (isNearby && !_wasNearby && !_nearbyAlertShown) {
        _nearbyAlertShown = true;
        showSimpleLocalNotification(
          id: 9001,
          title: '${widget.artisan.fullName} est proche !',
          body: 'Votre ouvrier est à moins de 500 m de chez vous.',
        );
      }
    }

    _wasNearby      = isNearby;
    _hadFirstUpdate = true;
  }

  void _fitMap() {
    final points = [
      if (_routePoints.isNotEmpty) ..._routePoints
      else ...[if (_artisanPos != null) _artisanPos!, if (_destPos != null) _destPos!],
    ];
    if (points.isEmpty) return;
    try {
      if (points.length == 1) {
        _mapController.move(points.first, 14);
      } else {
        _mapController.fitCamera(
          CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40)),
        );
      }
    } catch (_) {}
  }

  double? _haversineDist() {
    if (_artisanPos == null || _destPos == null) return null;
    final lat1 = _artisanPos!.latitude * (3.14159265 / 180);
    final lat2 = _destPos!.latitude * (3.14159265 / 180);
    final dLat = (_destPos!.latitude - _artisanPos!.latitude) * (3.14159265 / 180);
    final dLon = (_destPos!.longitude - _artisanPos!.longitude) * (3.14159265 / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    return 6371000.0 * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String _fmtDist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  String _fmtEta(int s) {
    if (s < 60) return 'moins d\'1 min';
    final min = s ~/ 60;
    if (min < 60) return '$min min';
    return '${min ~/ 60}h${(min % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artisan = widget.artisan;
    final dist = _roadDistanceM ?? _haversineDist();
    final initialCenter = _destPos ?? const LatLng(14.6928, -17.4467);

    return GestureDetector(
      onTap: widget.onTrack,
      child: Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Mini-map ─────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 200,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.misonservice.app',
                      ),
                      if (_routePoints.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              color: primaryColor,
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (_destPos != null)
                            Marker(
                              point: _destPos!,
                              width: 36,
                              height: 44,
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.redAccent,
                                size: 36,
                                shadows: [Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
                              ),
                            ),
                          if (_artisanPos != null)
                            Marker(
                              point: _artisanPos!,
                              width: 34,
                              height: 34,
                              rotate: false,
                              child: Transform.rotate(
                                angle: _bearing * pi / 180,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: primaryColor,
                                    border: Border.all(color: Colors.white, width: 2.5),
                                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                                  ),
                                  child: const Icon(
                                    Icons.navigation_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                  // Badge LIVE / attente
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _artisanPos != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'LIVE',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                ),
                                SizedBox(width: 6),
                                Text('Localisation…', style: TextStyle(color: Colors.white, fontSize: 10)),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // ── Infos ouvrier (le suivi se lance via la barre du bas) ─────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryColor.withValues(alpha: 0.1),
                        border: Border.all(color: primaryColor.withValues(alpha: 0.2), width: 1.5),
                        image: artisan.profilePictureUrl != null
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(artisan.profilePictureUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: artisan.profilePictureUrl == null
                          ? Icon(Icons.person_rounded, color: primaryColor, size: 24)
                          : null,
                    ),
                    12.width,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(artisan.fullName, style: boldTextStyle(size: 16)),
                          4.height,
                          Row(
                            children: [
                              if (artisan.averageRating != null) ...[
                                Icon(Icons.star_rounded, size: 13, color: ratingBarColor),
                                3.width,
                                Text(artisan.rating.toStringAsFixed(1), style: secondaryTextStyle(size: 14)),
                                8.width,
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'En route',
                                  style: TextStyle(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Distance + ETA
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (dist != null)
                          Text(_fmtDist(dist), style: boldTextStyle(size: 16, color: primaryColor)),
                        if (_etaSeconds != null)
                          Text(_fmtEta(_etaSeconds!), style: secondaryTextStyle(size: 13, color: Colors.green.shade700)),
                        if (dist == null && _etaSeconds == null)
                          const SizedBox.shrink(),
                      ],
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
