import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/booking/mison_confirm_booking_screen.dart';
import 'package:booking_system_flutter/screens/map/osm_map_screen.dart';
import 'package:booking_system_flutter/screens/map/google_place_map_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:intl/intl.dart';

/// Écran formulaire de commande Mison
/// Correspond au design Figma "Onboarding_001"
class MisonBookingFormScreen extends StatefulWidget {
  final MisonService service;

  const MisonBookingFormScreen({Key? key, required this.service}) : super(key: key);

  @override
  State<MisonBookingFormScreen> createState() => _MisonBookingFormScreenState();
}

class _MisonBookingFormScreenState extends State<MisonBookingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final TextEditingController descriptionCont = TextEditingController();
  final TextEditingController zoneCont = TextEditingController();
  
  // Zone coordinates
  double? zoneLat;
  double? zoneLon;
  
  // Date/Time selection
  bool isImmediateService = true; // "Tout de suite" vs "Plus tard"
  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  
  // Payment method
  String selectedPaymentMethod = 'wave';
  
  @override
  void dispose() {
    descriptionCont.dispose();
    zoneCont.dispose();
    super.dispose();
  }

  // ignore: unused_element
  void _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: context.cardColor,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  void _selectTime(String timeSlot) {
    // Parse time slot like "09:00"
    final parts = timeSlot.split(':');
    if (parts.length == 2) {
      setState(() {
        selectedTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      });
    }
  }

  // ignore: unused_element
  String _formatSelectedDate() {
    if (selectedDate == null) return '';
    return DateFormat('dd MMM yyyy', 'fr_FR').format(selectedDate!);
  }

  String _getServiceDateISO() {
    if (isImmediateService) {
      return DateTime.now().add(const Duration(minutes: 30)).toIso8601String();
    }
    
    if (selectedDate != null && selectedTime != null) {
      final dateTime = DateTime(
        selectedDate!.year,
        selectedDate!.month,
        selectedDate!.day,
        selectedTime!.hour,
        selectedTime!.minute,
      );
      return dateTime.toIso8601String();
    }
    
    return DateTime.now().toIso8601String();
  }

  void _continueToConfirmation() {
    if (_formKey.currentState!.validate()) {
      if (!isImmediateService && (selectedDate == null || selectedTime == null)) {
        toast('Veuillez sélectionner une date et une heure');
        return;
      }
      
      if (zoneCont.text.isEmpty) {
        toast('Veuillez sélectionner une zone d\'intervention');
        return;
      }

      // Navigate to confirmation screen
      MisonConfirmBookingScreen(
        service: widget.service,
        description: descriptionCont.text,
        zone: zoneCont.text,
        serviceDate: _getServiceDateISO(),
        isImmediate: isImmediateService,
        paymentMethod: selectedPaymentMethod,
      ).launch(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarWidget(
        widget.service.name ?? '',
        textColor: appStore.isDarkMode ? Colors.white : Colors.black,
        color: context.scaffoldBackgroundColor,
        elevation: 0,
        systemUiOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: appStore.isDarkMode ? Brightness.light : Brightness.dark,
          statusBarColor: context.scaffoldBackgroundColor,
        ),
        showBack: true,
        backWidget: BackWidget(iconColor: context.iconColor),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Service info
              _buildServiceHeader(),
              24.height,
              
              // Date selection
              _buildDateSection(),
              24.height,
              
              // Calendar & Time (if "Plus tard")
              if (!isImmediateService) ...[
                _buildCalendarSection(),
                16.height,
                _buildTimeSlots(),
                24.height,
              ],
              
              // Zone selection
              _buildZoneDropdown(),
              16.height,
              
              // Description
              _buildDescriptionField(),
              24.height,
              
              // Payment methods
              _buildPaymentMethods(),
              24.height,
              
              // Promise section
              _buildPromiseSection(),
              24.height,
              
              // Continue button
              AppButton(
                width: context.width(),
                color: primaryColor,
                text: 'Continuer',
                textColor: Colors.white,
                shapeBorder: RoundedRectangleBorder(borderRadius: radius(12)),
                onTap: _continueToConfirmation,
              ),
              16.height,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceHeader() {
    return Center(
      // Ajoutez Center ici
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // Correction ici
        mainAxisSize: MainAxisSize
            .min, // Pour que la Column prenne juste la hauteur nécessaire
        children: [
          // Service icon centered
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: widget.service.imageUrl != null &&
                    widget.service.imageUrl!.isNotEmpty
                ? CachedImageWidget(
                    url: widget.service.imageUrl!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.contain,
                  ).center()
                : Icon(_getIconForService(widget.service.name ?? ''),
                    size: 40, color: primaryColor),
          ),
          16.height,
          // Service name
          Text(
            widget.service.name ?? '',
            style: boldTextStyle(size: 20),
            textAlign: TextAlign.center,
          ),
          4.height,
          // Price
          Text(
            'à partir de ${widget.service.minPrice ?? '0'}F',
            style: secondaryTextStyle(),
            textAlign: TextAlign.center,
          ),
          4.height,
          // Duration
          Text(
            '~ 30mn',
            style: secondaryTextStyle(size: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  IconData _getIconForService(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('électr') || name.contains('electr')) return Icons.electrical_services;
    if (name.contains('plomb')) return Icons.plumbing;
    if (name.contains('maçon') || name.contains('macon')) return Icons.construction;
    if (name.contains('menuis')) return Icons.carpenter;
    if (name.contains('peintr')) return Icons.format_paint;
    if (name.contains('carrel')) return Icons.grid_on;
    if (name.contains('climati') || name.contains('froid')) return Icons.ac_unit;
    if (name.contains('mecan')) return Icons.build;
    return Icons.handyman;
  }

  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choisir la date prévue pour les travaux',
          style: boldTextStyle(size: 14),
        ),
        12.height,
        Row(
          children: [
            Expanded(
              child: _DateToggleButton(
                label: 'Tout de suite',
                icon: Icons.flash_on,
                isSelected: isImmediateService,
                onTap: () => setState(() => isImmediateService = true),
              ),
            ),
            12.width,
            Expanded(
              child: _DateToggleButton(
                label: 'Plus tard',
                icon: Icons.calendar_today,
                isSelected: !isImmediateService,
                onTap: () => setState(() => isImmediateService = false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choisir une date et heure',
          style: boldTextStyle(size: 14),
        ),
        12.height,
        // Month navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {},
            ),
            Text(
              DateFormat('MMMM', 'fr_FR').format(selectedDate ?? DateTime.now()).capitalizeFirstLetter(),
              style: boldTextStyle(),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {},
            ),
          ],
        ),
        8.height,
        // Week days header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam']
              .map((day) => Text(day, style: secondaryTextStyle(size: 12)))
              .toList(),
        ),
        8.height,
        // Calendar (simplified - shows current week)
        _buildWeekCalendar(),
      ],
    );
  }

  Widget _buildWeekCalendar() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(7, (index) {
        final date = startOfWeek.add(Duration(days: index));
        final isSelected = selectedDate?.day == date.day && 
                          selectedDate?.month == date.month &&
                          selectedDate?.year == date.year;
        final isPast = date.isBefore(DateTime.now().subtract(const Duration(days: 1)));
        
        return GestureDetector(
          onTap: isPast ? null : () {
            setState(() {
              selectedDate = date;
            });
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected ? primaryColor : Colors.transparent,
              borderRadius: radius(8),
            ),
            child: Center(
              child: Text(
                '${date.day}',
                style: primaryTextStyle(
                  color: isSelected 
                      ? Colors.white 
                      : isPast 
                          ? Colors.grey 
                          : null,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTimeSlots() {
    final timeSlots = ['09:00', '10:00', '11:00', '12:00', '14:00', '15:00', '16:00', '17:00'];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choisir l\'heure', style: boldTextStyle(size: 14)),
        12.height,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: timeSlots.map((slot) {
            final isSelected = selectedTime != null && 
                             '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}' == slot;
            
            return GestureDetector(
              onTap: () => _selectTime(slot),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: boxDecorationDefault(
                  color: isSelected ? primaryColor : context.cardColor,
                  borderRadius: radius(8),
                  border: Border.all(
                    color: isSelected ? primaryColor : borderColor,
                  ),
                ),
                child: Text(
                  slot,
                  style: primaryTextStyle(
                    color: isSelected ? Colors.white : null,
                    size: 14,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _openZonePicker() async {
    final result = await const GooglePlaceMapScreen().launch(context);
    if (result == null || result is! Map<String, dynamic>) return;

    if (result['use_map'] == true) {
      final mapResult = await const OsmMapScreen().launch(context);
      if (mapResult != null && mapResult is Map<String, dynamic>) {
        setState(() {
          zoneCont.text = mapResult['name'] ?? '';
          zoneLat = mapResult['lat'] as double?;
          zoneLon = mapResult['lon'] as double?;
        });
      }
      return;
    }

    setState(() {
      zoneCont.text = result['name'] ?? '';
      zoneLat = result['lat'] as double?;
      zoneLon = result['lon'] as double?;
    });
  }

  Widget _buildZoneDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Zone d\'intervention', style: boldTextStyle(size: 14)),
        8.height,
        GestureDetector(
          onTap: _openZonePicker,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 20,
                  color: zoneCont.text.isNotEmpty ? primaryColor : grey,
                ),
                10.width,
                Expanded(
                  child: Text(
                    zoneCont.text.isNotEmpty
                        ? zoneCont.text
                        : 'Rechercher une adresse...',
                    style: zoneCont.text.isNotEmpty
                        ? primaryTextStyle(size: 14)
                        : secondaryTextStyle(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.search, size: 18, color: grey),
              ],
            ),
          ),
        ),
        if (zoneLat != null && zoneLon != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Row(
              children: [
                Icon(Icons.gps_fixed_rounded, size: 12, color: Colors.green.shade600),
                4.width,
                Text(
                  '${zoneLat!.toStringAsFixed(4)}, ${zoneLon!.toStringAsFixed(4)}',
                  style: secondaryTextStyle(size: 11, color: Colors.green.shade600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Description', style: boldTextStyle(size: 14)),
        8.height,
        AppTextField(
          controller: descriptionCont,
          textFieldType: TextFieldType.MULTILINE,
          minLines: 3,
          maxLines: 5,
          decoration: inputDecoration(context).copyWith(
            hintText: 'Description du service',
            fillColor: context.cardColor,
            filled: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethods() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choisir un moyen de paiement pour voir les coordonnées de l\'ouvrier',
          style: boldTextStyle(size: 14),
        ),
        16.height,
        _PaymentMethodTile(
          assetPath: orange_money_logo,
          icon: Icons.account_balance_wallet,
          label: 'Payer par Orange Money',
          iconColor: Colors.orange,
          isSelected: selectedPaymentMethod == 'orange_money',
          onTap: () => setState(() => selectedPaymentMethod = 'orange_money'),
        ),
        8.height,
        _PaymentMethodTile(
          assetPath: wave_logo,
          icon: Icons.waves,
          label: 'Payer par Wave',
          iconColor: Colors.blue,
          isSelected: selectedPaymentMethod == 'wave',
          onTap: () => setState(() => selectedPaymentMethod = 'wave'),
        ),
      ],
    );
  }

  Widget _buildPromiseSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: boxDecorationDefault(
        color: context.cardColor,
        borderRadius: radius(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notre promesse client', style: boldTextStyle(size: 14)),
          12.height,
          _PromiseItem(icon: Icons.check_circle, text: 'Annulation possible à tout moment avant le rendez-vous'),
          _PromiseItem(icon: Icons.access_time, text: 'Disponible 24h/24'),
          _PromiseItem(icon: Icons.security, text: 'Garanti par 3R Mison et payer en toute sécurité'),
          _PromiseItem(icon: Icons.lock, text: 'Un paiement sûr et sécurisé'),
        ],
      ),
    );
  }

}

/// Toggle button for date selection (Tout de suite / Plus tard)
class _DateToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _DateToggleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: boxDecorationDefault(
          color: isSelected ? primaryColor : context.cardColor,
          borderRadius: radius(8),
          border: Border.all(
            color: isSelected ? primaryColor : borderColor,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : primaryColor,
            ),
            8.width,
            Text(
              label,
              style: primaryTextStyle(
                color: isSelected ? Colors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Payment method tile
class _PaymentMethodTile extends StatelessWidget {
  final IconData? icon;
  final String? assetPath;
  final String label;
  final Color iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    this.icon,
    this.assetPath,
    required this.label,
    required this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: boxDecorationDefault(
          color: context.cardColor,
          borderRadius: radius(8),
          border: Border.all(
            color: isSelected ? primaryColor : borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            if (assetPath != null)
              Image.asset(
                assetPath!,
                width: 24,
                height: 24,
                errorBuilder: (_, __, ___) => Icon(icon ?? Icons.payment, color: iconColor, size: 24),
              )
            else
              Icon(icon ?? Icons.payment, color: iconColor, size: 24),
            12.width,
            Expanded(child: Text(label, style: primaryTextStyle())),
            if (isSelected)
              Icon(Icons.check_circle, color: primaryColor, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Promise item
class _PromiseItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PromiseItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryColor, size: 16),
          8.width,
          Expanded(
            child: Text(text, style: secondaryTextStyle(size: 12)),
          ),
        ],
      ),
    );
  }
}

