import 'dart:convert';

import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/view_all_label_component.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/category/mison_category_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

import '../../../booking/mison_booking_form_screen.dart';

/// Composant affichant la liste horizontale des services Mison avec
/// image, description, prix minimum - Design identique à ServiceListDashboardComponent1
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
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final token = getStringAsync(TOKEN);
      debugPrint('MisonServiceListComponent: Loading services...');
      final response = await http.get(
        Uri.parse('https://api.mison.app/api/services'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      debugPrint('MisonServiceListComponent: Response status: ${response.statusCode}');
      debugPrint('MisonServiceListComponent: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final servicesResponse = MisonServicesResponse.fromJson(data);
        debugPrint('MisonServiceListComponent: Loaded ${servicesResponse.data?.length ?? 0} services');
        setState(() {
          services = servicesResponse.data ?? [];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Erreur ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MisonServiceListComponent: Error: $e');
      setState(() {
        errorMessage = 'Erreur: $e';
        isLoading = false;
      });
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
        child: const Center(child: CircularProgressIndicator()),
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
      decoration: BoxDecoration(
        color: appStore.isDarkMode ? context.cardColor : context.primaryColor.withOpacity(0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          16.height,
          ViewAllLabel(
            label: language.services,
            list: services,
            trailingTextStyle: boldTextStyle(color: primaryColor, size: 12),
            alwaysShowViewAll: true,
            onTap: () {
              const MisonCategoryScreen().launch(context);
            },
          ).paddingSymmetric(horizontal: 16),
          HorizontalList(
            itemCount: services.length,
            spacing: 16,
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 26, top: 8),
            itemBuilder: (context, index) => _MisonServiceCard(
              service: services[index],
              width: 280,
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
  final double width;

  const _MisonServiceCard({
    required this.service,
    this.width = 280,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        MisonBookingFormScreen(service: service).launch(context);
      },
      child: Container(
        width: width,
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
              width: width,
              child: Stack(
                children: [
                  CachedImageWidget(
                    url: service.imageUrl ?? '',
                    fit: BoxFit.cover,
                    height: 180,
                    width: width,
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
                          backgroundColor: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.9),
                          borderRadius: radius(24),
                        ),
                        child: Text(
                          'DISPONIBLE',
                          style: boldTextStyle(color: const Color.fromARGB(255, 2, 2, 2), size: 10),
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
                Marquee(
                  directionMarguee: DirectionMarguee.oneDirection,
                  child: Text(
                    service.name.validate(),
                    style: boldTextStyle(size: 16),
                  ),
                ).paddingSymmetric(horizontal: 16),
                8.height,
                // Description (si disponible)
                if (service.description != null && service.description!.isNotEmpty)
                  Text(
                    service.description!,
                    style: secondaryTextStyle(size: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ).paddingSymmetric(horizontal: 16),
                12.height,
                // Prix minimum
                Row(
                  children: [
                    Text(
                      'À partir de ',
                      style: secondaryTextStyle(size: 12),
                    ),
                    Text(
                      '${service.minPriceValue.toStringAsFixed(0)} FCFA',
                      style: boldTextStyle(color: primaryColor, size: 14),
                    ),
                  ],
                ).paddingSymmetric(horizontal: 16),
                16.height,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
