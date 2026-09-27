import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

Future<Position> getUserLocationPosition() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  LocationPermission permission = await Geolocator.checkPermission();
  if (!serviceEnabled) {
    //
  }

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.openAppSettings();
      throw '${language.lblLocationPermissionDenied}';
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw '${language.lblLocationPermissionDeniedPermanently}';
  }

  return await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high)).then((value) {
    return value;
  }).catchError((e) async {
    return await Geolocator.getLastKnownPosition().then((value) async {
      if (value != null) {
        return value;
      } else {
        throw '${language.lblEnableLocation}';
      }
    }).catchError((e) {
      TopToast.show(message: e.toString(), type: TopToastType.error);
      throw e;
    });
  });
}

Future<String> getUserLocation() async {
  Position position = await getUserLocationPosition().catchError((e) {
    throw e.toString();
  });

  return await buildFullAddressFromLatLong(position.latitude, position.longitude);
}

Future<String> buildFullAddressFromLatLong(double latitude, double longitude) async {
  List<Placemark> placeMark = await placemarkFromCoordinates(latitude, longitude).catchError((e) async {
    log(e);
    throw errorSomethingWentWrong;
  });

  setValue(LATITUDE, latitude);
  setValue(LONGITUDE, longitude);

  Placemark place = placeMark[0];

  log(place.toJson());

  // Seulement les morceaux renseignés, sans doublon : sans nom de rue (fréquent
  // au Sénégal), l'ancienne concaténation donnait « , Pikine, Pikine, Senegal ».
  final address = joinAddressParts([
    if (!place.name.isEmptyOrNull && !place.street.isEmptyOrNull && place.name != place.street) place.name,
    place.street,
    place.subLocality,
    place.locality,
    place.administrativeArea,
    place.postalCode,
    place.country,
  ]);

  setValue(CURRENT_ADDRESS, address);
  setValue(CITY_NAME, place.locality);

  return address;
}


/// Assemble une adresse : ignore les morceaux vides et les noms répétés
/// (ex. ville et région toutes deux « Pikine »), séparés par « , ».
String joinAddressParts(Iterable<String?> parts) {
  final kept = <String>[];
  for (final part in parts) {
    final value = (part ?? '').trim();
    if (value.isEmpty) continue;
    if (kept.any((k) => k.toLowerCase() == value.toLowerCase())) continue;
    kept.add(value);
  }
  return kept.join(', ');
}
