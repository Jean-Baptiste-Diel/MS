import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class MisonArtisanDetailScreen extends StatelessWidget {
  final MisonArtisanInfo artisan;

  const MisonArtisanDetailScreen({Key? key, required this.artisan}) : super(key: key);

  MisonService get _service => MisonService(
        id: artisan.service?.id,
        name: artisan.service?.name,
        minPrice: artisan.service?.minPrice,
        imageUrl: artisan.service?.imageUrl,
        isAvailable: artisan.isAvailable,
      );

  void _book(BuildContext context) {
    if (artisan.service?.id == null) {
      TopToast.show(message: 'Aucun service disponible pour ce prestataire');
      return;
    }
    MisonBookingFormScreen(
      service: _service,
      artisanId: artisan.id,
    ).launch(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Logo centré + fond de la page, comme les autres pages
      appBar: MisonAppBar(
        title: 'Profil prestataire',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kMisonDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: DotGridBackground(
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Carte identité ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Photo de profil (icône dorée si absente ou en erreur)
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kMisonGold.withValues(alpha: 0.1),
                            border: Border.all(color: kMisonGold.withValues(alpha: 0.35), width: 2),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (artisan.profilePictureUrl ?? '').trim().isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: artisan.profilePictureUrl!.trim(),
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: kMisonGold),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.person_rounded, color: kMisonGold, size: 40),
                                )
                              : const Icon(Icons.person_rounded, color: kMisonGold, size: 40),
                        ),
                        16.width,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(artisan.fullName,
                                  style: boldTextStyle(size: 21, color: kMisonDark),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              if (artisan.service?.name != null) ...[
                                4.height,
                                Row(children: [
                                  Icon(Icons.handyman_rounded,
                                      size: 13, color: kMisonGold),
                                  4.width,
                                  Text(artisan.service!.name!,
                                      style: primaryTextStyle(
                                          size: 15, color: kMisonGold)),
                                ]),
                              ],
                              if (artisan.averageRating != null) ...[
                                6.height,
                                Row(children: [
                                  Icon(Icons.star_rounded,
                                      size: 15, color: ratingBarColor),
                                  4.width,
                                  Text(
                                    '${artisan.rating.toStringAsFixed(1)} (${artisan.totalReviews ?? 0} avis)',
                                    style: boldTextStyle(
                                        size: 15, color: ratingBarColor),
                                  ),
                                ]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  20.height,

                  // ── Infos ────────────────────────────────────────────────
                  _InfoCard(children: [
                    if (artisan.experienceYears != null)
                      _InfoRow(
                        icon: Icons.work_outline_rounded,
                        label: 'Expérience',
                        value: '${artisan.experienceYears} ans',
                      ),
                    if (artisan.address != null &&
                        artisan.address!.isNotEmpty) ...[
                      if (artisan.experienceYears != null)
                        const Divider(height: 1, indent: 48),
                      _InfoRow(
                        icon: Icons.location_on_outlined,
                        label: 'Zone',
                        value: artisan.address!,
                      ),
                    ],
                    if (artisan.isAvailable != null) ...[
                      const Divider(height: 1, indent: 48),
                      _InfoRow(
                        icon: artisan.isAvailable == true
                            ? Icons.check_circle_outline_rounded
                            : Icons.cancel_outlined,
                        label: 'Disponibilité',
                        value: artisan.isAvailable == true
                            ? 'Disponible'
                            : 'Indisponible',
                        valueColor: artisan.isAvailable == true
                            ? Colors.green
                            : Colors.red,
                      ),
                    ],
                  ]),

                  if (artisan.professionName != null && artisan.professionName!.isNotEmpty) ...[
                    16.height,
                    _InfoCard(children: [
                      _InfoRow(
                        icon: Icons.notes_rounded,
                        label: 'À propos',
                        value: artisan.professionName!,
                      ),
                    ]),
                  ],

                  32.height,

                  // ── Bouton commander ─────────────────────────────────────
                  AppButton(
                    width: double.infinity,
                    color: kMisonGold,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shapeBorder: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    onTap: () => _book(context),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_task_rounded,
                            color: Colors.white, size: 20),
                        8.width,
                        Text('Commander ce prestataire',
                            style: boldTextStyle(color: Colors.white, size: 15)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
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
  final Color? valueColor;

  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
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
                    style: boldTextStyle(size: 16, color: valueColor),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
