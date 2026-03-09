import 'dart:convert';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_service_selection_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

/// Composant qui affiche les services Mison depuis l'API
/// Utilisé sur le dashboard pour remplacer les catégories
class MisonServicesDashboardComponent extends StatefulWidget {
  const MisonServicesDashboardComponent({Key? key}) : super(key: key);

  @override
  State<MisonServicesDashboardComponent> createState() => _MisonServicesDashboardComponentState();
}

class _MisonServicesDashboardComponentState extends State<MisonServicesDashboardComponent> {
  List<MisonService> _services = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  Future<void> _fetchServices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (appStore.token.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${appStore.token}';
      }

      final uri = Uri.parse('https://api.mison.app/api/services');
      log('Fetching services from: $uri');
      final response = await http.get(uri, headers: headers);
      log('Response status: ${response.statusCode}');
      log('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final servicesResponse = MisonServicesResponse.fromJson(body);
        setState(() {
          _services = servicesResponse.data ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Erreur ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      log('Error fetching services: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              language.category,
              style: boldTextStyle(size: 18),
            ).expand(),
            TextButton(
              onPressed: () {
                // Naviguer vers la liste complète des services
                const MisonServiceSelectionScreen().launch(context);
              },
              child: Text(
                'Voir tout',
                style: secondaryTextStyle(color: primaryColor),
              ),
            ),
          ],
        ).paddingSymmetric(horizontal: 16),
        8.height,
        _buildServicesContent(),
      ],
    );
  }

  Widget _buildServicesContent() {
    if (_isLoading) {
      return SizedBox(
        height: 120,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 5,
          itemBuilder: (context, index) {
            return Container(
              width: 100,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: radius(12),
              ),
            );
          },
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Text(
              'Erreur: $_error',
              style: secondaryTextStyle(color: Colors.red),
            ),
            8.height,
            TextButton(
              onPressed: _fetchServices,
              child: Text('Réessayer', style: primaryTextStyle(color: primaryColor)),
            ),
          ],
        ),
      );
    }

    if (_services.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Aucun service disponible',
          style: secondaryTextStyle(),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _services.length,
        itemBuilder: (context, index) {
          final service = _services[index];
          return _ServiceCard(
            service: service,
            onTap: () {
              MisonBookingFormScreen(service: service).launch(context);
            },
          );
        },
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final MisonService service;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.service,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: radius(16),
              ),
              child: ClipRRect(
                borderRadius: radius(16),
                child: service.imageUrl != null && service.imageUrl!.isNotEmpty
                    ? CachedImageWidget(
                        url: service.imageUrl!,
                        fit: BoxFit.cover,
                        width: 70,
                        height: 70,
                      )
                    : Icon(
                        Icons.home_repair_service,
                        size: 36,
                        color: primaryColor,
                      ),
              ),
            ),
            8.height,
            Text(
              service.name ?? '',
              style: primaryTextStyle(size: 12),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
