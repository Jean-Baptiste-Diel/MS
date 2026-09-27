import 'package:booking_system_flutter/utils/order_invoice_pdf.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' show sin, cos, sqrt, atan2;

import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/utils/artisan_eta_tracker.dart';
import 'package:booking_system_flutter/component/app_empty_state.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/mison_cancel_order_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/component/artisan_arrival_eta.dart';
import 'package:booking_system_flutter/utils/artisan_arrival_reporter.dart';
import 'package:booking_system_flutter/component/mison_discreet_cancel_button.dart';
import 'package:booking_system_flutter/utils/route_eta.dart' show kArrivalRadiusMeters;
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/order_events.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:booking_system_flutter/utils/auto_refresh_mixin.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:booking_system_flutter/utils/firebase_messaging_utils.dart';
import 'package:latlong2/latlong.dart';

import 'package:booking_system_flutter/utils/mison_call_utils.dart';
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

class _MisonOrderDetailScreenState extends State<MisonOrderDetailScreen> with WidgetsBindingObserver, AutoRefreshMixin {
  late Future<MisonOrderDetailResponse> future;
  Timer? _locationTimer;
  Position? _artisanPosition;
  StreamSubscription<String?>? _orderEventsSub;
  Timer? _paymentPollTimer;
  bool _paymentLaunched = false;
  bool _paymentRequestInFlight = false;

  /// Un paiement est en cours (requête, app Wave/Orange ouverte ou vérification
  /// du statut) : le bouton "Payer" est désactivé pour éviter de payer deux fois.
  bool get _paymentVerifying => _paymentRequestInFlight || _paymentLaunched || _paymentPollTimer != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    init();
    if (appStore.userType == USER_TYPE_PROVIDER) _fetchArtisanPosition();
    // Statut de commande changé côté serveur (paiement confirmé, prestation
    // terminée par l'ouvrier…). orderId null = event sans id, on rafraîchit.
    startAutoRefresh();
    _orderEventsSub = OrderEvents.stream.listen((orderId) {
      if (orderId == null || orderId.isEmpty || orderId == widget.orderId) {
        _stopPaymentPolling();
        init();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    stopAutoRefresh();
    _locationTimer?.cancel();
    _paymentPollTimer?.cancel();
    _orderEventsSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Le client revient dans l'app après avoir payé via Wave/Orange Money
    // (app externe) : on rafraîchit le statut de la commande.
    if (state == AppLifecycleState.resumed) {
      init();
      if (mounted) setState(() {});
      if (_paymentLaunched) {
        _paymentLaunched = false;
        _startPaymentPolling();
      }
    }
  }

  void init() => future = getMisonOrderDetail(widget.orderId);

  /// Actualisation silencieuse du statut (acceptée, en route, arrivée…).
  @override
  Future<void> onAutoRefresh() async {
    final res = await getMisonOrderDetail(widget.orderId);
    if (mounted) setState(() => future = Future.value(res));
  }

  /// Le webhook Wave/Orange Money peut arriver au serveur quelques secondes
  /// après le retour dans l'app : on interroge le statut jusqu'à ce que le
  /// paiement soit pris en compte (max ~30 s).
  void _startPaymentPolling() {
    _stopPaymentPolling();
    int ticks = 0;
    _paymentPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (++ticks > 10 || !mounted) return _stopPaymentPolling();
      try {
        final res = await getMisonOrderDetail(widget.orderId);
        if (!mounted || _paymentPollTimer == null) return;
        if (res.data != null && !res.data!.isAwaitingAnyPayment) {
          _stopPaymentPolling();
          setState(() => future = Future.value(res));
        }
      } catch (e) {
        log('[PaymentPolling] $e');
      }
    });
  }

  void _stopPaymentPolling() {
    final wasPolling = _paymentPollTimer != null;
    _paymentPollTimer?.cancel();
    _paymentPollTimer = null;
    // Réactive le bouton "Payer" si la commande est toujours en attente.
    if (wasPolling && mounted) setState(() {});
  }

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

  /// Facture PDF générée dans l'app et enregistrée sur le téléphone.
  Future<void> _downloadInvoice(MisonOrder order) async {
    appStore.setLoading(true);
    try {
      final where = await downloadOrderInvoice(order);
      TopToast.show(message: 'Facture enregistrée dans $where', type: TopToastType.success);
    } catch (e) {
      TopToast.show(message: 'Impossible de générer la facture.', type: TopToastType.error);
    } finally {
      appStore.setLoading(false);
    }
  }

  // ── Trajet de l'ouvrier : « Aller chez le client » → arrivée ────────────────

  void _openNavigation(MisonOrder order) {
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
  }

  /// Signale le départ au serveur (mini-carte des deux côtés, client prévenu),
  /// puis ouvre la navigation. Déjà en route : rouvre simplement la navigation.
  Future<void> _departTo(MisonOrder order) async {
    if (!order.isEnRoute) {
      appStore.setLoading(true);
      try {
        await artisanDepart(order.id!);
      } catch (e) {
        TopToast.show(message: e.toString(), type: TopToastType.error);
        return;
      } finally {
        appStore.setLoading(false);
      }
      init();
      if (mounted) setState(() {});
    }
    if (mounted) _openNavigation(order);
  }

  /// « Je suis arrivé » : au cas où le GPS n'a pas détecté l'arrivée.
  Future<void> _markArrived(MisonOrder order) async {
    appStore.setLoading(true);
    final ok = await ArtisanArrivalReporter.markArrived(order.id!);
    appStore.setLoading(false);
    if (!ok) TopToast.show(message: "Impossible de signaler l'arrivée, réessayez.", type: TopToastType.error);
    init();
    if (mounted) setState(() {});
  }

  // ── Tracking GPS artisan → Firestore ────────────────────────────────────────

  Future<void> _startTracking(MisonOrder order) async {
    if (_locationTimer != null) return;
    final orderId = order.id!;

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
        // Arrivé à l'adresse : bascule sur « Commencer la prestation »
        ArtisanArrivalReporter.check(
          orderId: orderId,
          destLat: double.tryParse(order.latitude ?? ''),
          destLng: double.tryParse(order.longitude ?? ''),
          position: pos,
        );
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
      case 'PENDING':                      return kMisonGold;
      case 'ASSIGNED':                     return kMisonGold;
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
    switch (s) {
      case 'PENDING':                      return 'Recherche d\'ouvrier';
      case 'ASSIGNED':                     return 'Ouvrier proposé';
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

  /// Confirmation aux couleurs Mison (rouge pour une action destructive).
  Future<void> _confirm({
    required String title,
    required String subtitle,
    required VoidCallback onConfirm,
    DialogType type = DialogType.CONFIRMATION,
  }) async {
    final danger = type == DialogType.DELETE;
    final ok = await showMisonConfirmSheet(
      context,
      title: title,
      subtitle: subtitle,
      icon: danger ? Icons.event_busy_rounded : Icons.check_circle_outline_rounded,
      danger: danger,
    );
    if (ok) onConfirm();
  }


  void _showPaymentModal(MisonOrder order) {
    if (_paymentVerifying) {
      TopToast.show(message: 'Paiement en cours de vérification, patientez quelques secondes.');
      return;
    }
    const title = 'Frais de prestation';
    final total = order.clientTotal;
    final price = order.prestationPrice;
    final desc = price != null
        ? 'Prestation ${formatFcfa(price)} + frais de service ${formatFcfa(order.serviceFee)}.'
        : "Ces frais correspondent à la prestation réalisée par l'ouvrier.";
    final feeLabel = total != null ? formatFcfa(total) : 'Montant non défini';

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
          if (_paymentVerifying) return;
          setState(() => _paymentRequestInFlight = true);
          appStore.setLoading(true);
          try {
            final res = await paymentCheckout(order.id ?? '');
            if (res.waveLaunchUrl != null && res.waveLaunchUrl!.isNotEmpty) {
              _paymentLaunched = true;
              await launchUrl(Uri.parse(res.waveLaunchUrl!), mode: LaunchMode.externalApplication);
            } else {
              TopToast.show(message: res.message ?? 'Paiement Wave initié');
            }
            init(); setState(() {});
          } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
          finally {
            appStore.setLoading(false);
            if (mounted) setState(() => _paymentRequestInFlight = false);
          }
        },
        onPayOrange: () async {
          Navigator.pop(context);
          if (_paymentVerifying) return;
          setState(() => _paymentRequestInFlight = true);
          appStore.setLoading(true);
          try {
            final res = await paymentCheckoutOrange(order.id ?? '');
            if (res.deeplink != null && res.deeplink!.isNotEmpty) {
              _paymentLaunched = true;
              await launchUrl(Uri.parse(res.deeplink!), mode: LaunchMode.externalApplication);
            } else {
              TopToast.show(message: res.message ?? 'Paiement Orange Money initié');
            }
            init(); setState(() {});
          } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
          finally {
            appStore.setLoading(false);
            if (mounted) setState(() => _paymentRequestInFlight = false);
          }
        },
      ),
    );
  }

  Future<void> _startCall(MisonOrder order) async {
    final otherName = appStore.userType == USER_TYPE_PROVIDER
        ? order.client != null
            ? '${order.client!.firstName ?? ''} ${order.client!.lastName ?? ''}'.trim()
            : 'Client'
        : order.artisan?.fullName ?? 'Ouvrier';
    await startMisonOrderCall(context, orderId: order.id!, otherPartyName: otherName);
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
            loadingWidget: Center(child: LoaderWidget(colors: const [kMisonDark, kMisonGold])),
            errorBuilder: (error) => isNotFoundError(error)
                // Commande d'un autre compte, ou prise par un autre artisan :
                // réessayer ne servirait à rien, on propose de revenir.
                ? AppEmptyState(
                    type: AppEmptyStateType.empty,
                    title: kOrderUnavailableMessage,
                    subtitle: 'Elle a peut-être été prise par un autre ouvrier, annulée, '
                        'ou appartient à un autre compte.',
                    retryLabel: 'Retour',
                    onRetry: () => Navigator.of(context).maybePop(),
                  )
                : AppEmptyState(
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
                  _startTracking(order);
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
                  title: 'Commencer la prestation',
                  subtitle: 'Vous êtes chez le client : confirmez le début de la prestation.',
                  onConfirm: () => _startOrder(order.id!),
                ),
                onChat: () => _openChat(order),
                onSetRealizationFee: () => _showSetFeeModal(
                  title: 'Frais de prestation',
                  apiCall: (amount) => setRealizationFee(order.id!, amount),
                ),
                // Client : panneau d'annulation Mison (motif, chargement) ;
                // ouvrier : confirmation de désistement inchangée
                onCancel: appStore.userType == USER_TYPE_PROVIDER
                    ? () => _confirm(
                          title: 'Se désister de la commande',
                          subtitle: 'La commande sera reproposée aux autres ouvriers. Confirmez-vous ?',
                          type: DialogType.DELETE,
                          onConfirm: () => _cancelOrder(order.id!),
                        )
                    : () async {
                        final cancelled = await showMisonCancelOrderSheet(context, orderId: order.id!);
                        if (cancelled && mounted) {
                          init();
                          setState(() {});
                        }
                      },
                onPay: () => _showPaymentModal(order),
                paymentVerifying: _paymentVerifying,
                onRated: () { init(); setState(() {}); },
                onDownloadInvoice: () => _downloadInvoice(order),
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
                onNavigate: () => _openNavigation(order),
                onDepart: () => _departTo(order),
                onArrive: () => _markArrived(order),
              );
            },
          ),
          Observer(builder: (_) => LoaderWidget(colors: const [kMisonDark, kMisonGold]).visible(appStore.isLoading)),
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
  final bool paymentVerifying;
  final VoidCallback onRated;
  final VoidCallback onDownloadInvoice;
  final VoidCallback onCall;
  final VoidCallback onTrack;
  final VoidCallback onNavigate;
  final VoidCallback onDepart;
  final VoidCallback onArrive;

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
    this.paymentVerifying = false,
    required this.onRated,
    required this.onDownloadInvoice,
    required this.onCall,
    required this.onTrack,
    required this.onNavigate,
    required this.onDepart,
    required this.onArrive,
  });

  bool get _isArtisan => appStore.userType == USER_TYPE_PROVIDER;
  bool get _isClient  => !_isArtisan;

  bool get _showPayButton =>
      _isClient && order.isAwaitingAnyPayment;

  /// Client, prestation en cours : le bouton « Payer » est déjà là, mais
  /// inutilisable tant que l'ouvrier n'a pas terminé (et fixé ses frais).
  bool get _showPayLocked => _isClient && order.isInProgress;

  /// Prestataire, frais de prestation fixés (paiement en attente ou fait) :
  /// récapitulatif seulement (prix, client, prestation, paiement, adresse).
  bool get _artisanSummary =>
      _isArtisan && (order.isAwaitingRealizationPayment || order.isCompleted);

  bool get _canCancel =>
      _isArtisan ? order.canReleaseByArtisan : order.canCancelByClient;

  @override
  Widget build(BuildContext context) {
    final sColor = statusColor(order.status);
    // Récapitulatif prestataire : plus d'appel ni de message
    final showBottomCall = order.canCall && !_artisanSummary;
    // Client : l'annulation prend la place de « Suivre en direct » (déplacé
    // dans la carte de l'ouvrier, après le statut « En route »).
    final showClientCancel = _isClient && _canCancel;
    final showAcceptButton = _isArtisan &&
        ((order.isPending && order.artisan == null) || order.needsArtisanConfirmation);
    // Ouvrier : « Aller chez le client » tant qu'il n'est pas arrivé, puis
    // « Commencer la prestation » une fois sur place.
    final showGoButton = _isArtisan && order.isBeforeStart && !order.needsArtisanConfirmation && !order.hasArrived;
    final showStartButton = _isArtisan && order.hasArrived && !order.needsArtisanConfirmation;
    final showSetFeeButton = _isArtisan && order.artisan != null && order.isInProgress;
    final showPrimaryAction = showAcceptButton || showGoButton || showStartButton || showSetFeeButton || _showPayButton || _showPayLocked;
    final showBottomBar = showBottomCall || showPrimaryAction || showClientCancel;

    late final String primaryActionLabel;
    late final IconData primaryActionIcon;
    late final Color primaryActionColor;
    late final VoidCallback primaryActionTap;
    if (showAcceptButton) {
      primaryActionLabel = order.needsArtisanConfirmation ? 'Confirmer cette commande' : 'Accepter cette commande';
      primaryActionIcon = Icons.check_circle_outline_rounded;
      primaryActionColor = kMisonGold; // Accepter / Confirmer en doré
      primaryActionTap = onAccept;
    } else if (showGoButton) {
      primaryActionLabel = 'Aller chez le client';
      primaryActionIcon = Icons.directions_car_rounded;
      primaryActionColor = kMisonGold;
      primaryActionTap = onDepart;
    } else if (showStartButton) {
      primaryActionLabel = 'Commencer la prestation';
      primaryActionIcon = Icons.play_circle_outline_rounded;
      primaryActionColor = Colors.green;
      primaryActionTap = onStart;
    } else if (showSetFeeButton) {
      primaryActionLabel = 'Définir les frais de prestation';
      primaryActionIcon = Icons.receipt_long_rounded;
      primaryActionColor = completed;
      primaryActionTap = onSetRealizationFee;
    } else if (_showPayLocked) {
      primaryActionLabel = 'Payer la prestation';
      primaryActionIcon = Icons.lock_clock_rounded;
      primaryActionColor = Colors.grey.shade400;
      primaryActionTap = () => TopToast.show(
            message: 'Le paiement sera possible dès la fin de la prestation.',
          );
    } else if (_showPayButton && paymentVerifying) {
      primaryActionLabel = 'Vérification du paiement…';
      primaryActionIcon = Icons.hourglass_top_rounded;
      primaryActionColor = Colors.grey;
      primaryActionTap = onPay; // affiche seulement "patientez", n'ouvre pas le paiement
    } else if (_showPayButton) {
      primaryActionLabel = 'Payer la prestation';
      primaryActionIcon = Icons.payment_rounded;
      primaryActionColor = kMisonGold;
      primaryActionTap = onPay;
    }

    return Stack(
      children: [
      CustomScrollView(
      slivers: [
        // ── En-tête : logo centré sur le fond de la page (fixe) ─────────────
        SliverAppBar(
          pinned: true,
          backgroundColor: kMisonHeaderBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          toolbarHeight: 84,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: kMisonDark),
            onPressed: () => Navigator.pop(context),
          ),
          title: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Image.asset('assets/logo/logo_transparent.png', height: 58),
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
                    _ArtisanHeroCard(
                      artisan: order.artisan!,
                      statusColor: sColor,
                      statusLabel: statusLabel(order.status),
                      serviceName: order.service?.name ?? '',
                    ),
                  20.height,
                ],

                // ── Client : récapitulatif (prix, prestation, mode de paiement)
                // une fois les frais de prestation fixés ──────────────────────
                if (_isClient && (order.isAwaitingRealizationPayment || order.isCompleted)) ...[
                  _ArtisanSummaryCard(order: order, forClient: true),
                  20.height,
                ],




                // ── Prestataire en déplacement : carte comme chez le client, avec
                // les infos du client ; un appui ouvre la navigation ────────────
                if (_isArtisan && order.canTrack) ...[
                  _LiveTrackingCard(
                    order: order,
                    artisan: order.artisan ?? MisonArtisanInfo(),
                    onTrack: onNavigate,
                    forArtisan: true,
                  ),
                  // Si le GPS ne détecte pas l'arrivée
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onArrive,
                      icon: const Icon(Icons.where_to_vote_rounded, size: 18, color: kMisonGold),
                      label: Text('Je suis arrivé', style: boldTextStyle(size: 13, color: kMisonGold)),
                    ),
                  ),
                  8.height,
                ] else if (_artisanSummary) ...[
                  // Frais fixés : plus de carte ni d'appel/chat, un récapitulatif
                  _ArtisanSummaryCard(order: order),
                  16.height,
                ] else if (_isArtisan && order.client != null) ...[
                  // Infos du client, comme la carte de l'ouvrier chez le client
                  _ClientHeroCard(
                    order: order,
                    statusColor: sColor,
                    statusLabel: statusLabel(order.status),
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
                        color: kMisonGold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kMisonGold.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.assignment_ind_rounded, size: 18, color: kMisonGold),
                          8.width,
                          Expanded(
                            child: Text(
                              'Cette commande vous a été affectée par Mison. Confirmez-la pour la démarrer.',
                              style: secondaryTextStyle(size: 14, color: kMisonGold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                // ── Infos commande (le récapitulatif prestataire les contient déjà)
                if (!_artisanSummary) _InfoCard(children: [
                  _InfoRow(icon: Icons.calendar_today_rounded, label: 'Date', value: fmtDate(order.serviceDate)),
                  // Pas d'heure pour une prestation demandée « tout de suite »
                  if (_isClient && _ArrivalRow.isShown(order)) ...[
                    _Divider(),
                    _ArrivalRow(order: order, fmtTime: fmtTime),
                  ] else if (_isArtisan && !order.isImmediate) ...[
                    _Divider(),
                    _InfoRow(icon: Icons.access_time_rounded, label: 'Heure', value: fmtTime(order.serviceDate)),
                  ],
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

                if (!_artisanSummary && order.description != null && order.description!.isNotEmpty) ...[
                  16.height,
                  _InfoCard(children: [
                    _InfoRow(icon: Icons.notes_rounded, label: 'Description', value: order.description!),
                  ]),
                ],

                // ── Désistement — ouvrier (le client annule depuis la barre du bas)
                if (_isArtisan && _canCancel) ...[
                  16.height,
                  // Désistement discret, même style que l'annulation côté client
                  MisonDiscreetCancelButton(
                    label: 'Se désister de la commande',
                    onTap: onCancel,
                    expanded: true,
                  ),
                  8.height,
                  Text(
                    'La commande sera reproposée aux autres ouvriers du service.',
                    style: secondaryTextStyle(size: 12, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ).center(),
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

                // ── Prestation terminée : facture PDF (client et prestataire) ────
                if (order.isCompleted) ...[
                  16.height,
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: onDownloadInvoice,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kMisonGold,
                        side: const BorderSide(color: kMisonGold, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        'Télécharger la facture',
                        style: boldTextStyle(size: 15, color: kMisonGold),
                      ),
                    ),
                  ),
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
                // Client : annulation discrète (même style que « Mes commandes »),
                // à la place de l'ancien bouton « Suivre en direct ».
                if (showClientCancel && !showPrimaryAction) ...[
                  Expanded(
                    child: MisonDiscreetCancelButton(
                      label: 'Annuler la commande',
                      onTap: onCancel,
                      expanded: true,
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
                        side: const BorderSide(color: kMisonGold, width: 1.5),
                      ),
                      onTap: onCall,
                      // Bouton appel : bordure et icône dorées
                      child: const Icon(Icons.call_rounded, color: kMisonGold, size: 20),
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
                        color: kMisonGold,
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

/// Photo de profil de l'ouvrier dans un rond doré. Si le lien est vide ou
/// que l'image ne se charge pas (lien expiré, réseau), affiche une icône.
class _ArtisanAvatar extends StatelessWidget {
  final String? url;
  final double size;
  const _ArtisanAvatar({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.person_rounded, color: kMisonGold, size: size * 0.5);
    final hasUrl = url != null && url!.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kMisonGold.withValues(alpha: 0.1),
        border: Border.all(color: kMisonGold.withValues(alpha: 0.35), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? CachedNetworkImage(
              imageUrl: url!.trim(),
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_, __) => Center(
                child: SizedBox(
                  width: size * 0.35,
                  height: size * 0.35,
                  child: const CircularProgressIndicator(strokeWidth: 2, color: kMisonGold),
                ),
              ),
              errorWidget: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }
}

/// Carte du client vue par le prestataire : statut, nom, service, adresse.
class _ClientHeroCard extends StatelessWidget {
  final MisonOrder order;
  final Color statusColor;
  final String statusLabel;

  const _ClientHeroCard({required this.order, required this.statusColor, required this.statusLabel});

  @override
  Widget build(BuildContext context) {
    final client = order.client;
    final name = (client?.fullName ?? '').isNotEmpty ? client!.fullName : 'Client';
    final service = order.service?.name ?? '';
    final address = order.serviceAddress ?? '';

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
          // ── Bandeau statut
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

          // ── Client
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ArtisanAvatar(url: null, size: 64),
                16.width,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Client', style: secondaryTextStyle(size: 12)),
                      2.height,
                      Text(name, style: boldTextStyle(size: 20), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (service.isNotEmpty) ...[
                        3.height,
                        Text(service,
                            style: boldTextStyle(size: 13, color: kMisonGold),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      if (address.isNotEmpty) ...[
                        6.height,
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                            4.width,
                            Expanded(
                              child: Text(address,
                                  style: secondaryTextStyle(size: 14),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
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
        ],
      ),
    );
  }
}

class _ArtisanHeroCard extends StatelessWidget {
  final MisonArtisanInfo artisan;
  final Color statusColor;
  final String statusLabel;
  final String serviceName;

  const _ArtisanHeroCard({
    required this.artisan,
    required this.statusColor,
    required this.statusLabel,
    this.serviceName = '',
  });

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
                // Photo de profil de l'ouvrier
                _ArtisanAvatar(url: artisan.profilePictureUrl, size: 64),
                16.width,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nom de l'ouvrier en premier, puis le service
                      Text(artisan.fullName,
                          style: boldTextStyle(size: 20),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (serviceName.isNotEmpty) ...[
                        3.height,
                        Text(serviceName,
                            style: boldTextStyle(size: 13, color: kMisonGold),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
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
  final Widget? valueWidget;
  const _InfoRow({required this.icon, required this.label, this.value = '', this.valueWidget});

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
              color: kMisonGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kMisonGold, size: 18),
          ),
          12.width,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: secondaryTextStyle(size: 14)),
                4.height,
                valueWidget ?? Text(value, style: boldTextStyle(size: 16), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Côté client, à la place de l'heure prévue : où en est l'ouvrier.
/// Recherche en cours → heure d'arrivée en direct (comme Google Maps) → sur place.
class _ArrivalRow extends StatelessWidget {
  final MisonOrder order;
  final String Function(String?) fmtTime;
  const _ArrivalRow({required this.order, required this.fmtTime});

  /// Faux quand la ligne n'afficherait que l'heure d'une prestation « tout de suite ».
  static bool isShown(MisonOrder order) {
    final showsStatus = order.isPending ||
        order.isAssigned ||
        order.isAccepted ||
        order.isAwaitingTravelPayment ||
        order.isInProgress ||
        order.isAwaitingRealizationPayment ||
        order.isCompleted;
    return showsStatus || !order.isImmediate;
  }

  @override
  Widget build(BuildContext context) {
    const icon = Icons.access_time_rounded;
    if (order.isPending) {
      return const _InfoRow(icon: icon, label: 'Ouvrier', value: "Recherche d'un ouvrier en cours…");
    }
    // Trajet de l'ouvrier : pas encore parti → en route (heure d'arrivée) → arrivé
    if (order.hasArrived) {
      return const _InfoRow(icon: Icons.where_to_vote_rounded, label: 'Ouvrier', value: 'Arrivé chez vous');
    }
    if (order.isBeforeStart && !order.isEnRoute) {
      return _InfoRow(
        icon: icon,
        label: 'Ouvrier',
        value: order.isImmediate
            ? 'Ouvrier trouvé · il va bientôt partir'
            : 'Ouvrier trouvé · prévu à ${fmtTime(order.serviceDate)}',
      );
    }
    if (order.isEnRoute) {
      final lat = double.tryParse(order.latitude ?? '');
      final lng = double.tryParse(order.longitude ?? '');
      return _InfoRow(
        icon: Icons.directions_car_rounded,
        label: "Arrivée de l'ouvrier",
        valueWidget: ArtisanArrivalEta(
          orderId: order.id!,
          destination: (lat != null && lng != null) ? gmaps.LatLng(lat, lng) : null,
          // Position pas encore reçue : pour une commande programmée, l'heure
          // prévue reste la meilleure indication.
          fallback: order.isImmediate
              ? "Ouvrier trouvé · calcul de l'arrivée…"
              : 'Prévue à ${fmtTime(order.serviceDate)}',
        ),
      );
    }
    if (order.isInProgress || order.isAwaitingRealizationPayment) {
      return const _InfoRow(icon: icon, label: 'Ouvrier', value: 'Sur place');
    }
    if (order.isCompleted) {
      return const _InfoRow(icon: icon, label: 'Ouvrier', value: 'Prestation terminée');
    }
    return _InfoRow(icon: icon, label: 'Heure', value: fmtTime(order.serviceDate));
  }
}

/// « 10 100 FCFA »
String formatFcfa(num value) {
  final digits = value.toStringAsFixed(0);
  return '${digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} FCFA';
}

/// Récapitulatif une fois les frais de prestation fixés.
/// Prestataire : prix, client, prestation, paiement, adresse.
/// Client : prix, prestation, mode de paiement.
class _ArtisanSummaryCard extends StatelessWidget {
  final MisonOrder order;
  final bool forClient;
  const _ArtisanSummaryCard({required this.order, this.forClient = false});

  String _fcfa(int? value) => value == null ? '—' : formatFcfa(value);

  @override
  Widget build(BuildContext context) {
    final client = order.client?.fullName ?? '';
    return _InfoCard(children: [
      _InfoRow(icon: Icons.payments_rounded, label: 'Prix de la prestation', value: _fcfa(order.prestationPrice)),
      // Client : il paie la prestation + les frais de service Mison.
      if (forClient) ...[
        _Divider(),
        _InfoRow(icon: Icons.receipt_rounded, label: 'Frais de service', value: _fcfa(order.serviceFee)),
        _Divider(),
        _InfoRow(
          icon: Icons.account_balance_rounded,
          label: order.isCompleted ? 'Total payé' : 'Total à payer',
          value: _fcfa(order.clientTotal),
        ),
      ],
      if (!forClient) ...[
        _Divider(),
        _InfoRow(icon: Icons.person_rounded, label: 'Client', value: client.isNotEmpty ? client : '—'),
      ],
      _Divider(),
      _InfoRow(icon: Icons.handyman_rounded, label: 'Prestation', value: order.service?.name ?? '—'),
      _Divider(),
      _InfoRow(
        icon: Icons.account_balance_wallet_rounded,
        label: forClient ? 'Mode de paiement' : 'Paiement',
        // Client, pas encore payé : formulé pour lui (seul Wave pour le moment)
        value: forClient && order.paymentMethod == null && !order.isCompleted
            ? 'Wave · à régler'
            : order.paymentMethodLabel,
      ),
      if (!forClient && (order.serviceAddress ?? '').isNotEmpty) ...[
        _Divider(),
        _InfoRow(icon: Icons.location_on_rounded, label: 'Adresse', value: order.serviceAddress!),
      ],
    ]);
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
                icon: Icon(Icons.check_circle_outline, color: kMisonGold),
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
                borderSide: BorderSide(color: kMisonGold, width: 1.5),
              ),
            ),
          ),
          20.height,
          AppButton(
            text: 'Confirmer',
            color: kMisonGold,
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
              color: kMisonGold.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kMisonGold.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.desc, style: secondaryTextStyle(size: 14)),
                8.height,
                Text(widget.feeLabel,
                    style: boldTextStyle(size: 20, color: kMisonGold)),
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

  /// Vue du prestataire : la carte montre le client (nom, service) au lieu de
  /// l'ouvrier, et pas d'alertes « l'ouvrier approche ».
  final bool forArtisan;

  const _LiveTrackingCard({
    required this.order,
    required this.artisan,
    required this.onTrack,
    this.forArtisan = false,
  });

  @override
  State<_LiveTrackingCard> createState() => _LiveTrackingCardState();
}

class _LiveTrackingCardState extends State<_LiveTrackingCard> {
  gmaps.GoogleMapController? _mapController;
  gmaps.BitmapDescriptor? _artisanIcon;
  LatLng? _artisanPos;
  LatLng? _destPos;
  double _bearing = 0;
  StreamSubscription<DocumentSnapshot>? _sub;

  // Route OSRM
  List<LatLng> _routePoints    = [];
  double?      _roadDistanceM;
  // Suivi partagé avec la ligne « Arrivée de l'ouvrier » : un seul calcul
  // Google Directions (trafic compris)
  ArtisanEtaTracker? _etaTracker;

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
    _buildArtisanIcon();
    _etaTracker = ArtisanEtaTracker.acquire(
      widget.order.id!,
      _destPos != null ? gmaps.LatLng(_destPos!.latitude, _destPos!.longitude) : null,
    )..addListener(_onEtaUpdate);

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

  /// Nouveau calcul Google Directions : tracé, distance, durée, heure d'arrivée.
  void _onEtaUpdate() {
    final eta = _etaTracker?.eta;
    if (eta == null || !mounted) return;
    setState(() {
      _routePoints   = eta.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
      _roadDistanceM = eta.distanceMeters > 0 ? eta.distanceMeters.toDouble() : null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
    _checkNearby();
  }

  void _checkNearby() {
    if (widget.forArtisan) return; // alertes destinées au client
    if (_destPos == null || _artisanPos == null) return;
    final dist = _roadDistanceM ?? _haversineDist();
    if (dist == null) return;

    final isArrived = dist <= kArrivalRadiusMeters;
    final isNearby  = dist < 500;

    if (_hadFirstUpdate) {
      if (isArrived && !_arrivedAlertShown) {
        // La notification « arrivé » est envoyée par le serveur (arrivée signalée
        // par l'ouvrier) : ne pas en créer une seconde ici.
        _arrivedAlertShown = true;
        _nearbyAlertShown  = true;
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

  gmaps.LatLng _g(LatLng p) => gmaps.LatLng(p.latitude, p.longitude);

  /// Point doré de l'ouvrier avec une flèche blanche (orientée via `rotation`).
  Future<void> _buildArtisanIcon() async {
    const double size = 96; // pixels, rendu net sur écrans haute densité
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    canvas.drawCircle(center, size / 2 - 4, Paint()..color = Colors.black26);
    canvas.drawCircle(center, size / 2 - 8, Paint()..color = Colors.white);
    canvas.drawCircle(center, size / 2 - 15, Paint()..color = kMisonGold);
    final arrow = ui.Path()
      ..moveTo(size / 2, size * 0.26)
      ..lineTo(size * 0.68, size * 0.70)
      ..lineTo(size / 2, size * 0.60)
      ..lineTo(size * 0.32, size * 0.70)
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null || !mounted) return;
    setState(() {
      _artisanIcon = gmaps.BitmapDescriptor.bytes(bytes.buffer.asUint8List(), width: 34, height: 34);
    });
  }

  void _fitMap() {
    final controller = _mapController;
    if (controller == null) return;
    final points = [
      if (_routePoints.isNotEmpty) ..._routePoints
      else ...[if (_artisanPos != null) _artisanPos!, if (_destPos != null) _destPos!],
    ];
    if (points.isEmpty) return;
    try {
      if (points.length == 1) {
        controller.animateCamera(gmaps.CameraUpdate.newLatLngZoom(_g(points.first), 14));
      } else {
        double minLat = points.first.latitude, maxLat = points.first.latitude;
        double minLng = points.first.longitude, maxLng = points.first.longitude;
        for (final p in points) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }
        controller.animateCamera(gmaps.CameraUpdate.newLatLngBounds(
          gmaps.LatLngBounds(
            southwest: gmaps.LatLng(minLat, minLng),
            northeast: gmaps.LatLng(maxLat, maxLng),
          ),
          40,
        ));
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

  @override
  void dispose() {
    _etaTracker?.removeListener(_onEtaUpdate);
    _etaTracker?.release();
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
                  // Google Maps (au lieu d'OpenStreetMap), carte non interactive
                  gmaps.GoogleMap(
                    initialCameraPosition: gmaps.CameraPosition(target: _g(initialCenter), zoom: 14),
                    onMapCreated: (c) {
                      _mapController = c;
                      WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
                    },
                    zoomGesturesEnabled: false,
                    scrollGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                    polylines: {
                      if (_routePoints.isNotEmpty)
                        gmaps.Polyline(
                          polylineId: const gmaps.PolylineId('route'),
                          points: _routePoints.map(_g).toList(),
                          color: kMisonGold,
                          width: 4,
                        ),
                    },
                    markers: {
                      if (_destPos != null)
                        gmaps.Marker(
                          markerId: const gmaps.MarkerId('destination'),
                          position: _g(_destPos!),
                        ),
                      if (_artisanPos != null)
                        gmaps.Marker(
                          markerId: const gmaps.MarkerId('artisan'),
                          position: _g(_artisanPos!),
                          icon: _artisanIcon ?? gmaps.BitmapDescriptor.defaultMarkerWithHue(45),
                          rotation: _artisanIcon != null ? _bearing : 0,
                          anchor: const Offset(0.5, 0.5),
                          flat: true,
                          zIndexInt: 2,
                        ),
                    },
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

          // ── Infos ouvrier (le suivi se lance via le bouton en pied de carte) ─
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Photo de l'ouvrier (vue client) ; le client n'a pas de photo
                    _ArtisanAvatar(url: widget.forArtisan ? null : artisan.profilePictureUrl, size: 50),
                    12.width,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nom (ouvrier côté client, client côté prestataire), puis le service
                          if (widget.forArtisan) ...[
                            // Prestataire : « Client : Nom » et « Prestation : Service »
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: 'Client : ', style: secondaryTextStyle(size: 14)),
                                TextSpan(
                                  text: (widget.order.client?.fullName ?? '').isNotEmpty
                                      ? widget.order.client!.fullName
                                      : '—',
                                  style: boldTextStyle(size: 17),
                                ),
                              ]),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                            if ((widget.order.service?.name ?? '').isNotEmpty) ...[
                              3.height,
                              Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: 'Prestation : ', style: secondaryTextStyle(size: 14)),
                                  TextSpan(
                                    text: widget.order.service!.name!,
                                    style: boldTextStyle(size: 14, color: kMisonGold),
                                  ),
                                ]),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ] else ...[
                            Text(artisan.fullName,
                                style: boldTextStyle(size: 19),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if ((widget.order.service?.name ?? '').isNotEmpty) ...[
                              2.height,
                              Text(widget.order.service!.name!,
                                  style: boldTextStyle(size: 13, color: kMisonGold),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ],
                          // Adresse du client (vue prestataire)
                          if (widget.forArtisan && (widget.order.serviceAddress ?? '').isNotEmpty) ...[
                            2.height,
                            Row(children: [
                              const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                              3.width,
                              Expanded(
                                child: Text(widget.order.serviceAddress!,
                                    style: secondaryTextStyle(size: 13),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                          ],
                          4.height,
                          Row(
                            children: [
                              if (!widget.forArtisan && artisan.averageRating != null) ...[
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
                                  widget.forArtisan ? 'Vous êtes en route' : 'En route',
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
                          Text(_fmtDist(dist), style: boldTextStyle(size: 16, color: kMisonGold)),
                        // Le temps d'arrivée est affiché une seule fois,
                        // dans la ligne « Arrivée de l'ouvrier » plus bas
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── Client : « Suivre en direct » en pied de carte, pleine largeur,
          // collé aux bords (juste sous les infos du prestataire) ─────────────
          if (!widget.forArtisan)
            Material(
              color: kMisonGold,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTrack,
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.open_in_full_rounded, size: 18, color: Colors.white),
                      8.width,
                      Text('Suivre en direct', style: boldTextStyle(size: 15, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }
}
