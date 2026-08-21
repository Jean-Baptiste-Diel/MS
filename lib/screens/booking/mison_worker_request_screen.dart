import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/nominatim_address_field.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_success_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class MisonWorkerRequestScreen extends StatefulWidget {
  const MisonWorkerRequestScreen({Key? key}) : super(key: key);

  @override
  State<MisonWorkerRequestScreen> createState() =>
      _MisonWorkerRequestScreenState();
}

class _MisonWorkerRequestScreenState extends State<MisonWorkerRequestScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _descriptionCont = TextEditingController();
  final TextEditingController _addressCont = TextEditingController();
  final TextEditingController _workerCountCont =
      TextEditingController(text: '1');

  MisonService? _selectedService;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void dispose() {
    _descriptionCont.dispose();
    _addressCont.dispose();
    _workerCountCont.dispose();
    super.dispose();
  }

  Future<void> _pickService() async {
    final service = await Navigator.push<MisonService>(
      context,
      MaterialPageRoute(
        builder: (_) => const _ServicePickerScreen(),
      ),
    );
    if (service != null) setState(() => _selectedService = service);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('fr'),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  String get _formattedDate {
    if (_selectedDate == null) return 'Choisir une date';
    return '${_selectedDate!.day.toString().padLeft(2, '0')}/'
        '${_selectedDate!.month.toString().padLeft(2, '0')}/'
        '${_selectedDate!.year}';
  }

  String get _formattedTime {
    if (_selectedTime == null) return 'Choisir une heure';
    return '${_selectedTime!.hour.toString().padLeft(2, '0')}:'
        '${_selectedTime!.minute.toString().padLeft(2, '0')}';
  }

  String? _buildIso() {
    if (_selectedDate == null || _selectedTime == null) return null;
    return DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    ).toUtc().toIso8601String();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedService == null) {
      TopToast.show(message: 'Veuillez sélectionner un service');
      return;
    }
    if (_selectedDate == null || _selectedTime == null) {
      TopToast.show(message: 'Veuillez sélectionner une date et une heure');
      return;
    }

    hideKeyboard(context);
    appStore.setLoading(true);

    try {
      final request = MisonWorkerRequestModel(
        service: _selectedService!.id ?? '',
        workerCount: int.tryParse(_workerCountCont.text.trim()) ?? 1,
        description: _descriptionCont.text.trim(),
        serviceDate: _buildIso()!,
        serviceAddress: _addressCont.text.trim(),
      );
      final res = await createWorkerRequest(request);
      appStore.setLoading(false);
      if (!mounted) return;
      MisonBookingSuccessScreen(
        order: res.data ?? MisonOrder(),
        serviceName: _selectedService!.name ?? 'Demande d\'ouvrier',
        paymentMethod: '',
      ).launch(context, isNewTask: true);
    } catch (e) {
      appStore.setLoading(false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => hideKeyboard(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBarWidget(
          'Demande d\'ouvrier',
          textColor: Colors.white,
          textSize: 18,
          color: primaryColor,
          systemUiOverlayStyle: SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            statusBarColor: context.primaryColor,
          ),
          showBack: true,
          backWidget: BackWidget(),
        ),
        body: DotGridBackground(
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Service ──────────────────────────────────────────────
                Text('Service *', style: boldTextStyle(size: 16)),
                8.height,
                GestureDetector(
                  onTap: _pickService,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedService == null
                            ? borderColor
                            : primaryColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_selectedService?.imageUrl != null)
                          CachedImageWidget(
                            url: _selectedService!.imageUrl!,
                            width: 28,
                            height: 28,
                            radius: 14,
                          ).paddingRight(10),
                        Expanded(
                          child: Text(
                            _selectedService?.name ?? 'Choisir un service',
                            style: _selectedService == null
                                ? secondaryTextStyle()
                                : primaryTextStyle(),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down,
                            color: _selectedService == null
                                ? Colors.grey
                                : primaryColor),
                      ],
                    ),
                  ),
                ),
                20.height,

                // ── Nombre d'ouvriers ────────────────────────────────────
                Text('Nombre d\'ouvriers *', style: boldTextStyle(size: 16)),
                8.height,
                Row(
                  children: [
                    _CounterButton(
                      icon: Icons.remove,
                      onTap: () {
                        final val =
                            int.tryParse(_workerCountCont.text) ?? 1;
                        if (val > 1) {
                          _workerCountCont.text = (val - 1).toString();
                        }
                      },
                    ),
                    Expanded(
                      child: AppTextField(
                        textFieldType: TextFieldType.PHONE,
                        controller: _workerCountCont,
                        textAlign: TextAlign.center,
                        isValidationRequired: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: inputDecoration(context),
                        validator: (val) {
                          if (val == null || val.isEmpty)
                            return language.requiredText;
                          final n = int.tryParse(val);
                          if (n == null || n < 1)
                            return 'Minimum 1 ouvrier';
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    _CounterButton(
                      icon: Icons.add,
                      onTap: () {
                        final val =
                            int.tryParse(_workerCountCont.text) ?? 1;
                        _workerCountCont.text = (val + 1).toString();
                      },
                    ),
                  ],
                ),
                20.height,

                // ── Description ──────────────────────────────────────────
                Text('Description *', style: boldTextStyle(size: 16)),
                8.height,
                AppTextField(
                  textFieldType: TextFieldType.MULTILINE,
                  controller: _descriptionCont,
                  minLines: 4,
                  maxLines: 6,
                  isValidationRequired: true,
                  decoration: inputDecoration(
                    context,
                    hintText: 'Décrivez le travail à effectuer...',
                  ).copyWith(alignLabelWithHint: true),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty)
                      return language.requiredText;
                    if (val.trim().length < 10)
                      return 'Minimum 10 caractères';
                    return null;
                  },
                ),
                20.height,

                // ── Date ─────────────────────────────────────────────────
                Text('Date d\'intervention *', style: boldTextStyle(size: 16)),
                8.height,
                _PickerField(
                  icon: Icons.calendar_today_outlined,
                  label: _formattedDate,
                  hasValue: _selectedDate != null,
                  onTap: _pickDate,
                ),
                20.height,

                // ── Heure ────────────────────────────────────────────────
                Text('Heure d\'intervention *', style: boldTextStyle(size: 16)),
                8.height,
                _PickerField(
                  icon: Icons.access_time,
                  label: _formattedTime,
                  hasValue: _selectedTime != null,
                  onTap: _pickTime,
                ),
                20.height,

                // ── Adresse ──────────────────────────────────────────────
                Text('Adresse d\'intervention *',
                    style: boldTextStyle(size: 16)),
                8.height,
                Container(
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: NominatimAddressField(
                    controller: _addressCont,
                    hintText: 'Rechercher une adresse...',
                    countryCodes: const ['sn', 'ml', 'ci', 'bf', 'gn', 'ne', 'tg', 'bj', 'mr', 'gm'],
                    decoration: InputDecoration(
                      hintText: 'Rechercher une adresse...',
                      hintStyle: secondaryTextStyle(),
                      prefixIcon: Icon(Icons.location_on_outlined, color: primaryColor, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
                32.height,

                AppButton(
                  text: 'Envoyer la demande',
                  color: primaryColor,
                  textColor: Colors.white,
                  width: context.width(),
                  onTap: _submit,
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

// ─── Widgets helpers ──────────────────────────────────────────────────────────

class _PickerField extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool hasValue;
  final VoidCallback onTap;

  const _PickerField({
    required this.icon,
    required this.label,
    required this.hasValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: hasValue ? primaryColor : borderColor),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: hasValue ? primaryColor : Colors.grey),
            12.width,
            Text(
              label,
              style:
                  hasValue ? primaryTextStyle() : secondaryTextStyle(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CounterButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: primaryColor, size: 20),
      ),
    );
  }
}

// ─── Écran de sélection de service (retourne MisonService) ───────────────────

class _ServicePickerScreen extends StatefulWidget {
  const _ServicePickerScreen();

  @override
  State<_ServicePickerScreen> createState() => _ServicePickerScreenState();
}

class _ServicePickerScreenState extends State<_ServicePickerScreen> {
  late Future<List<MisonService>> _future;

  @override
  void initState() {
    super.initState();
    _future = getMisonServices().then((r) => r.data ?? []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBarWidget(
        'Choisir un service',
        textColor: Colors.white,
        textSize: 18,
        color: primaryColor,
        showBack: true,
        backWidget: BackWidget(),
      ),
      body: DotGridBackground(
        child: FutureBuilder<List<MisonService>>(
          future: _future,
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text(snap.error.toString()));
            }
            final services = snap.data ?? [];
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: services.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = services[i];
                return ListTile(
                  leading: s.imageUrl != null
                      ? CachedImageWidget(
                          url: s.imageUrl!,
                          width: 40,
                          height: 40,
                          radius: 8,
                        )
                      : Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.handyman,
                              color: primaryColor, size: 20),
                        ),
                  title: Text(s.name ?? '', style: primaryTextStyle()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, s),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
