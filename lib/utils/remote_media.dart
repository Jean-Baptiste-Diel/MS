import 'dart:convert';
import 'dart:io';

import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';
import 'package:path_provider/path_provider.dart';

/// Sons et images de l'app remplaçables depuis le back-office (« Sons et
/// images de l'app »), sans nouvelle version.
///
/// Au démarrage, l'app demande au serveur la liste des fichiers remplacés,
/// télécharge ceux qui ont changé et les garde sur le téléphone : ils servent
/// ensuite sans réseau. Un élément absent de la liste (jamais remplacé, ou
/// remis à l'origine) utilise le fichier de l'app.
class RemoteMedia {
  static const _prefsKey = 'APP_MEDIA_FILES';

  /// Fichier de l'app → élément du back-office.
  static const assetKeys = <String, String>{
    'sounds/bienvenue_client.m4a': 'audio_bienvenue_client',
    'sounds/apres_acceptation.m4a': 'audio_apres_acceptation',
    'sounds/avant_paiement.m4a': 'audio_avant_paiement',
    'sounds/rappel_paiement_ouvrier.m4a': 'audio_rappel_paiement_ouvrier',
    'assets/images/mison_welcome_bg.jpg': 'image_bienvenue_fond',
    'assets/images/home_banner_mison.jpg': 'image_accueil_defaut',
  };

  /// Élément → chemin du fichier téléchargé.
  static Map<String, String> _files = {};
  static bool _loaded = false;
  static Future<void>? _syncing;

  static void _load() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = getStringAsync(_prefsKey);
      if (raw.isNotEmpty) _files = Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _files = {};
    }
  }

  /// Fichier téléchargé qui remplace [asset], s'il existe encore.
  static File? fileFor(String asset) {
    _load();
    final key = assetKeys[asset];
    final path = key == null ? null : _files[key];
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  /// Met à jour les fichiers depuis le serveur. Ne lève jamais ; un seul
  /// appel à la fois.
  static Future<void> sync() => _syncing ??= _sync().whenComplete(() => _syncing = null);

  static Future<void> _sync() async {
    _load();
    try {
      final res = await buildHttpResponse('app/media', method: HttpMethodType.GET);
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      final items = body is Map && body['data'] is List ? body['data'] as List : const [];
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/app_media');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final next = <String, String>{};
      for (final item in items.whereType<Map>()) {
        final key = item['key']?.toString() ?? '';
        final url = item['url']?.toString() ?? '';
        if (!assetKeys.containsValue(key) || url.isEmpty) continue;
        final ext = _extension(url);
        final path = '${dir.path}/$key-${item['version']}$ext';
        if (!File(path).existsSync()) {
          final ok = await _download(url, path);
          if (!ok) {
            // Échec : on garde l'ancien fichier remplacé s'il y en a un.
            if (_files[key] != null) next[key] = _files[key]!;
            continue;
          }
        }
        next[key] = path;
      }

      // Fichiers devenus inutiles (remplacés à nouveau ou remis à l'origine).
      final keep = next.values.toSet();
      for (final entity in dir.listSync()) {
        if (entity is File && !keep.contains(entity.path)) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
      _files = next;
      await setValue(_prefsKey, jsonEncode(next));
    } catch (e) {
      log('[RemoteMedia] $e');
    }
  }

  static Future<bool> _download(String url, String path) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return false;
      final tmp = File('$path.part');
      await tmp.writeAsBytes(res.bodyBytes, flush: true);
      await tmp.rename(path);
      return true;
    } catch (e) {
      log('[RemoteMedia] téléchargement : $e');
      return false;
    }
  }

  static String _extension(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot).toLowerCase() : '';
    return ext.length <= 5 ? ext : '';
  }
}

/// Image de l'app, remplacée par celle du back-office quand il y en a une.
class MisonAssetImage extends StatelessWidget {
  final String asset;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  const MisonAssetImage(this.asset, {super.key, this.fit, this.width, this.height, this.errorBuilder});

  @override
  Widget build(BuildContext context) {
    final file = RemoteMedia.fileFor(asset);
    if (file != null) {
      return Image.file(
        file,
        fit: fit,
        width: width,
        height: height,
        // Fichier abîmé : l'image de l'app.
        errorBuilder: (_, __, ___) => Image.asset(asset, fit: fit, width: width, height: height, errorBuilder: errorBuilder),
      );
    }
    return Image.asset(asset, fit: fit, width: width, height: height, errorBuilder: errorBuilder);
  }
}
