import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:booking_system_flutter/utils/step_sheets.dart';
import 'package:booking_system_flutter/utils/remote_media.dart';
import 'package:booking_system_flutter/utils/feature_flags.dart';
import 'package:booking_system_flutter/component/mison_rate_sheet.dart';
import 'package:booking_system_flutter/screens/booking/mison_artisan_reviews_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/component/mison_start_prestation_sheet.dart';
import 'package:booking_system_flutter/utils/image_cache_key.dart';
import 'package:booking_system_flutter/component/mison_receipt_sheet.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_searching_screen.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' show sin, cos, sqrt, atan2;

import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/component/mison_price_agreement_card.dart';
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

import 'package:booking_system_flutter/component/mison_audio_sheet.dart';
import 'package:booking_system_flutter/component/mison_price_validation_sheet.dart';
import 'package:booking_system_flutter/component/mandatory_audio_dialog.dart' show isAfterAcceptAudioOpen;
import 'package:booking_system_flutter/screens/support_chat/voice_note_player.dart';
import 'package:booking_system_flutter/utils/mison_call_utils.dart';
import '../chat/mison_order_chat_screen.dart';
import '../map/mison_artisan_navigation_screen.dart';
import '../map/mison_tracking_screen.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class MisonOrderDetailScreen extends StatefulWidget {
  final String orderId;
  final double? distanceKm;
  const MisonOrderDetailScreen({Key? key, required this.orderId, this.distanceKm}) : super(key: key);

  /// Commandes dont la page est ouverte (pour ne pas en rouvrir une seconde
  /// au retour de Wave / Orange Money).
  static final Map<String, int> _open = {};
  static bool isOpen(String orderId) => (_open[orderId] ?? 0) > 0;

  /// Ouvre la commande, sauf si elle est déjà à l'écran (ou sous un autre
  /// écran) : jamais deux pages de la même commande empilées — il fallait
  /// sinon faire « retour » deux fois pour la quitter. Déjà ouverte : elle se
  /// met à jour d'elle-même (notifications, retour de paiement).
  static Future<void> openOnce(NavigatorState? navigator, String orderId) async {
    if (navigator == null || orderId.isEmpty || isOpen(orderId)) return;
    await navigator.push(MaterialPageRoute(builder: (_) => MisonOrderDetailScreen(orderId: orderId)));
  }

  static final StreamController<(String, bool)> _paymentReturns = StreamController<(String, bool)>.broadcast();

  /// Retour dans l'app après un paiement : la page ouverte vérifie le statut
  /// jusqu'à ce que le paiement soit confirmé ; paiement annulé : le bouton
  /// « Payer » redevient utilisable tout de suite.
  static void notifyPaymentReturn(String orderId, {required bool success}) =>
      _paymentReturns.add((orderId, success));

  @override
  State<MisonOrderDetailScreen> createState() => _MisonOrderDetailScreenState();
}

class _MisonOrderDetailScreenState extends State<MisonOrderDetailScreen> with WidgetsBindingObserver, AutoRefreshMixin {
  late Future<MisonOrderDetailResponse> future;
  Timer? _locationTimer;
  Position? _artisanPosition;
  StreamSubscription<String?>? _orderEventsSub;
  StreamSubscription<(String, bool)>? _paymentReturnSub;
  Timer? _paymentPollTimer;
  bool _paymentLaunchedFlag = false;
  Timer? _paymentLaunchTimeout;

  /// App Wave / Orange Money ouverte pour payer. Délai de sécurité : si le
  /// retour dans l'app n'est pas détecté, l'état « vérification » s'arrête
  /// tout seul au bout de 2 minutes et le bouton « Payer » revient.
  bool get _paymentLaunched => _paymentLaunchedFlag;
  set _paymentLaunched(bool value) {
    _paymentLaunchedFlag = value;
    _paymentLaunchTimeout?.cancel();
    _paymentLaunchTimeout = null;
    if (value) {
      _paymentLaunchTimeout = Timer(const Duration(minutes: 2), () {
        if (!mounted || !_paymentLaunchedFlag) return;
        _paymentLaunchedFlag = false;
        _startPaymentPolling();
        setState(() {});
      });
    }
  }
  bool _paymentRequestInFlight = false;

  /// Vérifications du statut depuis le retour dans l'app.
  int _paymentPollTicks = 0;

  /// Retour de Wave/Orange Money : « Vérification du paiement… » pendant ces
  /// vérifications (~30 s : la confirmation d'Orange Money peut prendre
  /// plusieurs secondes ; avant, la page de paiement se rouvrait alors que le
  /// client venait de payer, et il appuyait de nouveau sur « Payer »).
  /// Paiement abandonné : « Payer la prestation » revient ensuite, la
  /// vérification continue en arrière-plan. Pas de double paiement : Wave rouvre la même session,
  /// et un second paiement est repéré par le serveur (doublon).
  static const int _kVerifyingTicks = 10;

  /// Un paiement est en cours (requête, app Wave/Orange ouverte ou premières
  /// secondes de vérification) : le bouton "Payer" est désactivé.
  bool get _paymentVerifying =>
      _paymentRequestInFlight ||
      _paymentLaunched ||
      (_paymentPollTimer != null && _paymentPollTicks < _kVerifyingTicks);

  @override
  void initState() {
    super.initState();
    // Modes de paiement cochés dans le back-office : relus à l'ouverture.
    FeatureFlags.refresh().then((_) {
      if (mounted) setState(() {});
    });
    MisonOrderDetailScreen._open.update(widget.orderId, (n) => n + 1, ifAbsent: () => 1);
    WidgetsBinding.instance.addObserver(this);
    StepSheets.changes.addListener(_onStepSheetsChanged);
    init();
    _paymentReturnSub = MisonOrderDetailScreen._paymentReturns.stream.listen((event) {
      final (id, success) = event;
      if (id != widget.orderId) return;
      _paymentLaunched = false;
      if (success) {
        _startPaymentPolling();
      } else {
        _stopPaymentPolling();
        _reloadSilently();
      }
    });
    if (appStore.userType == USER_TYPE_PROVIDER) _fetchArtisanPosition();
    // Statut de commande changé côté serveur (paiement confirmé, prestation
    // terminée par l'ouvrier…). orderId null = event sans id, on rafraîchit.
    startAutoRefresh();
    _orderEventsSub = OrderEvents.stream.listen((orderId) {
      if (orderId == null || orderId.isEmpty || orderId == widget.orderId) {
        // Pas de rechargement « à blanc » ni d'arrêt de la vérification du
        // paiement : la page est mise à jour dès que les données arrivent.
        _reloadSilently();
      }
    });
  }

  @override
  void dispose() {
    _paymentLaunchTimeout?.cancel();
    stopAutoRefresh();
    _locationTimer?.cancel();
    _paymentPollTimer?.cancel();
    _orderEventsSub?.cancel();
    _paymentReturnSub?.cancel();
    final n = (MisonOrderDetailScreen._open[widget.orderId] ?? 1) - 1;
    if (n <= 0) {
      MisonOrderDetailScreen._open.remove(widget.orderId);
    } else {
      MisonOrderDetailScreen._open[widget.orderId] = n;
    }
    WidgetsBinding.instance.removeObserver(this);
    StepSheets.changes.removeListener(_onStepSheetsChanged);
    _stepReload?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Le client revient dans l'app après avoir payé via Wave/Orange Money
    // (app externe) : on rafraîchit le statut de la commande.
    if (state == AppLifecycleState.resumed) {
      _reloadSilently();
      if (_paymentLaunched) {
        _paymentLaunched = false;
        _startPaymentPolling();
      }
    }
  }

  void init() => future = getMisonOrderDetail(widget.orderId);

  /// Commande plus accessible (confiée à un autre ouvrier par MISON, ou d'un
  /// autre compte) : les pages d'étape se ferment et la page se débloque, pour
  /// ne pas rester coincé sur « Terminer la prestation » ou le paiement.
  Widget _orderGone(Widget child) {
    final id = widget.orderId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final step in const ['finish', 'go', 'pay', 'price', 'setprice']) {
        StepSheets.close(StepSheets.id(step, id));
      }
      if (mounted && (_locked || _completed)) {
        setState(() {
          _locked = false;
          _completed = false;
        });
      }
    });
    return child;
  }

  /// Une page d'étape s'est fermée (ici ou sur un autre écran de la même
  /// commande) : la commande est rechargée, pour ne jamais rester sur un
  /// statut dépassé (ex. « Prix proposé » alors qu'il vient d'être validé).
  void _onStepSheetsChanged() {
    if (!mounted) return;
    setState(() {});
    _stepReload?.cancel();
    _stepReload = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _reloadSilently();
    });
  }

  Timer? _stepReload;

  /// Ferme les pages d'étape dont l'étape est passée (commande payée, prix
  /// validé, prestation terminée, ouvrier parti), même ouvertes par un autre
  /// écran de la même commande.
  void _closeStaleSheets(MisonOrder order) {
    final id = order.id;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!order.isAwaitingRealizationPayment) StepSheets.close(StepSheets.id('pay', id));
      if (!(order.needsPriceAgreement && order.priceProposal != null && order.priceProposedBy == 'artisan')) {
        StepSheets.close(StepSheets.id('price', id));
      }
      if (!order.isInProgress) StepSheets.close(StepSheets.id('finish', id));
      if (_setPriceReason(order) == null) StepSheets.close(StepSheets.id('setprice', id));
      if (!(order.isBeforeStart && order.isPriceAgreed && !order.isEnRoute && !order.hasArrived)) {
        StepSheets.close(StepSheets.id('go', id));
      }
    });
  }

  // Changements de commande gérés par l'écoute OrderEvents de initState.
  @override
  bool get refreshOnOrderEvents => false;

  /// Actualisation silencieuse du statut (acceptée, en route, arrivée…).
  @override
  Future<void> onAutoRefresh() async {
    final res = await getMisonOrderDetail(widget.orderId);
    if (mounted) setState(() { future = Future.value(res); });
  }

  Future<void> _reloadSilently() async {
    try {
      final res = await getMisonOrderDetail(widget.orderId);
      if (!mounted) return;
      setState(() { future = Future.value(res); });
      if (res.data != null && !res.data!.isAwaitingAnyPayment) _stopPaymentPolling();
    } catch (e) {
      log('[OrderDetail] $e');
    }
  }

  /// Le webhook Wave/Orange Money peut arriver au serveur quelques secondes
  /// après le retour dans l'app : on interroge le statut jusqu'à ce que le
  /// paiement soit pris en compte (max ~1 min 30). La page est mise à jour à
  /// chaque vérification.
  void _startPaymentPolling() {
    if (_paymentPollTimer != null) return; // déjà en cours
    _paymentPollTicks = 0;
    _paymentPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (++_paymentPollTicks > 30 || !mounted) return _stopPaymentPolling();
      // Fin de la vérification visible : le bouton « Payer » revient.
      if (_paymentPollTicks == _kVerifyingTicks) setState(() {});
      try {
        final res = await getMisonOrderDetail(widget.orderId);
        if (!mounted || _paymentPollTimer == null) return;
        setState(() { future = Future.value(res); });
        if (res.data != null && !res.data!.isAwaitingAnyPayment) {
          _stopPaymentPolling();
          if (res.data!.isCompleted) {
            TopToast.show(message: 'Paiement confirmé !', type: TopToastType.success);
          }
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

  /// Ouvre DIRECTEMENT le menu Share Sheet natif (WhatsApp, Mail, Save Image, Save to Files, etc.) avec le reçu en image.
  void _shareInvoice(MisonOrder order) {
    shareMisonReceiptDirectly(context, order);
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
  Future<void> _departTo(MisonOrder order, {bool priceOnSite = false}) async {
    if (!order.isEnRoute) {
      appStore.setLoading(true);
      try {
        await artisanDepart(order.id!, priceOnSite: priceOnSite);
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

  Future<void> _openChat(MisonOrder order) async {
    final peerName = appStore.userType == USER_TYPE_PROVIDER
        ? (order.client?.fullName.isNotEmpty == true ? order.client!.fullName : 'Client')
        : (order.artisan?.fullName.isNotEmpty == true ? order.artisan!.fullName : 'Ouvrier');
    await MisonOrderChatScreen.openOnce(Navigator.of(context), order.id!, peerName: peerName);
  }

  Future<void> _showSetFeeModal({
    required String title,
    required Future<MisonActionResponse> Function(num) apiCall,
  }) {
    final ctrl = TextEditingController();
    // Terminé seulement quand l'envoi au serveur est fini (pas dès la fermeture
    // de la fenêtre) : la page « Terminer la prestation » ne se rouvre pas
    // pendant l'envoi.
    Future<void>? sending;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeeBottomSheet(
        title: title,
        ctrl: ctrl,
        onConfirm: () async {
          if (sending != null) return; // un seul envoi
          final amount = num.tryParse(ctrl.text.trim());
          if (amount == null || amount <= 0) { TopToast.show(message: 'Veuillez saisir un montant valide'); return; }
          Navigator.pop(context);
          sending = () async {
            appStore.setLoading(true);
            try {
              final res = await apiCall(amount);
              TopToast.show(message: res.message ?? 'Succès', type: TopToastType.success);
              await _reloadSilently();
            } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
            finally { appStore.setLoading(false); }
          }();
        },
      ),
    ).then((_) => sending);
  }

  /// Page « Prestation terminée » à l'écran (évite de l'ouvrir deux fois).
  bool _finishOpen = false;

  /// Ouvrier, « Terminer la prestation » : page au style des autres, avec la
  /// note vocale du processus de paiement (à écouter jusqu'au bout), puis fin
  /// au prix convenu ou saisie du montant.
  /// [locked] : prestation en cours, la page reste affichée (ni croix, ni
  /// « Plus tard », ni retour) jusqu'à ce qu'il termine.
  Future<void> _finishPrestation(MisonOrder order, {bool locked = false}) async {
    final sid = StepSheets.id('finish', order.id);
    // Une seule page, même si la commande est ouverte deux fois.
    if (_finishOpen || !StepSheets.claim(sid)) return;
    _finishOpen = true;
    try {
      final agreed = order.isPriceAgreed;
      final go = await showMisonAudioSheet(
        context,
        asset: kAudioWorkerPaymentReminder,
        icon: Icons.verified_user_outlined,
        caption: locked ? 'Prestation en cours' : 'Prestation terminée',
        title: agreed ? formatFcfa(order.agreedPrice!) : 'Montant à fixer',
        subtitle: agreed
            ? ((order.materialsPrice ?? 0) > 0
                ? 'Prix de la prestation convenu avec le client, + matériel ${formatFcfa(order.materialsPrice!)}. '
                    'Terminez quand le travail est fini.'
                : 'Prix convenu avec le client. Terminez quand le travail est fini.')
            : 'Indiquez le montant quand le travail est fini.',
        continueLabel: agreed ? 'Terminer la prestation' : 'Saisir le montant',
        laterLabel: locked ? null : 'Plus tard',
        footnote: RemoteMedia.hasAudio(kAudioWorkerPaymentReminder)
            ? 'Rappel : écoutez comment se passe le paiement.'
            : null,
        warning: "Le client paie dans l'application MISON avec ${FeatureFlags.paymentMethods}.",
        mustListen: true,
        listenKey: 'finish-${order.id}',
        locked: locked,
        stepId: sid,
      );
      if (!go || !mounted) return;
      if (agreed) {
        await _finishWithAgreedPrice(order);
      } else {
        await _showSetFeeModal(
          title: 'Frais de prestation',
          apiCall: (amount) => setRealizationFee(order.id!, amount),
        );
      }
      // Statut à jour AVANT de libérer la page : sinon elle se rouvrait aussitôt
      // sur l'ancien statut (« en cours ») et l'ouvrier devait réappuyer.
      if (mounted) await _reloadSilently();
    } finally {
      _finishOpen = false;
      StepSheets.release(sid);
    }
  }

  /// Ouvrier, prestation en cours : il reste sur « Terminer la prestation ».
  /// La page se rouvre d'elle-même tant que la prestation n'est pas terminée
  /// (saisie du montant fermée sans valider, erreur…).
  void _maybeOpenFinish(MisonOrder order) {
    if (appStore.userType != USER_TYPE_PROVIDER || _finishOpen) return;
    if (!order.isInProgress || order.artisan == null) return;
    if (StepSheets.isOpen(StepSheets.id('finish', order.id))) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _finishOpen) return;
      await _finishPrestation(order, locked: true);
      // Toujours en cours (montant pas validé) : la page revient.
      if (mounted) await _reloadSilently();
    });
  }

  /// Prestation terminée au prix convenu : le client est invité à payer.
  /// Le client a payé en espèces : la commande est terminée et l'ouvrier
  /// doit à MISON sa part (frais de service, commission, assurance).
  Future<void> _declarePaidCash(MisonOrder order) async {
    final ok = await showMisonConfirmSheet(
      context,
      title: 'Payé en espèces ?',
      subtitle: "Confirmez que le client vous a payé en espèces. Vous devrez régler à MISON sa part "
          '(frais de service, commission et assurance), à payer dans l\'app.',
      icon: Icons.payments_outlined,
      confirmLabel: 'Oui, payé en espèces',
    );
    if (!ok) return;
    appStore.setLoading(true);
    try {
      final res = await declarePaidCash(order.id!);
      TopToast.show(message: res.message ?? 'Commande terminée', type: TopToastType.success);
      init();
      if (mounted) setState(() {});
    } catch (e) {
      TopToast.show(message: '$e', type: TopToastType.error);
    } finally {
      appStore.setLoading(false);
    }
  }

  Future<void> _finishWithAgreedPrice(MisonOrder order) async {
    appStore.setLoading(true);
    try {
      final res = await setRealizationFee(order.id!, order.agreedPrice!);
      TopToast.show(message: res.message ?? 'Succès', type: TopToastType.success);
      await _reloadSilently();
    } catch (e) { TopToast.show(message: e.toString(), type: TopToastType.error); }
    finally { appStore.setLoading(false); }
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
      if (mounted) goToMisonHome(context);
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


  /// Ouvrier, avant de fixer le prix : il va d'abord voir chez le client.
  /// Sur place, l'écran reste sur « Entrer le prix de la prestation » ; le
  /// client valide le prix avant que la prestation commence.
  /// Pas de confirmation : la carte avec la position du client s'ouvre aussitôt.
  Future<void> _goFirst(MisonOrder order) async {
    if (!mounted) return;
    await _departTo(order, priceOnSite: true);
  }

  /// Client : nouvelle commande du même service, adressée directement au même
  /// prestataire (demande directe, comme depuis sa fiche).
  void _bookAgain(MisonOrder order) {
    final artisan = order.artisan;
    final service = order.service;
    if (artisan?.id == null || service?.id == null) return;
    MisonBookingFormScreen(
      service: MisonService(
        id: service!.id,
        name: service.name,
        imageUrl: service.imageUrl,
        isAvailable: true,
      ),
      artisanId: artisan!.id,
      artisanName: artisan.fullName,
    ).launch(context);
  }

  /// Ouvrier, bouton « Prix convenu avec le client » : il saisit le prix
  /// sur lequel ils se sont mis d'accord (le client le valide ensuite).
  Future<void> _enterAgreedPrice(MisonOrder order) async {
    // Pas encore parti : petite flèche « Vérifier d'abord chez le client »
    // en bas de la page du prix.
    final beforeTrip = order.isBeforeStart && !order.needsArtisanConfirmation &&
        !order.isEnRoute && !order.hasArrived && !order.isPriceAgreed;
    final sent = await proposeAgreedPrice(
      context,
      order,
      onGoFirst: beforeTrip ? () => _goFirst(order) : null,
    );
    if (sent && mounted) await _reloadSilently();
  }

  bool _goSheetOpen = false;

  /// Ouvrier, prix validé par le client, pas encore parti : page « Aller chez
  /// le client » (même style que les autres), verrouillée jusqu'au départ.
  void _maybeOpenGoToClient(MisonOrder order) {
    if (appStore.userType != USER_TYPE_PROVIDER || _goSheetOpen) return;
    if (!order.isBeforeStart || order.needsArtisanConfirmation || order.hasArrived) return;
    if (!order.isPriceAgreed || order.isEnRoute) return;
    final sid = StepSheets.id('go', order.id);
    if (StepSheets.isOpen(sid)) return;
    _goSheetOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Une seule page, même si la commande est ouverte deux fois.
      if (!StepSheets.claim(sid)) {
        _goSheetOpen = false;
        return;
      }
      // Attend la fin de la note obligatoire d'après l'acceptation.
      while (mounted && isAfterAcceptAudioOpen) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (!mounted) {
        _goSheetOpen = false;
        StepSheets.release(sid);
        return;
      }
      final name = order.client?.fullName ?? '';
      final go = await showMisonAudioSheet(
        context,
        icon: Icons.verified_user_outlined,
        caption: 'Prix validé',
        title: formatFcfa(order.agreedPrice!),
        subtitle: name.isNotEmpty
            ? '${name.split(' ').first} a validé le prix. Vous pouvez y aller.'
            : 'Le client a validé le prix. Vous pouvez y aller.',
        continueLabel: 'Aller chez le client',
        // Tant qu'il n'est pas sur place, il peut consulter la carte.
        laterLabel: 'Voir la carte',
        footnote: 'Le client voit votre trajet en direct',
        warning: "Le client paiera ce prix dans l'application MISON à la fin de la prestation.",
        locked: true,
        stepId: sid,
      );
      // Fermée d'office (déjà parti, ouvert ailleurs) : rien à faire.
      if (StepSheets.consumeForceClosed(sid)) {
        _goSheetOpen = false;
        StepSheets.release(sid);
        return;
      }
      if (go && mounted) {
        // La page reste « ouverte » jusqu'au statut à jour (en route) : sinon
        // elle se rouvrait sur l'ancien statut et l'ouvrier devait réappuyer.
        await _departTo(order);
        if (mounted) await _reloadSilently();
        _goSheetOpen = false;
        StepSheets.release(sid);
        return;
      }
      // « Voir la carte » : la carte du trajet, puis retour sur la page.
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => MisonTrackingScreen(
            orderId: order.id!,
            serviceAddress: order.serviceAddress ?? '',
            artisanName: order.artisan?.fullName ?? 'Ouvrier',
            serviceLat: double.tryParse(order.latitude ?? ''),
            serviceLng: double.tryParse(order.longitude ?? ''),
          ),
        ));
      }
      _goSheetOpen = false;
      StepSheets.release(sid);
      if (mounted) await _reloadSilently();
    });
  }

  bool _setPriceOpen = false;

  /// Ouvrier : écran bloqué sur la saisie du prix.
  /// - 'declined' : le client a refusé le prix proposé ;
  /// - 'onsite' : arrivé chez le client sans prix (client absent à la
  ///   commande, ou parti voir d'abord) : prix à fixer avant de commencer.
  /// null : rien à bloquer (prix validé, ou envoyé et en attente du client).
  String? _setPriceReason(MisonOrder order) {
    if (appStore.userType != USER_TYPE_PROVIDER || order.artisan == null) return null;
    if (!order.needsPriceAgreement || order.priceProposal != null) return null;
    if (order.priceDeclined) return 'declined';
    if (order.hasArrived && (order.priceAtArrival || order.priceAgreementRequired)) return 'onsite';
    return null;
  }

  void _maybeOpenSetPrice(MisonOrder order) {
    final reason = _setPriceReason(order);
    if (reason == null || _setPriceOpen) return;
    final sid = StepSheets.id('setprice', order.id);
    if (StepSheets.isOpen(sid)) return;
    _setPriceOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !StepSheets.claim(sid)) {
        _setPriceOpen = false;
        return;
      }
      while (mounted && isAfterAcceptAudioOpen) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      final declined = reason == 'declined';
      final go = mounted &&
          await showMisonAudioSheet(
            context,
            icon: declined ? Icons.cancel_outlined : Icons.place_outlined,
            caption: declined ? 'Prix refusé' : 'Vous êtes sur place',
            title: declined ? 'Le client a refusé le prix proposé' : 'Entrer le prix de la prestation',
            subtitle: declined
                ? 'Proposez un nouveau prix.'
                : "Mettez-vous d'accord avec le client, puis entrez le prix. "
                    'Il doit le valider avant que vous commenciez.',
            continueLabel: declined ? 'Proposer un nouveau prix' : 'Entrer le prix de la prestation',
            // Prix refusé : il peut d'abord en reparler avec le client.
            laterLabel: declined ? 'Appeler le client' : null,
            locked: true,
            stepId: sid,
          );
      if (StepSheets.consumeForceClosed(sid) || !mounted) {
        _setPriceOpen = false;
        StepSheets.release(sid);
        return;
      }
      if (go) {
        await _enterAgreedPrice(order);
      } else {
        await _startCall(order);
      }
      // Statut à jour avant de libérer : la page revient tant qu'aucun
      // nouveau prix n'est envoyé.
      if (mounted) await _reloadSilently();
      _setPriceOpen = false;
      StepSheets.release(sid);
    });
  }

  /// Page « valider le prix » à l'écran (évite de l'ouvrir deux fois).
  bool _priceSheetOpen = false;

  /// Client : l'ouvrier a proposé un prix. La page de validation s'ouvre
  /// d'elle-même et reste affichée tant que le client n'a ni validé ni refusé.
  void _maybeOpenPriceValidation(MisonOrder order) {
    if (_priceSheetOpen || appStore.userType == USER_TYPE_PROVIDER) return;
    if (!(order.needsPriceAgreement && order.priceProposal != null && order.priceProposedBy == 'artisan')) return;
    final sid = StepSheets.id('price', order.id);
    if (StepSheets.isOpen(sid)) return;
    _priceSheetOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Une seule page, même si la commande est ouverte deux fois.
      if (!mounted || !StepSheets.claim(sid)) {
        _priceSheetOpen = false;
        return;
      }
      final answered = await showPriceValidationSheet(context, order);
      StepSheets.consumeForceClosed(sid);
      if (answered && mounted) await _reloadSilently();
      _priceSheetOpen = false;
      StepSheets.release(sid);
    });
  }

  /// Page de paiement à l'écran (évite de l'ouvrir deux fois).
  bool _paySheetOpen = false;

  /// Client, prestation en attente de paiement : la page de paiement s'ouvre
  /// d'elle-même et reste affichée (pas de croix, ni retour) jusqu'au paiement.
  /// Elle se rouvre au retour de Wave / Orange Money si le paiement n'a pas abouti.
  void _maybeOpenPayment(MisonOrder order) {
    if (_paySheetOpen || _paymentVerifying) return;
    if (appStore.userType == USER_TYPE_PROVIDER || !order.isAwaitingRealizationPayment) return;
    if (StepSheets.isOpen(StepSheets.id('pay', order.id))) return;
    _paySheetOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _paymentVerifying) {
        _paySheetOpen = false;
        return;
      }
      _showPaymentModal(order, locked: true);
    });
  }

  void _showPaymentModal(MisonOrder order, {bool locked = false}) {
    if (_paymentVerifying) {
      _paySheetOpen = false;
      TopToast.show(message: 'Paiement en cours de vérification, patientez quelques secondes.');
      return;
    }
    // Une seule page de paiement, même si la commande est ouverte deux fois.
    final sid = StepSheets.id('pay', order.id);
    if (!StepSheets.claim(sid)) {
      _paySheetOpen = false;
      return;
    }
    _paySheetOpen = true;
    const title = 'Frais de prestation';
    final total = order.clientTotal;
    final price = order.prestationPrice;
    final desc = price != null
        ? 'Prestation ${formatFcfa(price)}'
            '${(order.materialsPrice ?? 0) > 0 ? ' + matériel ${formatFcfa(order.materialsPrice!)}' : ''}'
            ' + frais de service ${formatFcfa(order.serviceFee)}.'
        : "Ces frais correspondent à la prestation réalisée par l'ouvrier.";
    final feeLabel = total != null ? formatFcfa(total) : 'Montant non défini';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: !locked,
      enableDrag: !locked,
      backgroundColor: Colors.transparent,
      builder: (_) => StepSheetScope(
        stepId: sid,
        child: _PaymentBottomSheet(
        orderId: order.id ?? '',
        locked: locked,
        title: title,
        desc: desc,
        feeLabel: feeLabel,
        serviceName: order.service?.name?.isNotEmpty == true ? order.service!.name! : 'Prestation',
        artisanName: order.artisan?.fullName ?? '',
        serviceImageUrl: order.service?.imageUrl,
        priceLabel: price != null ? formatFcfa(price) : '—',
        priceCaption: order.agreedPrice != null ? 'Prix convenu' : 'Prestation',
        agreedPriceLabel: order.agreedPrice != null ? formatFcfa(order.agreedPrice!) : null,
        serviceFeeLabel: formatFcfa(order.serviceFee),
        onPayWave: () async {
          Navigator.pop(context);
          if (_paymentVerifying) return;
          _stopPaymentPolling(); // nouvelle tentative : la vérification repartira au retour
          setState(() => _paymentRequestInFlight = true);
          appStore.setLoading(true);
          try {
            final res = await paymentCheckout(order.id ?? '');
            if (res.waveLaunchUrl != null && res.waveLaunchUrl!.isNotEmpty) {
              _paymentLaunched = true;
              final opened = await launchUrl(Uri.parse(res.waveLaunchUrl!), mode: LaunchMode.externalApplication)
                  .catchError((_) => false);
              if (!opened) {
                _paymentLaunched = false;
                TopToast.show(message: "Impossible d'ouvrir Wave. Vérifiez que l'application est installée.", type: TopToastType.error);
              }
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
          _stopPaymentPolling(); // nouvelle tentative : la vérification repartira au retour
          setState(() => _paymentRequestInFlight = true);
          appStore.setLoading(true);
          try {
            final res = await paymentCheckoutOrange(order.id ?? '');
            if (res.deeplink != null && res.deeplink!.isNotEmpty) {
              _paymentLaunched = true;
              final opened = await launchUrl(Uri.parse(res.deeplink!), mode: LaunchMode.externalApplication)
                  .catchError((_) => false);
              if (!opened) {
                _paymentLaunched = false;
                TopToast.show(message: "Impossible d'ouvrir Orange Money / Max it.", type: TopToastType.error);
              }
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
      ),
    ).whenComplete(() {
      _paySheetOpen = false;
      StepSheets.consumeForceClosed(sid);
      StepSheets.release(sid);
    });
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

  /// Prestation terminée : le retour (bouton du bas ou flèche) ramène à
  /// l'accueil, pas aux écrans de suivi ou de paiement ouverts avant.
  bool _completed = false;
  /// Client : prix à valider/refuser ou prestation à payer → pas de retour.
  bool _locked = false;
  MisonOrder? _lastOrder;

  /// Commandes pour lesquelles le panneau « Noter » s'est déjà ouvert tout seul
  /// (une fois par commande et par session : « Plus tard » ne le rouvre pas).
  static final Set<String> _ratePrompted = {};

  /// Prestation terminée, pas encore notée : le panneau s'ouvre tout seul.
  void _maybePromptRating(MisonOrder order) {
    final isClient = appStore.userType != USER_TYPE_PROVIDER;
    if (!isClient || !order.canRate || order.id == null || !_ratePrompted.add(order.id!)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
        _ratePrompted.remove(order.id!); // réessayé au prochain affichage
        return;
      }
      final rated = await showMisonRateSheet(context, orderId: order.id!, artisanName: order.artisan?.fullName);
      if (rated && mounted) {
        init();
        setState(() {});
      }
    });
  }

  void _goHome() => DashboardScreen().launch(context, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_completed && !_locked,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_locked) {
          // Statut peut-être dépassé : rechargé. S'il n'y a plus rien à faire,
          // la page se libère ; sinon la page d'étape se rouvre.
          _reloadSilently();
          final order = _lastOrder;
          TopToast.show(
            message: appStore.userType == USER_TYPE_PROVIDER
                ? 'Terminez la prestation pour continuer.'
                : order != null && order.isAwaitingRealizationPayment
                    ? 'Payez la prestation pour continuer.'
                    : "Validez ou refusez le prix proposé par l'ouvrier pour continuer.",
          );
          return;
        }
        _goHome();
      },
      child: Scaffold(
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
                ? _orderGone(AppEmptyState(
                    type: AppEmptyStateType.empty,
                    title: kOrderUnavailableMessage,
                    subtitle: 'Elle a peut-être été prise par un autre ouvrier, annulée, '
                        'ou appartient à un autre compte.',
                    retryLabel: 'Retour',
                    onRetry: () => Navigator.of(context).maybePop(),
                  ))
                : AppEmptyState(
                    type: AppEmptyStateType.error,
                    title: error,
                    onRetry: () { init(); setState(() {}); },
                  ),
            onSuccess: (response) {
              final order = response.data;
              final completed = order?.isCompleted ?? false;
              if (order != null) _maybePromptRating(order);
              if (order != null) _maybeOpenPayment(order);
              if (order != null) _maybeOpenPriceValidation(order);
              if (order != null) _maybeOpenGoToClient(order);
              if (order != null) _maybeOpenSetPrice(order);
              if (order != null) _maybeOpenFinish(order);
              if (order != null) _closeStaleSheets(order);
              if (completed != _completed) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _completed = completed);
                });
              }
              _lastOrder = order;
              // Client : prix à valider ou prestation à payer.
              // Ouvrier : prestation en cours, il reste sur la commande jusqu'à la terminer.
              final locked = appStore.userType != USER_TYPE_PROVIDER
                  ? (order?.clientMustAct ?? false)
                  : (order?.isInProgress ?? false);
              if (locked != _locked) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _locked = locked);
                });
              }
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
                onAccept: () async {
                  final ok = await showMisonAudioSheet(
                    context,
                    icon: Icons.info_outline_rounded,
                    caption: 'Nouvelle commande',
                    title: order.service?.name?.isNotEmpty == true ? order.service!.name! : 'Accepter la commande',
                    subtitle: order.serviceAddress?.isNotEmpty == true ? order.serviceAddress! : 'Confirmez-vous l\'acceptation ?',
                    continueLabel: 'Accepter la commande',
                    laterLabel: 'Plus tard',
                    footnote: 'Le client est prévenu dès que vous acceptez.',
                  );
                  if (ok && mounted) _acceptOrder(order.id!);
                },
                // Même panneau que l'annulation : vérifications puis démarrage.
                onStart: () async {
                  final started = await showMisonStartPrestationSheet(context, orderId: order.id!);
                  if (started && mounted) {
                    init();
                    setState(() {});
                  }
                },
                onChat: () => _openChat(order),
                onPaidCash: () => _declarePaidCash(order),
                // Ouvrier, « Terminer la prestation » : rappel audio du processus
                // de paiement, puis la suite habituelle.
                onSetRealizationFee: () => _finishPrestation(order),
                onPriceChanged: () { init(); setState(() {}); },
                // Client : panneau d'annulation Mison (motif, chargement) ;
                // ouvrier : confirmation de désistement inchangée
                onCancel: appStore.userType == USER_TYPE_PROVIDER
                    ? () => _confirm(
                          title: order.isPendingDirectRequest ? 'Refuser la demande' : 'Se désister de la commande',
                          subtitle: order.isPendingDirectRequest
                              ? 'Le client sera prévenu et sa demande sera proposée à d\'autres prestataires.'
                              : 'La commande sera reproposée aux autres ouvriers. Confirmez-vous ?',
                          type: DialogType.DELETE,
                          onConfirm: () => _cancelOrder(order.id!),
                        )
                    : () async {
                        final result = await showMisonCancelOrderSheet(
                          context,
                          orderId: order.id!,
                          hasArtisan: order.artisan != null,
                        );
                        if (!mounted) return;
                        if (result == MisonCancelResult.cancelled) {
                          goToMisonHome(context);
                        } else if (result == MisonCancelResult.artisanChanged) {
                          // Nouvelle recherche : on la suit sur la carte.
                          Navigator.of(context).pushReplacement(MaterialPageRoute(
                            builder: (_) => MisonOrderSearchingScreen(orderId: order.id!),
                          ));
                        }
                      },
                // Message audio de MISON (même panneau que l'annulation), puis paiement.
                // Une seule page : prix, note vocale de MISON, bouton de paiement.
                onPay: () => _showPaymentModal(order),
                paymentVerifying: _paymentVerifying,
                onRated: () { init(); setState(() {}); },
                onShareInvoice: () => _shareInvoice(order),
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
                onGoFirst: () => _goFirst(order),
                onArrive: () => _markArrived(order),
                onAgreedPrice: () => _enterAgreedPrice(order),
                onBookAgain: () => _bookAgain(order),
              );
            },
          ),
          Observer(builder: (_) => LoaderWidget(colors: const [kMisonDark, kMisonGold]).visible(appStore.isLoading)),
        ],
        ),
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
  /// Ouvrier : le client l'a payé en espèces.
  final VoidCallback? onPaidCash;
  final VoidCallback onPriceChanged;
  final VoidCallback onCancel;
  final VoidCallback onPay;
  final bool paymentVerifying;
  final VoidCallback onRated;
  final VoidCallback onShareInvoice;
  final VoidCallback onCall;
  final VoidCallback onTrack;
  final VoidCallback onNavigate;
  final VoidCallback onDepart;
  /// Ouvrier, avant de partir : aller voir chez le client avant de fixer le prix.
  final VoidCallback onGoFirst;
  /// Ouvrier, prix pas encore convenu : saisie du prix convenu.
  final VoidCallback onAgreedPrice;
  /// Client, commande terminée : nouvelle commande au même prestataire.
  final VoidCallback onBookAgain;
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
    this.onPaidCash,
    required this.onPriceChanged,
    required this.onCancel,
    required this.onPay,
    this.paymentVerifying = false,
    required this.onRated,
    required this.onShareInvoice,
    required this.onCall,
    required this.onTrack,
    required this.onNavigate,
    required this.onDepart,
    required this.onArrive,
    required this.onAgreedPrice,
    required this.onGoFirst,
    required this.onBookAgain,
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
    // En attente de paiement : plus besoin d'appel ni de message, le bouton
    // principal (Payer / payé en espèces) prend toute la largeur.
    final showBottomCall = order.canCall && !_artisanSummary && !order.isAwaitingRealizationPayment;
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
    // Le client l'a payé en espèces : il le déclare (sa part revient à MISON).
    final showCashButton = _isArtisan && order.isAwaitingRealizationPayment && FeatureFlags.cashTracking && onPaidCash != null;
    // Actions déjà proposées par une page qui s'ouvre d'elle-même : pas de
    // bouton en double dans la barre du bas (il apparaissait dès que la page
    // se fermait, le temps de la mise à jour).
    // - Ouvrier, prestation en cours : page « Terminer la prestation ».
    // - Ouvrier, prix validé, pas encore parti : page « Aller chez le client ».
    // - Client, prestation à payer : page de paiement (sauf pendant la
    //   vérification d'un paiement : « Vérification du paiement… » reste affiché).
    // Seulement pendant que la page est affichée : sinon le bouton revient
    // (jamais bloqué sans page ni bouton).
    final finishBySheet = showSetFeeButton && StepSheets.isOpen(StepSheets.id('finish', order.id));
    final goBySheet = showGoButton && order.isPriceAgreed && !order.isEnRoute &&
        StepSheets.isOpen(StepSheets.id('go', order.id));
    final payBySheet = _showPayButton && order.isAwaitingRealizationPayment && !paymentVerifying &&
        StepSheets.isOpen(StepSheets.id('pay', order.id));
    final showPrimaryAction = showAcceptButton ||
        (showGoButton && !goBySheet) ||
        showStartButton ||
        (showSetFeeButton && !finishBySheet) ||
        showCashButton ||
        (_showPayButton && !payBySheet) ||
        _showPayLocked;
    final showBottomBar = showBottomCall || showPrimaryAction || showClientCancel;
    // Ouvrier, avant de partir, prix pas encore convenu : appeler, discuter,
    // puis « Prix convenu avec le client » (3 boutons à la place du bouton
    // principal). Prix déjà envoyé : en attente de la validation du client.
    // Client absent à la commande : départ sans prix (bouton « Aller chez le
    // client » directement) ; sur place, le prix avant « Commencer ».
    final priceStep = (showGoButton && !order.isPriceAgreed && !order.priceAtArrival) ||
        (showStartButton && (order.priceAtArrival || order.priceAgreementRequired) && !order.isPriceAgreed);
    final priceWaitingClient = order.priceProposal != null && order.priceProposedBy == 'artisan';
    final showPriceButtons = priceStep && !priceWaitingClient && order.canChat;

    late final String primaryActionLabel;
    late final IconData primaryActionIcon;
    late final Color primaryActionColor;
    late final VoidCallback primaryActionTap;
    if (showAcceptButton) {
      primaryActionLabel = order.isPendingDirectRequest
          ? 'Accepter la demande'
          : order.needsArtisanConfirmation
              ? 'Confirmer cette commande'
              : 'Accepter cette commande';
      primaryActionIcon = Icons.check_circle_outline_rounded;
      primaryActionColor = kMisonGold; // Accepter / Confirmer en doré
      primaryActionTap = onAccept;
    } else if (priceStep) {
      // Prix envoyé, le client ne l'a pas encore validé.
      primaryActionLabel = 'Prix envoyé · en attente du client';
      primaryActionIcon = Icons.hourglass_top_rounded;
      primaryActionColor = Colors.grey;
      primaryActionTap = () => TopToast.show(
            message: 'Le client doit valider le prix. Vous pourrez ensuite aller chez lui.',
          );
    } else if (showGoButton) {
      // « Accord sur le prix obligatoire » (back-office) : grisé tant que le
      // client n'a pas validé le prix.
      final waitPrice = order.priceAgreementRequired && !order.isPriceAgreed && !order.priceAtArrival;
      // Déjà en route : on rouvre l'itinéraire (pas un 2e « Aller chez le client »).
      primaryActionLabel = order.isEnRoute ? "Voir l'itinéraire" : 'Aller chez le client';
      primaryActionIcon = order.isEnRoute ? Icons.navigation_rounded : Icons.directions_car_rounded;
      primaryActionColor = waitPrice ? Colors.grey : kMisonGold;
      primaryActionTap = waitPrice
          ? () => TopToast.show(
                message: "Mettez-vous d'abord d'accord sur le prix avec le client : il doit le valider avant que vous partiez.",
              )
          : onDepart;
    } else if (showStartButton) {
      primaryActionLabel = 'Commencer la prestation';
      primaryActionIcon = Icons.play_circle_outline_rounded;
      primaryActionColor = Colors.green;
      primaryActionTap = onStart;
    } else if (showSetFeeButton) {
      primaryActionLabel = order.isPriceAgreed ? 'Terminer la prestation' : 'Définir les frais de prestation';
      primaryActionIcon = Icons.receipt_long_rounded;
      primaryActionColor = completed;
      primaryActionTap = onSetRealizationFee;
    } else if (showCashButton) {
      primaryActionLabel = "Le client m'a payé en espèces";
      primaryActionIcon = Icons.payments_outlined;
      primaryActionColor = Colors.grey.shade700;
      primaryActionTap = onPaidCash!;
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
            // maybePop : passe par le retour de l'écran (accueil si terminée).
            onPressed: () => Navigator.maybePop(context),
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

                // ── Client : recherche en cours → carte radar des prestataires ──
                if (_isClient && order.isPending && order.artisan == null &&
                    (order.latitude ?? '').isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => MisonOrderSearchingScreen(orderId: order.id!, initialOrder: order).launch(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kMisonGold,
                        side: const BorderSide(color: kMisonGold, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.radar_rounded),
                      label: Text('Voir la recherche sur la carte', style: boldTextStyle(size: 15, color: kMisonGold)),
                    ),
                  ),
                  20.height,
                ],

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
                      statusLabel: order.isPendingDirectRequest ? 'En attente de réponse' : statusLabel(order.status),
                      serviceName: order.service?.name ?? '',
                    ),
                  // Commande terminée : refaire appel au même prestataire
                  // (demande directe), en haut de la page.
                  if (order.isCompleted && order.artisan?.id != null && order.service?.id != null) ...[
                    12.height,
                    // Carte blanche bordée : « Réserver à nouveau » en or,
                    // « Même service · Même prestataire » dessous.
                    Material(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: onBookAgain,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.refresh_rounded, color: kMisonGold, size: 24),
                                  6.width,
                                  Text('Réserver à nouveau', style: boldTextStyle(size: 18, color: kMisonGold)),
                                ],
                              ),
                              4.height,
                              Text('Même service · Même prestataire',
                                  style: secondaryTextStyle(size: 14, color: kMisonDark.withValues(alpha: 0.65))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  20.height,
                ],

                // ── Client : récapitulatif (prix, prestation, mode de paiement)
                // une fois les frais de prestation fixés ──────────────────────
                // (Client, en attente du paiement : le montant et l'avertissement
                // sont sur la page de paiement, qui s'ouvre d'elle-même.)
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
                    statusLabel: order.isPendingDirectRequest ? 'En attente de réponse' : statusLabel(order.status),
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
                              order.isPendingDirectRequest
                                  ? 'Ce client vous a choisi. Acceptez ou refusez sa demande.'
                                  : 'Cette commande vous a été affectée par MISON. Confirmez-la pour la démarrer.',
                              style: secondaryTextStyle(size: 14, color: kMisonGold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                // ── Accord sur le prix avant la prestation (client et ouvrier),
                // puis rappel du prix convenu jusqu'à la fin de la prestation ──
                if (order.needsPriceAgreement ||
                    (order.isPriceAgreed && (order.isBeforeStart || order.isInProgress))) ...[
                  MisonPriceAgreementCard(order: order, isArtisan: _isArtisan, onChanged: onPriceChanged),
                  16.height,
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
                    label: order.isPendingDirectRequest ? 'Refuser la demande' : 'Se désister de la commande',
                    onTap: onCancel,
                    expanded: true,
                  ),
                  8.height,
                  Text(
                    order.isPendingDirectRequest
                        ? 'Le client sera prévenu et sa demande proposée aux autres ouvriers du service.'
                        : 'La commande sera reproposée aux autres ouvriers du service.',
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

                // ── Prestation terminée : Partager la facture ──────────────────
                if (order.isCompleted) ...[
                  16.height,
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: onShareInvoice,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kMisonGold,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.share_rounded, color: Colors.black),
                            label: Text(
                              'Partager',
                              style: boldTextStyle(size: 14, color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                    ],
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Client, prestation en cours : message audio à écouter avant de
                // payer. En attente du paiement, il est sur la page de paiement
                // (qui s'ouvre d'elle-même) : pas de deuxième lecteur ici.
                if (_showPayLocked) ...[
                  const _PaymentAudioMessage(
                    asset: kAudioBeforePayment,
                    title: 'Écoutez avant de payer',
                  ),
                  12.height,
                ],
                // Ouvrier, paiement en attente : rappel du processus de paiement.
                // Prestation en cours : la note est sur la page « Terminer la
                // prestation » (qui s'ouvre d'elle-même) : pas de doublon ici.
                if (showCashButton) ...[
                  const _PaymentAudioMessage(
                    asset: kAudioWorkerPaymentReminder,
                    title: 'Rappel : le processus de paiement',
                  ),
                  12.height,
                ],
                if (showPriceButtons)
                  _PriceStepButtons(
                    order: order,
                    onCall: onCall,
                    onChat: onChat,
                    onAgreedPrice: onAgreedPrice,
                    // « Aller d'abord chez le client » : seulement avant le départ
                    // (prix fixé sur place, validé avant de commencer).
                    onDepart: null,
                  )
                else
                Row(
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
                // Appel et message seuls (action principale dans une page) :
                // à droite, à leur place habituelle.
                if (showBottomCall && !showPrimaryAction && !showClientCancel) const Spacer(),
                if (showBottomCall) ...[
                  ValueListenableBuilder<bool>(
                    // Désactivé pendant le lancement de l'appel (un seul appel par appui).
                    valueListenable: isStartingCall,
                    builder: (_, starting, __) => Opacity(
                    opacity: starting ? 0.4 : 1,
                    child: IgnorePointer(
                    ignoring: starting,
                    child: SizedBox(
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
                    ),
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
              ],
            ),
          ),
        ),
      ],  // end Stack children
    );  // end Stack
  }

}

/// Ouvrier, avant de partir, prix pas encore convenu : « Appeler le client »,
/// « Discuter avec le client », « Prix convenu avec le client ».
class _PriceStepButtons extends StatelessWidget {
  final MisonOrder order;
  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onAgreedPrice;
  /// Aller d'abord chez le client (vérifier avant de fixer le prix).
  final VoidCallback? onDepart;

  const _PriceStepButtons({
    required this.order,
    required this.onCall,
    required this.onChat,
    required this.onAgreedPrice,
    this.onDepart,
  });

  @override
  Widget build(BuildContext context) {
    final discussed = order.hasDiscussed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                // Un seul lancement d'appel par appui.
                valueListenable: isStartingCall,
                builder: (_, starting, __) => _PriceStepButton(
                  icon: Icons.call_rounded,
                  label: 'Appeler\nle client',
                  filled: true,
                  onTap: starting ? null : onCall,
                ),
              ),
            ),
            10.width,
            Expanded(
              child: _PriceStepButton(
                icon: Icons.chat_outlined,
                label: 'Discuter\navec le client',
                onTap: onChat,
              ),
            ),
            10.width,
            Expanded(
              child: Opacity(
                // Le serveur refuse un prix sans échange préalable.
                opacity: discussed ? 1 : 0.45,
                child: _PriceStepButton(
                  icon: Icons.handshake_outlined,
                  label: 'Entrer le prix\nconvenu avec\nle client',
                  onTap: discussed
                      ? onAgreedPrice
                      : () => TopToast.show(
                            message: "Appelez ou discutez d'abord avec le client, puis entrez le prix convenu.",
                          ),
                ),
              ),
            ),
          ],
        ),
        // Flèche tout en bas : aller vérifier chez le client avant de fixer
        // le prix (le prix sera fixé sur place).
        if (onDepart != null) ...[
          6.height,
          InkWell(
            onTap: onDepart,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text("Vérifier d'abord chez le client",
                        style: boldTextStyle(size: 14, color: kMisonDark.withValues(alpha: 0.8))),
                  ),
                  8.width,
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: kMisonGold, shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PriceStepButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  const _PriceStepButton({required this.icon, required this.label, this.filled = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : kMisonDark;
    return Material(
      color: filled ? kMisonGold : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: filled ? BorderSide.none : const BorderSide(color: kMisonGold, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: filled ? Colors.white : kMisonGold, size: 24),
                6.width,
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(label, maxLines: 3, style: primaryTextStyle(size: 14, color: fg, height: 1.15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              cacheKey: imageCacheKey(url!.trim()),
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
                        // Appui : liste des avis laissés par les clients.
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (artisan.id == null) return;
                            MisonArtisanReviewsScreen(
                              artisanId: artisan.id!,
                              artisanName: '${artisan.firstName ?? ''} ${artisan.lastName ?? ''}'.trim(),
                            ).launch(context);
                          },
                          child: Row(children: [
                            Icon(Icons.star_rounded, size: 14, color: ratingBarColor),
                            4.width,
                            Text(
                              '${artisan.rating.toStringAsFixed(1)} (${artisan.totalReviews ?? 0} avis)',
                              style: secondaryTextStyle(size: 14),
                            ),
                            6.width,
                            Text('Voir',
                                style: boldTextStyle(size: 13, color: kMisonGold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: kMisonGold)),
                          ]),
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
      // Recherche par étapes (5 → 10 → 15 km), puis prise en charge par l'équipe.
      if (order.isSearchHandledByTeam) {
        return const _InfoRow(
          icon: Icons.support_agent_rounded,
          label: 'Ouvrier',
          value: 'Votre demande est en cours : notre équipe vous trouve un ouvrier.',
        );
      }
      return const _InfoRow(icon: icon, label: 'Ouvrier', value: "Recherche d'un ouvrier en cours…");
    }
    // Trajet de l'ouvrier : pas encore parti → en route (heure d'arrivée) → arrivé
    if (order.hasArrived) {
      return const _InfoRow(
        icon: Icons.where_to_vote_rounded,
        label: 'Ouvrier',
        value: 'Arrivé chez vous · demandez-lui de lancer la prestation dans l\'app',
      );
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
      // Matériel (facultatif) : payé par le client, reversé en entier à l'ouvrier.
      if ((order.materialsPrice ?? 0) > 0) ...[
        _Divider(),
        _InfoRow(icon: Icons.construction_rounded, label: 'Prix du matériel', value: _fcfa(order.materialsPrice)),
      ],
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
        // Client, pas encore payé : formulé pour lui (Wave ou Orange Money)
        value: forClient && order.paymentMethod == null && !order.isCompleted
            ? '${FeatureFlags.paymentMethods} · à régler'
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

  /// Même présentation que les autres pages (fiche Google Play) : logo, petit
  /// libellé doré, montant saisi en grand, bouton, avertissement.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 14, 16, MediaQuery.of(context).padding.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset('assets/logo/logo_transparent.png', height: 30,
                      errorBuilder: (_, __, ___) => Text('MISON', style: boldTextStyle(size: 20, color: kMisonDark))),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 26),
                    color: kMisonDark,
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Fermer',
                  ),
                ],
              ),
              14.height,
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: boldTextStyle(size: 15, color: kMisonGold, letterSpacing: 0.3)),
                    6.height,
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      style: primaryTextStyle(size: 36, color: kMisonDark, weight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: primaryTextStyle(size: 36, color: Colors.grey.shade400, weight: FontWeight.w600),
                        suffixText: 'FCFA',
                        suffixStyle: boldTextStyle(size: 18, color: kMisonDark.withValues(alpha: 0.6)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.35)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: kMisonGold, width: 1.5),
                        ),
                      ),
                    ),
                    22.height,
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kMisonGold,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Terminer la prestation', style: boldTextStyle(color: Colors.white, size: 16)),
                      ),
                    ),
                    8.height,
                    Text('Montant de la prestation réalisée',
                        style: secondaryTextStyle(size: 13, color: kMisonDark.withValues(alpha: 0.75))),
                    22.height,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.verified_user_outlined, color: kMisonGold, size: 24),
                        14.width,
                        Expanded(
                          child: Text(
                            "Le client paiera ce montant dans l'application MISON.",
                            style: primaryTextStyle(size: 15, color: kMisonDark.withValues(alpha: 0.85)),
                          ),
                        ),
                      ],
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet paiement (Wave / Orange Money)
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentBottomSheet extends StatefulWidget {
  /// Ouverte d'office (prestation à payer) : ne se ferme pas avant le paiement.
  final bool locked;
  final String orderId;
  final String title;
  final String desc;
  final String feeLabel;
  final String serviceName;
  final String artisanName;
  final String? serviceImageUrl;
  final String priceLabel;
  final String priceCaption;
  final String? agreedPriceLabel;
  final String serviceFeeLabel;
  final VoidCallback onPayWave;
  final VoidCallback onPayOrange;

  const _PaymentBottomSheet({
    required this.orderId,
    this.locked = false,
    required this.title,
    required this.desc,
    required this.feeLabel,
    required this.serviceName,
    required this.artisanName,
    this.serviceImageUrl,
    required this.priceLabel,
    this.priceCaption = 'Prestation',
    this.agreedPriceLabel,
    required this.serviceFeeLabel,
    required this.onPayWave,
    required this.onPayOrange,
  });

  @override
  State<_PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

/// Panneau « Payer la prestation », présenté comme une fiche Google Play :
/// en-tête (logo, fermer), ouvrier en couleur, grand titre (le service),
/// chiffres en colonnes, gros bouton arrondi, mentions, encart d'information.
class _PaymentBottomSheetState extends State<_PaymentBottomSheet> {
  // Un seul mode coché dans le back-office : choisi d'office.
  String? _selected = FeatureFlags.paymentMethodList.length == 1
      ? (FeatureFlags.paymentMethodList.first == 'Wave' ? 'wave' : 'orange')
      : null;

  static const _wave = Color(0xFF1BA1F1);
  static const _orange = Color(0xFFFF7900);

  /// Commandes dont la note vocale a été écoutée jusqu'au bout : la page qui
  /// se rouvre (paiement abandonné) ne la réimpose pas.
  static final Set<String> _listenedOrders = {};
  bool get _audioDone => _noNote || _listenedOrders.contains(widget.orderId);

  /// La note n'a pas pu être lue.
  bool _unavailableNote = false;

  /// Pas de note sur le serveur, ou note illisible : la page s'affiche sans
  /// lecteur ni « Écoutez… », et le paiement est possible tout de suite.
  bool get _noNote => _unavailableNote || !RemoteMedia.hasAudio(kAudioBeforePayment);

  @override
  Widget build(BuildContext context) {
    final isWave   = _selected == 'wave';
    final isOrange = _selected == 'orange';
    // Modes de paiement indisponibles tant que la note vocale n'est pas finie.
    final canPay   = (isWave || isOrange) && _audioDone;
    // Wave et Orange Money toujours affichés ; un mode non activé dans le
    // back-office est grisé avec « Bientôt » et ne se choisit pas.
    final waveOn = FeatureFlags.paymentMethodList.contains('Wave');
    final orangeOn = FeatureFlags.paymentMethodList.contains('Orange Money');
    final btnColor = isWave ? _wave : isOrange ? _orange : kMisonGold;
    final btnLabel = isOrange
        ? 'Payer avec Orange Money'
        : isWave
            ? 'Payer avec Wave'
            : 'Choisissez un moyen de paiement';

    return PopScope(
      canPop: !widget.locked,
      child: Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 14, 16, MediaQuery.of(context).padding.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête : logo MISON, fermer
            Row(
              children: [
                Image.asset('assets/logo/logo_transparent.png', height: 30, errorBuilder: (_, __, ___) =>
                    Text('MISON', style: boldTextStyle(size: 20, color: kMisonDark))),
                const Spacer(),
                if (!widget.locked)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 26),
                    color: kMisonDark,
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Fermer',
                  )
                else
                  const SizedBox(height: 48),
              ],
            ),
            14.height,
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Petit libellé en couleur, puis le prix en grand
                  Text(widget.priceCaption == 'Prix convenu' ? 'PRIX CONVENU' : 'À PAYER',
                      style: boldTextStyle(size: 15, color: kMisonGold, letterSpacing: 0.3)),
                  6.height,
                  Text(widget.feeLabel,
                      style: primaryTextStyle(size: 36, color: kMisonDark, weight: FontWeight.w600)),
                  16.height,

                  // Note vocale de MISON à écouter avant de payer (démarre seule).
                  // Pas de note (ou illisible) : ni lecteur ni consigne.
                  if (!_noNote) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: kMisonFieldBg,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: VoiceNotePlayer(
                      asset: kAudioBeforePayment,
                      color: kMisonGold,
                      autoPlay: !_audioDone,
                      expand: true,
                      onCompleted: () {
                        if (!mounted) return;
                        setState(() => _listenedOrders.add(widget.orderId));
                      },
                      // Note illisible : le client peut quand même payer.
                      onUnavailable: () {
                        if (!mounted) return;
                        setState(() {
                          _listenedOrders.add(widget.orderId);
                          _unavailableNote = true;
                        });
                      },
                    ),
                  ),
                  if (!_audioDone) ...[
                    8.height,
                    Text('Écoutez le message jusqu’au bout pour pouvoir payer.',
                        style: secondaryTextStyle(size: 13)),
                  ],
                  20.height,
                  ],

                  // Moyen de paiement : pastilles (toujours les deux)
                  ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _MethodPill(
                            label: 'Wave',
                            logoAsset: 'assets/images/wave_logo.png',
                            color: _wave,
                            selected: isWave,
                            enabled: _audioDone,
                            soon: !waveOn,
                            onTap: () => setState(() => _selected = 'wave'),
                          ),
                        ),
                        10.width,
                        Expanded(
                          child: _MethodPill(
                            label: 'Orange Money',
                            logoAsset: 'assets/images/orange_money.jpg',
                            color: _orange,
                            selected: isOrange,
                            enabled: _audioDone,
                            soon: !orangeOn,
                            onTap: () => setState(() => _selected = 'orange'),
                          ),
                        ),
                      ],
                    ),
                    14.height,
                  ],

                  // Gros bouton arrondi
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: canPay ? (isOrange ? widget.onPayOrange : widget.onPayWave) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: btnColor,
                        disabledBackgroundColor: Colors.grey.shade300,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        btnLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: boldTextStyle(color: canPay ? Colors.white : Colors.grey.shade600, size: 16),
                      ),
                    ),
                  ),
                  // Note sous le bouton
                  8.height,
                  Text('Paiement sécurisé • Reçu disponible après le paiement',
                      style: secondaryTextStyle(size: 13, color: kMisonDark.withValues(alpha: 0.75))),
                  22.height,

                  // Avertissement
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_outlined, color: kMisonGold, size: 24),
                      14.width,
                      Expanded(
                        child: Text(
                          widget.desc,
                          style: primaryTextStyle(size: 15, color: kMisonDark.withValues(alpha: 0.85)),
                        ),
                      ),
                    ],
                  ),
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


/// Choix Wave / Orange Money : pastille avec logo.
class _MethodPill extends StatelessWidget {
  final String label;
  final String logoAsset;
  final Color color;
  final bool selected;
  final bool enabled;
  /// Mode pas encore ouvert : grisé, « Bientôt » dessous, ne se choisit pas.
  final bool soon;
  final VoidCallback onTap;

  const _MethodPill({
    required this.label,
    required this.logoAsset,
    required this.color,
    required this.selected,
    this.enabled = true,
    this.soon = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (soon) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.4,
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: _pill(context),
            ),
          ),
          4.height,
          Text('Bientôt', style: secondaryTextStyle(size: 12, weight: FontWeight.w600)),
        ],
      );
    }
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: _pill(context),
    ),
    );
  }

  Widget _pill(BuildContext context) {
    return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : context.cardColor,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: selected ? color : Colors.grey.withValues(alpha: 0.3), width: selected ? 1.6 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(logoAsset, width: 22, height: 22, fit: BoxFit.cover),
            ),
            8.width,
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: boldTextStyle(size: 14, color: selected ? color : kMisonDark)),
            ),
          ],
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
                      behavior: HitTestBehavior.opaque,
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


/// Message audio de MISON affiché dans la fiche commande, au-dessus du bouton
/// d'action (client : avant « Payer » ; ouvrier : avant « Terminer »).
class _PaymentAudioMessage extends StatelessWidget {
  final String asset;
  final String title;

  const _PaymentAudioMessage({required this.asset, required this.title});

  @override
  Widget build(BuildContext context) {
    if (!RemoteMedia.hasAudio(asset)) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kMisonGold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.headphones_rounded, color: kMisonGold, size: 18),
              6.width,
              Expanded(child: Text(title, style: boldTextStyle(size: 14))),
            ],
          ),
          VoiceNotePlayer(asset: asset, color: kMisonGold, expand: true),
        ],
      ),
    );
  }
}
