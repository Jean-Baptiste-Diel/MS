import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/nominatim_address_field.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/booking/mison_confirm_booking_screen.dart';
import 'package:booking_system_flutter/services/location_service.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:intl/intl.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

/// Écran formulaire de commande Mison
/// Correspond au design Figma "Onboarding_001"
class MisonBookingFormScreen extends StatefulWidget {
  final MisonService service;
  final String? artisanId;

  const MisonBookingFormScreen({Key? key, required this.service, this.artisanId}) : super(key: key);

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

  bool _isLocatingZone = false;

  Future<void> _fillZoneWithCurrentLocation() async {
    setState(() => _isLocatingZone = true);
    try {
      final granted = await Permissions.cameraFilesAndLocationPermissionsGranted();
      await setValue(PERMISSION_STATUS, granted);
      if (!granted || !mounted) return;

      final position = await getUserLocationPosition();
      final address = await buildFullAddressFromLatLong(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() {
        zoneCont.text = address;
        zoneLat = position.latitude;
        zoneLon = position.longitude;
      });
    } catch (e) {
      log(e);
      TopToast.show(message: 'Impossible de récupérer votre position');
    } finally {
      if (mounted) setState(() => _isLocatingZone = false);
    }
  }

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
        TopToast.show(message: 'Veuillez sélectionner une date et une heure');
        return;
      }
      
      if (zoneCont.text.isEmpty) {
        TopToast.show(message: 'Veuillez sélectionner une zone d\'intervention');
        return;
      }

      // Navigate to confirmation screen
      MisonConfirmBookingScreen(
        service: widget.service,
        description: descriptionCont.text,
        zone: zoneCont.text,
        serviceDate: _getServiceDateISO(),
        isImmediate: isImmediateService,
        latitude: zoneLat,
        longitude: zoneLon,
        artisanId: widget.artisanId,
      ).launch(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
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
        backWidget: BackWidget(iconColor: Colors.black),
      ),
      body: DotGridBackground(
        child: Form(
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
          // Duration
          Text(
            '~ 30mn',
            style: secondaryTextStyle(size: 14),
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
          style: boldTextStyle(size: 16),
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
          style: boldTextStyle(size: 16),
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
              .map((day) => Text(day, style: secondaryTextStyle(size: 13)))
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
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
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
        Text('Choisir l\'heure', style: boldTextStyle(size: 16)),
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
                    size: 16,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildZoneDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Zone d\'intervention', style: boldTextStyle(size: 16)),
        8.height,
        Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: NominatimAddressField(
            controller: zoneCont,
            hintText: 'Rechercher une adresse...',
            countryCodes: const ['sn', 'ml', 'ci', 'bf', 'gn', 'ne', 'tg', 'bj', 'mr', 'gm'],
            onSelected: (s) => setState(() {
              zoneLat = s.lat;
              zoneLon = s.lon;
            }),
            suffixButton: IconButton(
              onPressed: _isLocatingZone ? null : _fillZoneWithCurrentLocation,
              icon: _isLocatingZone
                  ? SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                    )
                  : Icon(Icons.my_location_rounded, color: primaryColor, size: 20),
              tooltip: 'Utiliser ma position actuelle',
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
                  style: secondaryTextStyle(size: 13, color: Colors.green.shade600),
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
        Text('Description', style: boldTextStyle(size: 16)),
        8.height,
        AppTextField(
          controller: descriptionCont,
          textFieldType: TextFieldType.MULTILINE,
          minLines: 3,
          maxLines: 5,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
          decoration: inputDecoration(context).copyWith(
            hintText: 'Description du service',
            fillColor: context.cardColor,
            filled: true,
          ),
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
          Text('Notre promesse client', style: boldTextStyle(size: 16)),
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
            child: Text(text, style: secondaryTextStyle(size: 14)),
          ),
        ],
      ),
    );
  }
}

