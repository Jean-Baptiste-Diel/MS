import 'package:booking_system_flutter/component/mison_service_image_header.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/nominatim_address_field.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/booking/mison_confirm_booking_screen.dart';
import 'package:booking_system_flutter/services/location_service.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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
  /// Étape affichée sous le champ pendant « Ma position ».
  String? _locateStep;
  /// Précision (m) de la position trouvée, affichée une fois l'adresse remplie.
  double? _locatedAccuracy;

  /// « Ma position » : remplit la zone d'intervention avec l'adresse actuelle.
  ///
  /// 1. Seule l'autorisation de localisation est demandée.
  /// 2. Une position récente déjà connue du téléphone s'affiche tout de suite ;
  ///    sinon le GPS est interrogé, 12 s au plus (repli : dernière position).
  /// 3. L'adresse est retrouvée à partir de la position ; si elle ne l'est pas,
  ///    la position est quand même gardée (« Ma position actuelle »).
  Future<void> _fillZoneWithCurrentLocation() async {
    if (_isLocatingZone) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLocatingZone = true;
      _locateStep = 'Localisation en cours…';
      _locatedAccuracy = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        TopToast.show(message: 'Activez la localisation de votre téléphone, puis réessayez.');
        await Geolocator.openLocationSettings();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        TopToast.show(message: 'Autorisez la localisation de Mison dans les réglages du téléphone.');
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        TopToast.show(message: 'Localisation refusée : saisissez votre adresse.');
        return;
      }

      // Position récente (moins de 2 min) : immédiate, inutile d'attendre le GPS.
      Position? position = await Geolocator.getLastKnownPosition();
      final recent = position != null &&
          DateTime.now().difference(position.timestamp) < const Duration(minutes: 2) &&
          position.accuracy <= 100;
      if (!recent) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12),
            ),
          );
        } catch (_) {
          // GPS trop long (intérieur) : dernière position connue, si elle existe.
          if (position == null) rethrow;
          TopToast.show(message: 'Position approximative : vérifiez l\'adresse.');
        }
      }
      if (!mounted) return;

      setState(() => _locateStep = 'Recherche de l\'adresse…');
      String address;
      try {
        address = await buildFullAddressFromLatLong(position.latitude, position.longitude)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        address = 'Ma position actuelle';
      }
      if (!mounted) return;

      setState(() {
        zoneCont.text = address;
        zoneLat = position!.latitude;
        zoneLon = position.longitude;
        _locatedAccuracy = position.accuracy;
      });
    } catch (e) {
      log(e);
      TopToast.show(message: 'Impossible de récupérer votre position. Saisissez votre adresse.');
    } finally {
      if (mounted) {
        setState(() {
          _isLocatingZone = false;
          _locateStep = null;
        });
      }
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
              primary: kMisonGold,
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
      // Non envoyée : pour "Tout de suite", le serveur fixe lui-même l'heure (is_immediate).
      return DateTime.now().toIso8601String();
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
      // Logo centré + fond de la page, comme les autres pages
      appBar: MisonAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kMisonDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: DotGridBackground(
        child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image du service (coins arrondis), nom écrit dessus
              _buildServiceHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              
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
                    color: kMisonGold,
                    text: 'Continuer',
                    textColor: Colors.white,
                    shapeBorder: RoundedRectangleBorder(borderRadius: radius(12)),
                    onTap: _continueToConfirmation,
                  ),
                  16.height,
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// Image du service avec son nom écrit dessus (composant commun).
  Widget _buildServiceHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: MisonServiceImageHeader(
        service: widget.service,
        fallbackIcon: _getIconForService(widget.service.name ?? ''),
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
              color: isSelected ? kMisonGold : Colors.transparent,
              borderRadius: radius(8),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: kMisonGold.withValues(alpha: 0.35),
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
        // Grille de 4 colonnes égales : les créneaux occupent toute la largeur
        LayoutBuilder(builder: (context, constraints) {
          const columns = 4;
          const spacing = 8.0;
          final slotWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: timeSlots.map((slot) {
            final isSelected = selectedTime != null && 
                             '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}' == slot;
            
            return GestureDetector(
              onTap: () => _selectTime(slot),
              child: Container(
                width: slotWidth,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: boxDecorationDefault(
                  color: isSelected ? kMisonGold : context.cardColor,
                  borderRadius: radius(8),
                  border: Border.all(
                    color: isSelected ? kMisonGold : borderColor,
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
          );
        }),
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
            // Commandes : suggestions limitées à la région de Dakar (Sénégal).
            countryCodes: const ['sn'],
            bbox: kDakarRegionBbox,
            onSelected: (s) => setState(() {
              zoneLat = s.lat;
              zoneLon = s.lon;
              _locatedAccuracy = null; // adresse choisie dans les suggestions
            }),
            // « Ma position » en toutes lettres (plutôt qu'une icône de cible).
            suffixButton: Padding(
              padding: const EdgeInsets.only(right: 4),
              // Le bouton garde son texte (grisé) pendant la recherche : la
              // progression s'affiche sous le champ, pas en cercle ici.
              child: TextButton(
                onPressed: _isLocatingZone ? null : _fillZoneWithCurrentLocation,
                style: TextButton.styleFrom(
                  foregroundColor: kMisonGold,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Ma position',
                  style: boldTextStyle(size: 13, color: _isLocatingZone ? Colors.grey : kMisonGold),
                ),
              ),
            ),
          ),
        ),
        if (_locateStep != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2, right: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: kMisonGold,
                    backgroundColor: kMisonGold.withValues(alpha: 0.15),
                  ),
                ),
                6.height,
                Row(
                  children: [
                    const Icon(Icons.location_searching_rounded, size: 14, color: kMisonGold),
                    6.width,
                    Text(_locateStep!, style: secondaryTextStyle(size: 13, color: kMisonGold)),
                  ],
                ),
              ],
            ),
          )
        else if (zoneLat != null && zoneLon != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: Colors.green.shade600),
                6.width,
                Text(
                  _locatedAccuracy != null
                      ? 'Position détectée (à ~${_locatedAccuracy!.round()} m près)'
                      : 'Adresse localisée sur la carte',
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
        Text('Description (facultative)', style: boldTextStyle(size: 16)),
        8.height,
        AppTextField(
          controller: descriptionCont,
          textFieldType: TextFieldType.MULTILINE,
          isValidationRequired: false,
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
          _PromiseItem(icon: Icons.security, text: 'Garanti par Mison Service et payer en toute sécurité'),
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
          color: isSelected ? kMisonGold : context.cardColor,
          borderRadius: radius(8),
          border: Border.all(
            color: isSelected ? kMisonGold : borderColor,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : kMisonGold,
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
          Icon(icon, color: kMisonGold, size: 16),
          8.width,
          Expanded(
            child: Text(text, style: secondaryTextStyle(size: 14)),
          ),
        ],
      ),
    );
  }
}

