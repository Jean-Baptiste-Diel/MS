import 'dart:convert';

import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/view_all_label_component.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/booking/mison_search_service_screen.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

import '../../../booking/mison_booking_form_screen.dart';

/// Component displaying Mison services as categories with the original CategoryWidget design.
/// Each service from the API is displayed as a category with circular icon and name.
class MisonCategoryComponent extends StatefulWidget {
  const MisonCategoryComponent({super.key});

  @override
  MisonCategoryComponentState createState() => MisonCategoryComponentState();
}

class MisonCategoryComponentState extends State<MisonCategoryComponent> {
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
      final response = await http.get(
        Uri.parse('${BASE_URL}services'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final servicesResponse = MisonServicesResponse.fromJson(data);
        setState(() {
          services = servicesResponse.data ?? [];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Erreur de chargement des services';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur de connexion';
        isLoading = false;
      });
    }
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  Widget _buildServiceWidget(BuildContext context, MisonService service) {
    return SizedBox(
      width: context.width() / 4 - 20,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: appStore.isDarkMode ? Colors.white24 : context.cardColor,
              shape: BoxShape.circle,
            ),
            child: CachedImageWidget(
              url: service.imageUrl ?? '',
              fit: BoxFit.cover,
              width: 40,
              height: 40,
              circle: true,
              placeHolderImage: '',
            ),
          ),
          4.height,
          Marquee(
            directionMarguee: DirectionMarguee.oneDirection,
            child: Text(
              service.name.validate(),
              style: primaryTextStyle(size: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      ).paddingAll(16);
    }

    if (errorMessage != null) {
      return Center(
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
      ).paddingAll(16);
    }

    if (services.isEmpty) {
      return const Offstage();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ViewAllLabel(
          label: language.lblCategory,
          labelSize: 17,
          list: services,
          usePillStyle: true,
          alwaysShowViewAll: true,
          onTap: () {
            const MisonSearchServiceScreen().launch(context);
          },
        ).paddingSymmetric(horizontal: 16),
        AnimatedWrap(
          spacing: 16,
          runSpacing: 16,
          itemCount: services.length,
          itemBuilder: (ctx, i) {
            final service = services[i];
            return GestureDetector(
              onTap: () {
                MisonBookingFormScreen(service: service).launch(context);
              },
              child: _buildServiceWidget(context, service),
            );
          },
        ).paddingSymmetric(horizontal: 16),
      ],
    );
  }
}
