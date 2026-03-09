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
  final String projectName;
  final String description;
  final String zone;
  final String serviceDate;
  final bool isImmediate;
  final String paymentMethod;

  const MisonConfirmBookingScreen({
    Key? key,
    required this.service,
    required this.projectName,
    required this.description,
    required this.zone,
    required this.serviceDate,
    required this.isImmediate,
    required this.paymentMethod,
  }) : super(key: key);

  @override
  State<MisonConfirmBookingScreen> createState() => _MisonConfirmBookingScreenState();
}

class _MisonConfirmBookingScreenState extends State<MisonConfirmBookingScreen> {
  bool isLoading = false;
  
  // Frais de réservation (à ajuster selon le backend)
  final num bookingFee = 100;

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
        description: '${widget.projectName}\n\n${widget.description}',
        serviceDate: widget.serviceDate,
        serviceAddress: widget.zone,
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
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: radius(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header orange
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: primaryColor,
              child: Text(
                'Services',
                style: boldTextStyle(color: Colors.white, size: 16),
                textAlign: TextAlign.center,
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Checkmark icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.green,
                      size: 40,
                    ),
                  ),
                  16.height,
                  Text(
                    'Confirm Booking',
                    style: boldTextStyle(size: 18),
                  ),
                  8.height,
                  Text(
                    'Do You Want To Confirm The Booking ?',
                    style: secondaryTextStyle(),
                    textAlign: TextAlign.center,
                  ),
                  24.height,
                  // Date and Time row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Date', style: secondaryTextStyle(size: 12)),
                            4.height,
                            Text(
                              widget.isImmediate ? 'Maintenant' : _formatDate(widget.serviceDate),
                              style: boldTextStyle(size: 14),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: borderColor,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Time', style: secondaryTextStyle(size: 12)),
                            4.height,
                            Text(
                              widget.isImmediate ? '--:--' : _formatTime(widget.serviceDate),
                              style: boldTextStyle(size: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  16.height,
                  const Divider(),
                  16.height,
                  // Frais De Booking
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Frais De Booking', style: secondaryTextStyle()),
                      Text('${bookingFee}F', style: boldTextStyle(color: primaryColor)),
                    ],
                  ),
                  8.height,
                  // Frais De Déplacement (barré)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Frais De Déplacement', style: secondaryTextStyle()),
                      Text(
                        '2 000F',
                        style: secondaryTextStyle().copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  16.height,
                  // Note
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: boxDecorationDefault(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: radius(8),
                    ),
                    child: Text(
                      'En cliquant sur "Valider", j\'atteste avoir lu et accepter les Conditions Générales d\'Utilisation.',
                      style: secondaryTextStyle(size: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  24.height,
                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: radius(8)),
                            side: BorderSide(color: borderColor),
                          ),
                          child: Text('Cancel', style: primaryTextStyle()),
                        ),
                      ),
                      12.width,
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _confirmBooking();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: radius(8)),
                          ),
                          child: Text('Confirm', style: boldTextStyle(color: Colors.white)),
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
                      
                      // Frais de réservation
                      _SummaryRow(
                        label: 'Frais De Booking',
                        value: '${bookingFee}F',
                        valueStyle: boldTextStyle(color: primaryColor),
                      ),
                      16.height,
                      
                      // Prix minimum service (info)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: boxDecorationDefault(
                          color: secondaryPrimaryColor,
                          borderRadius: radius(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: primaryColor, size: 20),
                            12.width,
                            Expanded(
                              child: Text(
                                'Le tarif final sera confirmé par l\'artisan. Prix minimum: ${widget.service.minPrice ?? '0'}F',
                                style: secondaryTextStyle(size: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
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
  final TextStyle? valueStyle;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: secondaryTextStyle()),
        Text(value, style: valueStyle ?? boldTextStyle(size: 14)),
      ],
    );
  }
}
