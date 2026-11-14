import 'dart:io';

import 'package:nb_utils/nb_utils.dart';

/// Téléphone et version de l'app, envoyés au serveur avec chaque requête :
/// l'équipe voit dans le back-office qui est sur iPhone ou Android, et qui
/// n'a pas encore mis à jour MISON.
///
/// - X-App-Platform : « ios » ou « android »
/// - X-App-Os       : « iOS 18.1 », « Android 14 »
/// - X-App-Version  : « 1.0.3 (34) »
final Map<String, String> appDeviceHeaders = {};

/// Lu une fois au démarrage (avant runApp). Ne lève jamais.
Future<void> loadAppDeviceHeaders() async {
  if (!Platform.isIOS && !Platform.isAndroid) return;
  appDeviceHeaders['X-App-Platform'] = Platform.isIOS ? 'ios' : 'android';
  try {
    final info = await getPackageInfo();
    final name = info.versionName ?? '';
    final code = info.versionCode ?? '';
    if (name.isNotEmpty) appDeviceHeaders['X-App-Version'] = code.isNotEmpty ? '$name ($code)' : name;
    appDeviceHeaders['X-App-Os'] = Platform.isIOS
        ? 'iOS ${_iosVersion(Platform.operatingSystemVersion)}'
        : _androidVersion(info.androidSDKVersion);
  } catch (_) {
    // Infos indisponibles : le système suffit.
  }
}

/// « Version 18.1 (Build 22B83) » → « 18.1 ».
String _iosVersion(String raw) => RegExp(r'\d+(\.\d+)*').firstMatch(raw)?.group(0) ?? raw;

/// Niveau d'API Android → version lisible (« Android 14 »).
String _androidVersion(int? sdk) {
  if (sdk == null) return 'Android';
  const names = {
    21: '5.0', 22: '5.1', 23: '6', 24: '7.0', 25: '7.1', 26: '8.0', 27: '8.1',
    28: '9', 29: '10', 30: '11', 31: '12', 32: '12L', 33: '13', 34: '14',
    35: '15', 36: '16', 37: '17',
  };
  final name = names[sdk];
  return name != null ? 'Android $name' : 'Android (API $sdk)';
}
