import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_success_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// Écran de confirmation de commande Mison
/// Affiche le récapitulatif et confirme la commande via l'API
class MisonConfirmBookingScreen extends StatefulWidget {
  final MisonService service;
  final String description;
  final String zone;
  final String serviceDate;
  final bool isImmediate;
  final String paymentMethod;
  final double? latitude;
  final double? longitude;
  final String? artisanId;

  const MisonConfirmBookingScreen({
    Key? key,
    required this.service,
    required this.description,
    required this.zone,
    required this.serviceDate,
    required this.isImmediate,
    required this.paymentMethod,
    this.latitude,
    this.longitude,
    this.artisanId,
  }) : super(key: key);

  @override
  State<MisonConfirmBookingScreen> createState() => _MisonConfirmBookingScreenState();
}

class _MisonConfirmBookingScreenState extends State<MisonConfirmBookingScreen> {
  bool isLoading = false;
  
  // Frais de réservation (à ajuster selon le backend)

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd MMM yyyy', 'fr_FR').format(date);
    } catch (e) {
      return isoDate;
    }
  }

  String _formatTime(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('HH:mm').format(date);
    } catch (e) {
      return '';
    }
  }

  String _getPaymentMethodLabel() {
    switch (widget.paymentMethod) {
      case 'wave':
        return 'Wave';
      case 'orange_money':
        return 'Orange Money';
      case 'max':
        return 'Max';
      case 'solde':
        return 'Solde';
      default:
        return widget.paymentMethod;
    }
  }

  Future<void> _confirmBooking() async {
    setState(() => isLoading = true);

    try {
      // Créer la commande via l'API
      final request = MisonCreateOrderRequest(
        service: widget.service.id ?? '',
        description: widget.description,
        serviceDate: widget.serviceDate,
        serviceAddress: widget.zone,
        latitude: widget.latitude,
        longitude: widget.longitude,
        artisanId: widget.artisanId,
      );

      final response = await createMisonOrder(request);
      
      setState(() => isLoading = false);

      if (response.data != null) {
        final order = response.data!;
        
        // Vérifier si le backend renvoie une URL de redirection pour le paiement
        // Pour l'instant, on navigue directement vers l'écran de succès
        // TODO: Gérer la redirection paiement selon la réponse backend
        
        // Si paiement Wave/Orange Money, le backend pourrait renvoyer une URL
        // await _handlePaymentRedirect(response);
        
        // Navigation vers l'écran de succès
        MisonBookingSuccessScreen(
          order: order,
          serviceName: widget.service.name ?? '',
          paymentMethod: _getPaymentMethodLabel(),
        ).launch(context, isNewTask: true);
      } else {
        toast(response.message ?? 'Erreur lors de la création de la commande');
      }
    } catch (e) {
      setState(() => isLoading = false);
      toast('Erreur: ${e.toString()}');
    }
  }

  // ignore: unused_element
  Future<void> _handlePaymentRedirect(String? paymentUrl) async {
    if (paymentUrl != null && paymentUrl.isNotEmpty) {
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header gradient
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor, primaryColor.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.receipt_long_rounded,
                          color: Colors.white, size: 28),
                    ),
                    12.height,
                    Text(
                      'Confirmer la commande',
                      style: boldTextStyle(color: Colors.white, size: 17),
                    ),
                    6.height,
                    Text(
                      widget.service.name ?? '',
                      style: secondaryTextStyle(color: Colors.white.withOpacity(0.85), size: 13),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date & Heure chips
                    Row(
                      children: [
                        _InfoChip(
                          icon: Icons.calendar_today_rounded,
                          label: 'Date',
                          value: widget.isImmediate
                              ? 'Maintenant'
                              : _formatDate(widget.serviceDate),
                        ),
                        12.width,
                        if (!widget.isImmediate)
                          _InfoChip(
                            icon: Icons.access_time_rounded,
                            label: 'Heure',
                            value: _formatTime(widget.serviceDate),
                          ),
                      ],
                    ),
                    16.height,

                    // Zone
                    _DetailRow(
                      icon: Icons.location_on_rounded,
                      label: 'Zone',
                      value: widget.zone,
                    ),
                    12.height,

                    // Paiement
                    _DetailRow(
                      icon: Icons.payment_rounded,
                      label: 'Paiement',
                      value: _getPaymentMethodLabel(),
                    ),
                    12.height,

                    // Frais de déplacement
                    _DetailRow(
                      icon: Icons.directions_car_rounded,
                      label: 'Frais de déplacement',
                      value: '2 000 F',
                    ),
                    20.height,

                    // CGU note
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: primaryColor.withOpacity(0.15)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: primaryColor, size: 16),
                          8.width,
                          Expanded(
                            child: Text(
                              'En validant, j\'accepte les Conditions Générales d\'Utilisation de Mison.',
                              style: secondaryTextStyle(size: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    24.height,

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: borderColor),
                            ),
                            child: Text('Annuler', style: primaryTextStyle(size: 14)),
                          ),
                        ),
                        12.width,
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmBooking();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('Valider',
                                style: boldTextStyle(color: Colors.white, size: 14)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      appBar: appBarWidget(
        'Confirmer le paiement',
        textColor: Colors.white,
        color: primaryColor,
        systemUiOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarColor: primaryColor,
        ),
        showBack: true,
        backWidget: BackWidget(),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary card
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
                      // Service
                      _SummaryRow(
                        label: 'Service',
                        value: widget.service.name ?? '',
                      ),
                      const Divider(height: 24),
                      
                      // Date
                      _SummaryRow(
                        label: 'Date',
                        value: widget.isImmediate 
                            ? 'Immédiat' 
                            : _formatDate(widget.serviceDate),
                      ),
                      const Divider(height: 24),
                      
                      // Heure
                      if (!widget.isImmediate) ...[
                        _SummaryRow(
                          label: 'Heure',
                          value: _formatTime(widget.serviceDate),
                        ),
                        const Divider(height: 24),
                      ],
                      
                      // Zone
                      _SummaryRow(
                        label: 'Zone',
                        value: widget.zone,
                      ),
                      const Divider(height: 24),
                      
                      // Payment method
                      _SummaryRow(
                        label: 'Méthode de paiement',
                        value: _getPaymentMethodLabel(),
                      ),
                      const Divider(height: 24),
                    ],
                  ),
                ),
                
                24.height,
                
                // Note
                Text(
                  'En cliquant sur "Confirmer", j\'accepte tout litige j\'accepte de me soumettre a la decision de Mison',
                  style: secondaryTextStyle(size: 12),
                  textAlign: TextAlign.center,
                ),
                
                32.height,
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: 'Annuler',
                        color: context.cardColor,
                        textColor: textPrimaryColorGlobal,
                        shapeBorder: RoundedRectangleBorder(
                          borderRadius: radius(12),
                          side: BorderSide(color: borderColor),
                        ),
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    16.width,
                    Expanded(
                      child: AppButton(
                        text: 'Confirmer',
                        color: primaryColor,
                        textColor: Colors.white,
                        shapeBorder: RoundedRectangleBorder(borderRadius: radius(12)),
                        onTap: _showConfirmDialog,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Loading overlay
          if (isLoading)
            Container(
              color: Colors.black26,
              child: Center(child: LoaderWidget()),
            ),
            
          Observer(
            builder: (context) => LoaderWidget().visible(appStore.isLoading.validate()),
          ),
        ],
      ),
    );
  }
}

/// Widget for summary row
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: secondaryTextStyle()),
        8.width,
        Flexible(
          child: Text(
            value,
            style: boldTextStyle(size: 14),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: primaryColor),
            10.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: secondaryTextStyle(size: 11)),
                  2.height,
                  Text(value, style: boldTextStyle(size: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: primaryColor),
        10.width,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: secondaryTextStyle(size: 11)),
              2.height,
              Text(value, style: boldTextStyle(size: 13), maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}
