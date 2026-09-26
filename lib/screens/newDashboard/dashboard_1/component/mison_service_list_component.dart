import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/view_all_label_component.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_search_service_screen.dart';
import 'package:booking_system_flutter/component/mison_page_loader.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../booking/mison_booking_form_screen.dart';

/// Liste verticale des services Mison sur l'accueil : cartes pleine largeur
/// (image, nom, description complète), qui défilent avec la page.
class MisonServiceListComponent extends StatefulWidget {
  const MisonServiceListComponent({super.key});

  @override
  MisonServiceListComponentState createState() => MisonServiceListComponentState();
}

class MisonServiceListComponentState extends State<MisonServiceListComponent> {
  List<MisonService> services = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() { isLoading = true; errorMessage = null; });
    try {
      final response = await getMisonServices();
      setState(() {
        services = response.data ?? [];
        isLoading = false;
      });
    } catch (e) {
      setState(() { errorMessage = 'Erreur: $e'; isLoading = false; });
    }
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: const MisonPageLoader(),
      );
    }

    if (errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(top: 16),
        child: Center(
          child: Column(
            children: [
              Text(errorMessage!, style: secondaryTextStyle()),
              8.height,
              TextButton(
                onPressed: _loadServices,
                child: Text(language.reload),
              ),
            ],
          ),
        ),
      );
    }

    if (services.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(top: 16),
        child: Center(
          child: Text('Aucun service disponible', style: secondaryTextStyle()),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      margin: const EdgeInsets.only(top: 16),
      width: context.width(),
      // Pas de fond : la section repose directement sur le fond de la page
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          16.height,
          ViewAllLabel(
            label: language.services,
            labelSize: 17,
            list: services,
            usePillStyle: true,
            alwaysShowViewAll: true,
            onTap: () {
              const MisonSearchServiceScreen().launch(context);
            },
          ).paddingSymmetric(horizontal: 16),
          // Défilement vertical avec la page (plus de carrousel horizontal).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              children: [
                for (final service in services) ...[
                  _MisonServiceCard(service: service),
                  16.height,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte individuelle de service Mison
class _MisonServiceCard extends StatelessWidget {
  final MisonService service;

  const _MisonServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        MisonBookingFormScreen(service: service).launch(context);
      },
      child: Container(
        width: double.infinity,
        // Hauteur libre : la carte s'adapte à la description complète.
        decoration: boxDecorationWithRoundedCorners(
          borderRadius: radius(),
          backgroundColor: context.cardColor,
          border: appStore.isDarkMode ? Border.all(color: context.dividerColor) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image du service
            SizedBox(
              height: 180,
              width: double.infinity,
              child: Stack(
                children: [
                  CachedImageWidget(
                    url: service.imageUrl ?? '',
                    fit: BoxFit.cover,
                    height: 180,
                    width: context.width(),
                    circle: false,
                  ).cornerRadiusWithClipRRectOnly(
                    topRight: defaultRadius.toInt(),
                    topLeft: defaultRadius.toInt(),
                  ),
                  // Badge disponibilité
                  if (service.isAvailable == true)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: boxDecorationWithShadow(
                          backgroundColor: const Color.fromARGB(255, 255, 255, 255).withValues(alpha: 0.9),
                          borderRadius: radius(24),
                        ),
                        child: Text(
                          'DISPONIBLE',
                          style: boldTextStyle(color: const Color.fromARGB(255, 2, 2, 2), size: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Contenu textuel
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                16.height,
                // Nom du service
                Text(
                  service.name.validate(),
                  style: boldTextStyle(size: 16),
                ).paddingSymmetric(horizontal: 16),
                // Description complète, sans coupure
                if (service.description.validate().isNotEmpty) ...[
                  8.height,
                  Text(
                    service.description.validate(),
                    style: secondaryTextStyle(size: 14),
                  ).paddingSymmetric(horizontal: 16),
                ],
                16.height,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
