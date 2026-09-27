import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/view_all_label_component.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_search_service_screen.dart';
import 'package:booking_system_flutter/component/mison_page_loader.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../booking/mison_booking_form_screen.dart';

/// Services Mison sur l'accueil : grille de 2 colonnes (image, nom,
/// description), qui défile avec la page.
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
      final list = response.data ?? [];
      final ordered = await _sortByClientHabits(list);
      setState(() {
        services = ordered;
        isLoading = false;
      });
    } catch (e) {
      setState(() { errorMessage = 'Erreur: $e'; isLoading = false; });
    }
  }

  /// Services que le client commande régulièrement : en premier, du plus
  /// commandé au moins commandé. Les autres gardent leur ordre habituel.
  /// Sans connexion (ou si l'historique est indisponible), ordre inchangé.
  Future<List<MisonService>> _sortByClientHabits(List<MisonService> list) async {
    if (!appStore.isLoggedIn || appStore.userType != USER_TYPE_USER) return list;
    try {
      final orders = (await getMisonOrders()).data ?? [];
      final counts = <String, int>{};
      for (final order in orders) {
        final id = order.service?.id;
        if (id != null && id.isNotEmpty) counts[id] = (counts[id] ?? 0) + 1;
      }
      if (counts.isEmpty) return list;
      final indexed = list.asMap().entries.toList()
        ..sort((a, b) {
          final byCount = (counts[b.value.id] ?? 0).compareTo(counts[a.value.id] ?? 0);
          return byCount != 0 ? byCount : a.key.compareTo(b.key); // tri stable
        });
      return indexed.map((e) => e.value).toList();
    } catch (_) {
      return list;
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
          // Grille de 2 colonnes, qui défile avec la page.
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            itemCount: services.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              // Hauteur fixe : image + nom (2 lignes) + description (3 lignes)
              mainAxisExtent: 232,
            ),
            itemBuilder: (context, index) => _MisonServiceCard(service: services[index]),
          ),
        ],
      ),
    );
  }
}

/// Carte de service dans la grille de l'accueil (2 colonnes).
class _MisonServiceCard extends StatelessWidget {
  final MisonService service;

  const _MisonServiceCard({required this.service});

  static const double _imageHeight = 112;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        MisonBookingFormScreen(service: service).launch(context);
      },
      child: Container(
        decoration: boxDecorationWithRoundedCorners(
          borderRadius: radius(),
          backgroundColor: context.cardColor,
          border: appStore.isDarkMode ? Border.all(color: context.dividerColor) : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image du service
            SizedBox(
              height: _imageHeight,
              width: double.infinity,
              child: Stack(
                children: [
                  CachedImageWidget(
                    url: service.imageUrl ?? '',
                    fit: BoxFit.cover,
                    height: _imageHeight,
                    width: context.width() / 2,
                    circle: false,
                  ),
                  // Badge disponibilité
                  if (service.isAvailable == true)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: boxDecorationWithShadow(
                          backgroundColor: Colors.white.withValues(alpha: 0.9),
                          borderRadius: radius(24),
                        ),
                        child: Text('DISPONIBLE', style: boldTextStyle(color: Colors.black, size: 9)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name.validate(),
                    style: boldTextStyle(size: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (service.description.validate().isNotEmpty) ...[
                    4.height,
                    Text(
                      service.description.validate(),
                      style: secondaryTextStyle(size: 12, height: 1.3),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
