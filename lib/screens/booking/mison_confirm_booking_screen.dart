import 'package:booking_system_flutter/component/mison_service_image_header.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_success_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class MisonConfirmBookingScreen extends StatefulWidget {
  final MisonService service;
  final String description;
  final String zone;
  final String serviceDate;
  final bool isImmediate;
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
    this.latitude,
    this.longitude,
    this.artisanId,
  }) : super(key: key);

  @override
  State<MisonConfirmBookingScreen> createState() =>
      _MisonConfirmBookingScreenState();
}

class _MisonConfirmBookingScreenState
    extends State<MisonConfirmBookingScreen> {
  bool _isLoading = false;

  String _fmtDate(String iso) {
    try {
      return DateFormat('EEEE dd MMMM yyyy', 'fr_FR')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  String _fmtTime(String iso) {
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  Future<void> _confirm() async {
    setState(() => _isLoading = true);
    try {
      final request = MisonCreateOrderRequest(
        service: widget.service.id ?? '',
        description: widget.description,
        serviceDate: widget.serviceDate,
        isImmediate: widget.isImmediate,
        serviceAddress: widget.zone,
        latitude: widget.latitude,
        longitude: widget.longitude,
        artisanId: widget.artisanId,
      );

      final response = await createMisonOrder(request);
      setState(() => _isLoading = false);

      if (response.data != null) {
        MisonBookingSuccessScreen(
          order: response.data!,
          serviceName: widget.service.name ?? '',
          paymentMethod: '',
        ).launch(context, isNewTask: true);
      } else {
        TopToast.show(message: response.message ?? 'Erreur lors de la création de la commande');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      TopToast.show(message: 'Erreur : ${e.toString()}', type: TopToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = widget.isImmediate
        ? 'Maintenant'
        : _fmtDate(widget.serviceDate);
    final timeLabel =
        widget.isImmediate ? '' : _fmtTime(widget.serviceDate);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Logo centré + fond de la page, comme les autres pages
      appBar: MisonAppBar(
        title: 'Confirmer la commande',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kMisonDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: DotGridBackground(
        child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 20, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Service ────────────────────────────────────────────
                      // Service : image arrondie avec son nom dessus
                      MisonServiceImageHeader(service: widget.service),

                      24.height,

                      // ── Détails ────────────────────────────────────────────
                      _SectionLabel(label: 'Détails de l\'intervention'),
                      12.height,
                      _InfoCard(
                        children: [
                          _InfoRow(
                            icon: Icons.calendar_today_rounded,
                            label: 'Date',
                            value: dateLabel,
                          ),
                          if (timeLabel.isNotEmpty) ...[
                            _RowDivider(),
                            _InfoRow(
                              icon: Icons.access_time_rounded,
                              label: 'Heure',
                              value: timeLabel,
                            ),
                          ],
                          _RowDivider(),
                          _InfoRow(
                            icon: Icons.location_on_rounded,
                            label: 'Adresse',
                            value: widget.zone,
                          ),
                          if (widget.description.isNotEmpty) ...[
                            _RowDivider(),
                            _InfoRow(
                              icon: Icons.notes_rounded,
                              label: 'Description',
                              value: widget.description,
                            ),
                          ],
                        ],
                      ),

                      24.height,

                      // ── Note CGU ───────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kMisonGold.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: kMisonGold.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                color: kMisonGold, size: 16),
                            10.width,
                            Expanded(
                              child: Text(
                                'En confirmant cette commande, j\'accepte les Conditions Générales d\'Utilisation de Mison et m\'engage à respecter la décision de la plateforme en cas de litige.',
                                style: secondaryTextStyle(size: 14),
                              ),
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

          // ── Bouton fixe en bas ───────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              decoration: BoxDecoration(
                color: kMisonHeaderBg, // même gris clair que la page
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: AppButton(
                text: 'Confirmer la commande',
                color: _isLoading ? Colors.grey : kMisonGold,
                disabledColor: Colors.grey,
                textColor: Colors.white,
                width: double.infinity,
                height: 52,
                shapeBorder:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: _isLoading ? null : _confirm,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              color: Colors.white, size: 20),
                          10.width,
                          Text('Confirmer la commande',
                              style: boldTextStyle(color: Colors.white, size: 16)),
                        ],
                      ),
              ),
            ),
          ),

          Observer(
            builder: (_) =>
                LoaderWidget(colors: const [kMisonDark, kMisonGold]).visible(appStore.isLoading.validate()),
          ),
        ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets utilitaires
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) =>
      Text(label, style: boldTextStyle(size: 16, color: Colors.grey));
}

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
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
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
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
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
                Text(value,
                    style: boldTextStyle(size: 16),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 48, color: Colors.grey.withValues(alpha: 0.15));
}
