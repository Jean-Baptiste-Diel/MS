import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';

/// Simple screen exposing Google Place Autocomplete and returning {name, lat, lon}
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
        title: Text('Choisir une adresse'),
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
              ),
              child: GooglePlaceAutoCompleteTextField(
                textEditingController: _controller,
                googleAPIKey: GOOGLE_PLACES_API_KEY,
                inputDecoration: InputDecoration(
                  hintText: 'Rechercher une adresse...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                debounceTime: 300,
                isLatLngRequired: true,
                countries: const ["sn", "ml", "ci", "bf", "gn", "ne", "tg", "bj", "mr", "gm"],
                getPlaceDetailWithLatLng: (prediction) {
                  final desc = prediction.description ?? '';
                  final lat = double.tryParse(prediction.lat ?? '') ;
                  final lng = double.tryParse(prediction.lng ?? '');

                  // Return result
                  final result = {
                    'name': desc,
                    'lat': lat,
                    'lon': lng,
                  };
                  Navigator.of(context).pop(result);
                },
                itemClick: (p) {
                  HapticFeedback.selectionClick();
                },
                seperatedBuilder: Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
                itemBuilder: (context, index, prediction) {
                  return ListTile(
                    leading: Icon(Icons.place, color: context.primaryColor),
                    title: Text(prediction.description ?? ''),
                  );
                },
              ),
            ),
            8.height,
            Text('Ou sélectionnez directement sur la carte', style: secondaryTextStyle(size: 12)),
            12.height,
            AppButton(
              child: Text('Ouvrir la carte', style: boldTextStyle(color: Colors.white)),
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
