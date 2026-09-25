import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

class MisonBookingSuccessScreen extends StatelessWidget {
  final MisonOrder order;
  final String serviceName;
  final String paymentMethod;

  const MisonBookingSuccessScreen({
    Key? key,
    required this.order,
    required this.serviceName,
    required this.paymentMethod,
  }) : super(key: key);

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '—';
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date);
    } catch (_) {
      return isoDate;
    }
  }

  String _formatTime(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '—';
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return DateFormat('HH:mm').format(date);
    } catch (_) {
      return '—';
    }
  }

  /// Sur l'écran de succès, le statut est toujours en doré.
  Color _statusColor(String? s) => kMisonGold;

  String _statusLabel(String? s) {
    switch (s) {
      case 'PENDING':                      return 'Recherche d\'ouvrier';
      case 'ACCEPTED':                     return 'Ouvrier trouvé';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'En attente de paiement';
      case 'IN_PROGRESS':                  return 'Intervention en cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'En attente du paiement de la prestation';
      case 'COMPLETED':                    return 'Prestation terminée';
      case 'CANCELLED':                    return 'Commande annulée';
      default:                             return s ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) DashboardScreen().launch(context, isNewTask: true);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        // Logo centré + fond de la page, comme les autres pages
        appBar: const MisonAppBar(),
        body: DotGridBackground(
          child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                // ── Icône succès ─────────────────────────────────────────
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutBack,
                  builder: (_, circle, child) => Transform.scale(
                    scale: circle,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: completed.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: child,
                    ),
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 900),
                    // La coche arrive après le rond, avec un petit rebond
                    curve: const Interval(0.35, 1, curve: Curves.elasticOut),
                    builder: (_, check, __) => Transform.scale(
                      scale: check,
                      child: Icon(Icons.check_circle_rounded,
                          size: 62, color: completed),
                    ),
                  ),
                ),
                24.height,

                Text('Demande envoyée !',
                    style: boldTextStyle(size: 26),
                    textAlign: TextAlign.center),
                10.height,
                Text(
                  'Votre demande a bien été enregistrée.\nUn ouvrier vous sera assigné prochainement.',
                  style: secondaryTextStyle(size: 14),
                  textAlign: TextAlign.center,
                ),
                32.height,

                // ── Carte détails ─────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: boxDecorationDefault(
                    color: context.cardColor,
                    borderRadius: radius(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(serviceName, style: boldTextStyle(size: 17)),
                      16.height,

                      // "Tout de suite" : l'heure prévue est fictive (création + 30 min),
                      // on affiche l'heure à laquelle la commande a été passée.
                      _Row(
                        icon: Icons.calendar_today_outlined,
                        label: 'Date',
                        value: _formatDate(order.isImmediate ? order.createdAt : order.serviceDate),
                      ),
                      12.height,
                      _Row(
                        icon: Icons.access_time_rounded,
                        label: order.isImmediate ? 'Commandée à' : 'Heure',
                        value: _formatTime(order.isImmediate ? order.createdAt : order.serviceDate),
                      ),
                      12.height,
                      _Row(
                        icon: Icons.location_on_outlined,
                        label: 'Adresse',
                        value: order.serviceAddress ?? '—',
                      ),

                      const Divider(height: 28),

                      // Statut
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Statut', style: secondaryTextStyle()),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: _statusColor(order.status)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _statusLabel(order.status),
                              style: boldTextStyle(
                                  size: 14,
                                  color: _statusColor(order.status)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                24.height,

                // ── Bannière info ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kMisonGold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: kMisonGold.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: kMisonGold, size: 20),
                      12.width,
                      Expanded(
                        child: Text(
                          'Vous recevrez une notification dès qu\'un ouvrier accepte votre demande.',
                          style: secondaryTextStyle(size: 15),
                        ),
                      ),
                    ],
                  ),
                ),

                40.height,

                // ── Boutons ───────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: 'Accueil',
                        color: context.cardColor,
                        textColor: textPrimaryColorGlobal,
                        shapeBorder: RoundedRectangleBorder(
                          borderRadius: radius(12),
                          side: BorderSide(color: borderColor),
                        ),
                        onTap: () => DashboardScreen()
                            .launch(context, isNewTask: true),
                      ),
                    ),
                    16.width,
                    Expanded(
                      child: AppButton(
                        text: 'Mes commandes',
                        color: kMisonGold,
                        textColor: Colors.white,
                        shapeBorder: RoundedRectangleBorder(
                            borderRadius: radius(12)),
                        onTap: () => DashboardScreen(redirectToBooking: true)
                            .launch(context, isNewTask: true),
                      ),
                    ),
                  ],
                ),
                16.height,
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Row({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: Colors.grey),
        10.width,
        Text('$label :', style: secondaryTextStyle()),
        8.width,
        Expanded(
          child: Text(
            value,
            style: boldTextStyle(size: 15),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
