import 'dart:convert';

import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

/// Écran affichant tous les services Mison comme catégories
/// Design: grille avec icônes circulaires
class MisonCategoryScreen extends StatefulWidget {
  const MisonCategoryScreen({super.key});

  @override
  State<MisonCategoryScreen> createState() => _MisonCategoryScreenState();
}

class _MisonCategoryScreenState extends State<MisonCategoryScreen> {
  List<MisonService> services = [];
  bool isLoading = true;
  String? errorMessage;
  final TextEditingController searchCont = TextEditingController();
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  @override
  void dispose() {
    searchCont.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final token = getStringAsync(TOKEN);
      final response = await http.get(
        Uri.parse('https://api.mison.app/api/services'),
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
          errorMessage = 'Erreur de chargement';
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarWidget(
        "Service",
        textColor: Colors.white,
        textSize: APP_BAR_TEXT_SIZE,
        color: primaryColor,
        systemUiOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarColor: primaryColor,
        ),
        showBack: true,
        backWidget: BackWidget(),
      ),
      body: _buildBody(),
    );
  }

  List<MisonService> get _filteredServices {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return services;

    return services.where((service) {
      return service.name.validate().toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(errorMessage!, style: secondaryTextStyle()),
            16.height,
            ElevatedButton(
              onPressed: _loadServices,
              child: Text(language.reload),
            ),
          ],
        ),
      );
    }

    if (services.isEmpty) {
      return Center(
        child: Text('Aucune catégorie disponible', style: secondaryTextStyle()),
      );
    }

    final filteredServices = _filteredServices;

    return AnimatedScrollView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      onSwipeRefresh: () async {
        await _loadServices();
        return await 1.seconds.delay;
      },
      children: [
        AppTextField(
          controller: searchCont,
          textFieldType: TextFieldType.OTHER,
          onChanged: (value) {
            setState(() {
              searchQuery = value;
            });
          },
          decoration: InputDecoration(
            hintText: 'Rechercher un service',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      searchCont.clear();
                      setState(() {
                        searchQuery = '';
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: context.cardColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: primaryColor, width: 1.2),
            ),
          ),
        ),
        16.height,
        if (filteredServices.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text(
                'Aucun service trouvé',
                style: secondaryTextStyle(),
              ),
            ),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 22,
            children: filteredServices
                .map((service) => _buildCategoryItem(service))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildCategoryItem(MisonService service) {
    final itemWidth = (context.width() - 56) / 3; // 3 items per row

    return GestureDetector(
      onTap: () {
        MisonBookingFormScreen(service: service).launch(context);
      },
      child: SizedBox(
        width: itemWidth,
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getColorForService(service.name ?? '')
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getColorForService(service.name ?? '')
                      .withValues(alpha: 0.35),
                  width: 1.1,
                ),
              ),
              child: service.imageUrl != null && service.imageUrl!.isNotEmpty
                  ? CachedImageWidget(
                      url: service.imageUrl!,
                      fit: BoxFit.cover,
                      width: 56,
                      height: 56,
                      circle: true,
                    )
                  : Icon(
                      _getIconForService(service.name ?? ''),
                      size: 34,
                      color: _getColorForService(service.name ?? ''),
                    ),
            ),
            10.height,
            Text(
              service.name.validate(),
              style: primaryTextStyle(size: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorForService(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('maçon') || name.contains('macon')) return Colors.orange;
    if (name.contains('plomb')) return Colors.blue;
    if (name.contains('électr') || name.contains('electr')) return Colors.amber;
    if (name.contains('menuis')) return Colors.brown;
    if (name.contains('carrel')) return Colors.teal;
    if (name.contains('ferron') || name.contains('ferraill')) return Colors.red;
    if (name.contains('peintr') || name.contains('peinture'))
      return Colors.pink;
    if (name.contains('climati') || name.contains('froid')) return Colors.cyan;
    if (name.contains('mecan')) return Colors.grey;
    return primaryColor;
  }

  IconData _getIconForService(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('maçon') || name.contains('macon'))
      return Icons.construction;
    if (name.contains('plomb')) return Icons.plumbing;
    if (name.contains('électr') || name.contains('electr'))
      return Icons.electrical_services;
    if (name.contains('menuis')) return Icons.carpenter;
    if (name.contains('carrel')) return Icons.grid_on;
    if (name.contains('ferron') || name.contains('ferraill'))
      return Icons.hardware;
    if (name.contains('peintr') || name.contains('peinture'))
      return Icons.format_paint;
    if (name.contains('climati') || name.contains('froid'))
      return Icons.ac_unit;
    if (name.contains('mecan')) return Icons.build;
    return Icons.handyman;
  }
}
