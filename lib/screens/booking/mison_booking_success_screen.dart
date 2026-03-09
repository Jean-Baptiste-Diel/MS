import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

/// Écran de succès après création d'une commande Mison
/// Correspond au design Figma "Thank you"
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
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd MMM yyyy', 'fr_FR').format(date);
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        DashboardScreen().launch(context, isNewTask: true);
        return false;
      },
      child: Scaffold(
        backgroundColor: context.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarIconBrightness: appStore.isDarkMode ? Brightness.light : Brightness.dark,
            statusBarColor: Colors.transparent,
          ),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Success icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: completed.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    size: 60,
                    color: completed,
                  ),
                ),
                
                24.height,
                
                // Thank you text
                Text(
                  'Thank You!',
                  style: boldTextStyle(size: 28),
                ),
                8.height,
                Text(
                  'Your booking is confirmed.',
                  style: secondaryTextStyle(size: 14),
                ),
                
                32.height,
                
                // Booking details card
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
                      // Service name
                      Text(
                        serviceName,
                        style: boldTextStyle(size: 18),
                      ),
                      
                      16.height,
                      
                      // Date & Time
                      _DetailRow(
                        icon: Icons.calendar_today,
                        label: 'Date',
                        value: _formatDate(order.serviceDate),
                      ),
                      12.height,
                      _DetailRow(
                        icon: Icons.access_time,
                        label: 'Heure',
                        value: _formatTime(order.serviceDate),
                      ),
                      12.height,
                      _DetailRow(
                        icon: Icons.location_on,
                        label: 'Adresse',
                        value: order.serviceAddress ?? '',
                      ),
                      
                      const Divider(height: 32),
                      
                      // Payment info
                      _DetailRow(
                        icon: Icons.payment,
                        label: 'Payment Mode',
                        value: paymentMethod,
                      ),
                      12.height,
                      _DetailRow(
                        icon: Icons.receipt,
                        label: 'Total',
                        value: '100F', // Frais de booking
                        valueColor: primaryColor,
                      ),
                      
                      const Divider(height: 32),
                      
                      // Status
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: boxDecorationDefault(
                              color: _getStatusColor(order.status).withOpacity(0.1),
                              borderRadius: radius(20),
                            ),
                            child: Text(
                              _getStatusLabel(order.status),
                              style: boldTextStyle(
                                size: 12,
                                color: _getStatusColor(order.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                32.height,
                
                // Info message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: boxDecorationDefault(
                    color: secondaryPrimaryColor,
                    borderRadius: radius(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: primaryColor),
                      12.width,
                      Expanded(
                        child: Text(
                          'Booking Time And Date',
                          style: primaryTextStyle(size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                
                40.height,
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: 'Go To Home',
                        color: context.cardColor,
                        textColor: textPrimaryColorGlobal,
                        shapeBorder: RoundedRectangleBorder(
                          borderRadius: radius(12),
                          side: BorderSide(color: borderColor),
                        ),
                        onTap: () {
                          DashboardScreen().launch(context, isNewTask: true);
                        },
                      ),
                    ),
                    16.width,
                    Expanded(
                      child: AppButton(
                        text: 'Go To Review',
                        color: primaryColor,
                        textColor: Colors.white,
                        shapeBorder: RoundedRectangleBorder(borderRadius: radius(12)),
                        onTap: () {
                          // TODO: Navigate to booking detail screen
                          DashboardScreen(redirectToBooking: true).launch(context, isNewTask: true);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        return 'Artisan assigné';
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
}

/// Widget for detail row
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        12.width,
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: secondaryTextStyle()),
              Text(
                value,
                style: boldTextStyle(
                  size: 14,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
