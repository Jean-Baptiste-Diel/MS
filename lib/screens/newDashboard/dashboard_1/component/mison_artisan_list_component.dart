import 'package:booking_system_flutter/utils/image_cache_key.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:booking_system_flutter/component/mison_view_all_button.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_artisan_detail_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_artisan_list_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

class MisonArtisanListComponent extends StatefulWidget {
  const MisonArtisanListComponent({super.key});

  @override
  State<MisonArtisanListComponent> createState() => _MisonArtisanListComponentState();
}

class _MisonArtisanListComponentState extends State<MisonArtisanListComponent> {
  List<MisonArtisanInfo> artisans = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    try {
      final res = await getMisonArtisans();
      setState(() { artisans = res.data ?? []; isLoading = false; });
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  @override
  void setState(fn) { if (mounted) super.setState(fn); }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          itemCount: 4,
          separatorBuilder: (_, __) => 12.width,
          itemBuilder: (_, __) => _ArtisanCardSkeleton(),
        ),
      );
    }
    if (artisans.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nos prestataires', style: boldTextStyle(size: 17)),
                  2.height,
                  Text('Choisissez votre expert', style: secondaryTextStyle(size: 14)),
                ],
              ),
              // Bouton « Voir tout › » doré de l'accueil
              MisonViewAllButton(
                onTap: () => const MisonArtisanListScreen().launch(context),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: artisans.length,
            separatorBuilder: (_, __) => 12.width,
            itemBuilder: (_, i) => ArtisanCard(artisan: artisans[i]),
          ),
        ),
        16.height,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card partagée (utilisée aussi dans MisonArtisanListScreen)
// ─────────────────────────────────────────────────────────────────────────────

/// Initiale du prénom de l'ouvrier, en doré (quand il n'y a pas de photo).
Widget _initial(MisonArtisanInfo artisan) => Center(
      child: Text(
        artisan.fullName.isNotEmpty ? artisan.fullName[0].toUpperCase() : '?',
        style: boldTextStyle(color: kMisonGold, size: 24),
      ),
    );

class ArtisanCard extends StatelessWidget {
  final MisonArtisanInfo artisan;
  final double width;

  const ArtisanCard({super.key, required this.artisan, this.width = 155});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => MisonArtisanDetailScreen(artisan: artisan).launch(context),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kMisonGold.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            // Photo (initiale dorée si absente ou en erreur)
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kMisonGold.withValues(alpha: 0.07),
                border: Border.all(color: kMisonGold.withValues(alpha: 0.18), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: (artisan.profilePictureUrl ?? '').trim().isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: artisan.profilePictureUrl!.trim(),
                      cacheKey: imageCacheKey(artisan.profilePictureUrl!.trim()),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _initial(artisan),
                    )
                  : _initial(artisan),
            ),
            10.height,

            // Nom
            Text(
              artisan.fullName,
              style: boldTextStyle(size: 15),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            5.height,

            // Service pill
            if (artisan.service?.name != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kMisonGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  artisan.service!.name!,
                  style: boldTextStyle(color: kMisonGold, size: 10),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
            6.height,

            // Note + expérience
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (artisan.averageRating != null) ...[
                  Icon(Icons.star_rounded, size: 13, color: ratingBarColor),
                  2.width,
                  Text(artisan.rating.toStringAsFixed(1),
                      style: boldTextStyle(size: 13, color: ratingBarColor)),
                  if (artisan.experienceYears != null) ...[
                    6.width,
                    Container(width: 3, height: 3,
                        decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.4),
                            shape: BoxShape.circle)),
                    6.width,
                  ],
                ],
                if (artisan.experienceYears != null)
                  Text('${artisan.experienceYears} ans', style: secondaryTextStyle(size: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton chargement
// ─────────────────────────────────────────────────────────────────────────────

class _ArtisanCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final grey = Colors.grey.withValues(alpha: 0.12);
    return Container(
      width: 155,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 62, height: 62, decoration: BoxDecoration(shape: BoxShape.circle, color: grey)),
          10.height,
          Container(height: 12, width: 100, decoration: BoxDecoration(color: grey, borderRadius: BorderRadius.circular(6))),
          6.height,
          Container(height: 10, width: 70, decoration: BoxDecoration(color: grey, borderRadius: BorderRadius.circular(6))),
          6.height,
          Container(height: 10, width: 80, decoration: BoxDecoration(color: grey, borderRadius: BorderRadius.circular(6))),
        ],
      ),
    );
  }
}
