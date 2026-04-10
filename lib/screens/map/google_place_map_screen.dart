import 'package:booking_system_flutter/component/nominatim_address_field.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Écran de recherche d'adresse avec autocomplétion Nominatim (sans clé API)
/// Retourne {name, lat, lon} ou {use_map: true} pour ouvrir la carte OSM
class GooglePlaceMapScreen extends StatefulWidget {
  const GooglePlaceMapScreen({Key? key}) : super(key: key);

  @override
  _GooglePlaceMapScreenState createState() => _GooglePlaceMapScreenState();
}

class _GooglePlaceMapScreenState extends State<GooglePlaceMapScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choisir une adresse'),
        backgroundColor: context.primaryColor,
        leading: BackButton(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: NominatimAddressField(
                controller: _controller,
                hintText: 'Rechercher une adresse...',
                countryCodes: const ['sn', 'ml', 'ci', 'bf', 'gn', 'ne', 'tg', 'bj', 'mr', 'gm'],
                decoration: InputDecoration(
                  hintText: 'Rechercher une adresse...',
                  hintStyle: secondaryTextStyle(),
                  prefixIcon: Icon(Icons.search, color: primaryColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onSelected: (suggestion) {
                  Navigator.of(context).pop({
                    'name': suggestion.shortName,
                    'lat': suggestion.lat,
                    'lon': suggestion.lon,
                  });
                },
              ),
            ),
            8.height,
            Text('Ou sélectionnez directement sur la carte',
                style: secondaryTextStyle(size: 12)),
            12.height,
            AppButton(
              child: Text('Ouvrir la carte',
                  style: boldTextStyle(color: Colors.white)),
              width: double.infinity,
              color: context.primaryColor,
              onTap: () => finish(context, {'use_map': true}),
            ),
          ],
        ),
      ),
    );
  }
}
