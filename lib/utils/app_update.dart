import 'dart:io' show Platform;

import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mises à jour de l'app, réglées dans l'admin Django (Versions de l'app) :
/// - build de l'app < build minimal → écran bloquant « Mise à jour obligatoire » ;
/// - build de l'app < dernier build → fenêtre « Nouvelle version disponible »
///   avec « Plus tard » (reproposée seulement à la version suivante).
///
/// Android : mise à jour intégrée Google Play (téléchargée et installée sans
/// quitter l'app). iPhone : la fiche App Store s'ouvre par-dessus l'app (Apple
/// ne permet pas d'installer une mise à jour depuis l'app).

const _kDismissedBuildKey = 'app_update_dismissed_build';
const _appStoreChannel = MethodChannel('mison/app_store');
const _kAppleAppId = '6777843890';
const _kPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.mison.serviceuser';

const _gold = Color(0xFFC49716);
const _dark = Color(0xFF3A3A3A);

bool _checkedThisSession = false;
bool _forceScreenShown = false;

class _VersionInfo {
  final String latestVersion;
  final int latestBuild;
  final int minBuild;
  final String message;

  _VersionInfo(Map json)
      : latestVersion = json['latest_version']?.toString() ?? '',
        latestBuild = int.tryParse('${json['latest_build']}') ?? 0,
        minBuild = int.tryParse('${json['min_build']}') ?? 0,
        message = json['message']?.toString() ?? '';
}

/// À appeler à l'ouverture des tableaux de bord : une seule vérification par
/// lancement de l'app. Ne lève jamais : sans réseau, rien ne s'affiche.
Future<void> checkAppUpdate(BuildContext context) async {
  if (_checkedThisSession || !(Platform.isAndroid || Platform.isIOS)) return;
  _checkedThisSession = true;
  try {
    final build = int.tryParse((await getPackageInfo()).versionCode ?? '') ?? 0;
    if (build <= 0) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    final res = await buildHttpResponse('app/version?platform=$platform', method: HttpMethodType.GET);
    if (res.statusCode != 200) return;
    final info = _VersionInfo(await handleResponse(res));
    if (!context.mounted) return;

    if (build < info.minBuild) {
      _showForceUpdate(context, info);
    } else if (build < info.latestBuild && getIntAsync(_kDismissedBuildKey) < info.latestBuild) {
      _showOptionalUpdate(context, info);
    }
  } catch (e) {
    log('checkAppUpdate: $e');
  }
}

/// Lance la mise à jour. [immediate] : Android installe tout de suite (plein
/// écran Google Play) ; sinon téléchargement en arrière-plan puis redémarrage.
Future<void> _startUpdate({required bool immediate}) async {
  if (Platform.isAndroid) {
    try {
      final update = await InAppUpdate.checkForUpdate();
      if (update.updateAvailability == UpdateAvailability.updateAvailable) {
        if (immediate && update.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
          return;
        }
        if (!immediate && update.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) await InAppUpdate.completeFlexibleUpdate();
          return;
        }
      }
    } catch (e) {
      // App installée hors Play Store (APK) ou Play indisponible : fiche du store.
      log('in-app update: $e');
    }
    await launchUrl(Uri.parse(_kPlayStoreUrl), mode: LaunchMode.externalApplication);
    return;
  }
  try {
    await _appStoreChannel.invokeMethod('open', _kAppleAppId);
  } catch (e) {
    log('app store sheet: $e');
    await launchUrl(Uri.parse(IOS_LINK_FOR_USER), mode: LaunchMode.externalApplication);
  }
}

void _showOptionalUpdate(BuildContext context, _VersionInfo info) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      content: _UpdateContent(
        title: 'Nouvelle version disponible',
        text: info.message.isNotEmpty
            ? info.message
            : 'Une nouvelle version de MISON${info.latestVersion.isNotEmpty ? ' (${info.latestVersion})' : ''} '
                'est disponible, avec des améliorations et des corrections.',
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () async {
            // Plus proposée avant la version suivante.
            await setValue(_kDismissedBuildKey, info.latestBuild);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('Plus tard', style: TextStyle(color: _dark)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            Navigator.pop(dialogContext);
            _startUpdate(immediate: false);
          },
          child: const Text('Mettre à jour'),
        ),
      ],
    ),
  );
}

void _showForceUpdate(BuildContext context, _VersionInfo info) {
  if (_forceScreenShown) return;
  _forceScreenShown = true;
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ForceUpdateScreen(info: info),
  ));
}

/// Écran bloquant : impossible de revenir en arrière tant que l'app n'est pas
/// mise à jour (Android la redémarre une fois installée).
class _ForceUpdateScreen extends StatelessWidget {
  final _VersionInfo info;

  const _ForceUpdateScreen({required this.info});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(),
                _UpdateContent(
                  title: 'Mise à jour obligatoire',
                  text: info.message.isNotEmpty
                      ? info.message
                      : 'Cette version de MISON n\'est plus prise en charge. '
                          'Installez la dernière version pour continuer à utiliser l\'application.',
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _startUpdate(immediate: true),
                    child: const Text('Mettre à jour', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                32.height,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateContent extends StatelessWidget {
  final String title;
  final String text;

  const _UpdateContent({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.system_update_rounded, color: _gold, size: 40),
        16.height,
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _dark)),
        12.height,
        Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Color(0xFF6B6B6B))),
      ],
    );
  }
}
