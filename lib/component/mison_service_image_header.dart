import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Image du service (coins arrondis comme le carrousel de l'accueil)
/// avec son nom écrit dessus. Utilisée par le formulaire et la confirmation
/// de commande.
class MisonServiceImageHeader extends StatelessWidget {
  final MisonService service;

  /// Icône affichée quand le service n'a pas d'image.
  final IconData fallbackIcon;

  static const double height = 200;

  const MisonServiceImageHeader({
    Key? key,
    required this.service,
    this.fallbackIcon = Icons.handyman_rounded,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasImage = service.imageUrl != null && service.imageUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            hasImage
                ? CachedImageWidget(
                    url: service.imageUrl!,
                    width: context.width(),
                    height: height,
                    fit: BoxFit.cover,
                  )
                : Container(
                    color: kMisonGold.withValues(alpha: 0.15),
                    child: Icon(fallbackIcon, size: 64, color: kMisonGold),
                  ),
            // Dégradé sombre en bas pour que le nom reste lisible
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65),
                  ],
                  stops: const [0.45, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Text(
                service.name ?? '',
                style: boldTextStyle(size: 24, color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
