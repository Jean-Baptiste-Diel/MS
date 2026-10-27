import 'dart:async';

import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark;
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_searching_screen.dart';
import 'package:booking_system_flutter/utils/order_events.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Accueil client : commandes en cours, avec leur état et celui du
/// prestataire. Un appui ouvre le suivi. Rien n'est affiché sans commande.
class MisonActiveOrdersSection extends StatefulWidget {
  /// Change à chaque actualisation de l'accueil (glisser vers le bas).
  final int refreshTick;

  const MisonActiveOrdersSection({super.key, this.refreshTick = 0});

  /// Commande pas encore terminée ni annulée.
  static bool isActive(MisonOrder o) =>
      o.isPending || o.isBeforeStart || o.isInProgress || o.isAwaitingRealizationPayment;

  @override
  State<MisonActiveOrdersSection> createState() => _MisonActiveOrdersSectionState();
}

class _MisonActiveOrdersSectionState extends State<MisonActiveOrdersSection> {
  List<MisonOrder> _orders = [];
  StreamSubscription<String?>? _eventsSub;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Notification ou action sur une commande : mise à jour immédiate.
    _eventsSub = OrderEvents.stream.listen((_) => _load());
    // En route, arrivé… : l'état suit aussi sans notification.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void didUpdateWidget(MisonActiveOrdersSection old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await getMisonOrders(offlineFallback: true);
      final active = (response.data ?? []).where(MisonActiveOrdersSection.isActive).toList();
      if (mounted) setState(() => _orders = active);
    } catch (_) {
      // Réseau instable : on garde l'affichage, nouvel essai au prochain tour.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_orders.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _orders.length == 1 ? 'Ma commande en cours' : 'Mes commandes en cours (${_orders.length})',
            style: boldTextStyle(size: 15),
          ),
          6.height,
          for (final order in _orders) ...[
            _ActiveOrderCard(order: order),
            6.height,
          ],
        ],
      ),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  final MisonOrder order;

  const _ActiveOrderCard({required this.order});

  /// État de la commande : libellé et couleur.
  (String, Color) get _orderState {
    if (order.isPending) {
      return order.isSearchHandledByTeam
          ? ('Notre équipe s\'en occupe', const Color(0xFFE8833A))
          : ('Recherche d\'un prestataire', kMisonGold);
    }
    if (order.isPendingDirectRequest) return ('Demande envoyée', kMisonGold);
    if (order.needsArtisanConfirmation) return ('Prestataire affecté', kMisonGold);
    if (order.isBeforeStart) {
      return order.needsPriceAgreement && order.priceProposal != null && order.priceProposedBy == 'artisan'
          ? ('Prix à valider', const Color(0xFFE8833A))
          : ('Prestataire trouvé', Colors.green.shade600);
    }
    if (order.isInProgress) return ('Intervention en cours', const Color(0xFF1E88E5));
    return ('Paiement à effectuer', const Color(0xFFE8833A));
  }

  /// État du prestataire : texte et icône.
  (String, IconData) get _artisanState {
    if (order.isPendingDirectRequest) return ('En attente de sa réponse', Icons.hourglass_top_rounded);
    if (order.needsArtisanConfirmation) return ('Doit confirmer la commande', Icons.hourglass_top_rounded);
    if (order.isEnRoute) return ('En route vers vous', Icons.directions_car_rounded);
    if (order.hasArrived) return ('Arrivé à votre adresse', Icons.where_to_vote_rounded);
    if (order.isBeforeStart) return ('Pas encore parti', Icons.schedule_rounded);
    if (order.isInProgress) return ('Sur place, au travail', Icons.handyman_rounded);
    return ('Prestation terminée', Icons.check_circle_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final (stateLabel, stateColor) = _orderState;
    final artisan = order.artisan;
    final detail = artisan == null
        ? (order.isSearchHandledByTeam ? 'Aucun prestataire disponible pour le moment' : 'Recherche en cours…')
        : '${artisan.firstName?.trim().isNotEmpty == true ? artisan.firstName!.trim() : 'Prestataire'} · ${_artisanState.$1}';
    // Une seule ligne compacte : photo, service + état du prestataire, état.
    return Material(
      color: context.cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => MisonOrderSearchingScreen.screenFor(order).launch(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: stateColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              if (artisan == null)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircularProgressIndicator(strokeWidth: 2, color: kMisonGold.withValues(alpha: 0.8)),
                  ),
                )
              else
                CachedImageWidget(
                  url: artisan.profilePictureUrl ?? '',
                  height: 28,
                  width: 28,
                  fit: BoxFit.cover,
                  circle: true,
                ),
              10.width,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.service?.name ?? 'Commande',
                      style: boldTextStyle(size: 13, color: kMisonDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(detail, style: secondaryTextStyle(size: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              6.width,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(stateLabel, style: boldTextStyle(size: 11, color: stateColor)),
              ),
              const Icon(Icons.chevron_right_rounded, color: kMisonGold, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
