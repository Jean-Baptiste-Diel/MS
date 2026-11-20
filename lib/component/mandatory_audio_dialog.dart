import 'package:booking_system_flutter/utils/remote_media.dart';
import 'package:flutter/material.dart';
import 'package:booking_system_flutter/component/mison_audio_sheet.dart';
import 'package:booking_system_flutter/main.dart' show appStore;
import 'package:booking_system_flutter/utils/constant.dart' show USER_TYPE_PROVIDER;
import 'package:booking_system_flutter/network/rest_apis.dart' show getMisonOrders;
import 'package:intl/intl.dart' show DateFormat;
import 'package:nb_utils/nb_utils.dart';

export 'package:booking_system_flutter/component/mison_audio_sheet.dart' show kAudioAfterAccept;

bool _mandatoryAudioOpen = false;

/// La note obligatoire d'après l'acceptation est à l'écran.
bool get isAfterAcceptAudioOpen => _mandatoryAudioOpen;

/// Ouvrier, juste après avoir accepté une commande : message audio à écouter
/// en entier (le panneau ne se ferme pas avant la fin).
Future<void> showAfterAcceptAudio() async {
  final context = navigatorKey.currentContext;
  if (context == null || _mandatoryAudioOpen) return;
  // Pas de note sur le serveur : pas de page « Message de MISON » (sinon un
  // « J'ai écouté » sans rien à écouter).
  if (!RemoteMedia.hasAudio(kAudioAfterAccept)) return;
  _mandatoryAudioOpen = true;
  try {
    await showMisonAudioSheet(
      context,
      asset: kAudioAfterAccept,
      icon: Icons.check_circle_rounded,
      caption: 'Commande acceptée',
      title: 'Message de MISON',
      subtitle: 'Écoutez ce message en entier avant de continuer.',
      continueLabel: "J'ai écouté",
      mustListen: true,
      // À écouter à chaque commande acceptée.
      listenKey: 'accept-${DateTime.now().microsecondsSinceEpoch}',
    );
  } finally {
    _mandatoryAudioOpen = false;
  }
}

/// Client, juste avant de valider une commande : note de MISON.
/// - tant qu'il n'a aucune commande terminée : à chaque commande ;
/// - ensuite : 2 fois par mois au plus.
/// La note doit être écoutée jusqu'au bout (jamais bloquante si elle ne peut
/// pas être lue). Renvoie false si le client ferme la page sans valider.
Future<bool> showClientOrderAudio(BuildContext context) async {
  if (appStore.userType == USER_TYPE_PROVIDER) return true;
  await RemoteMedia.ready(timeout: const Duration(seconds: 5));
  if (!RemoteMedia.hasAudio(kAudioWelcomeClient)) return true; // pas de note sur le serveur
  final hasCompleted = await _clientHasCompletedOrder();
  final monthKey = 'ORDER_AUDIO_${DateFormat('yyyy-MM').format(DateTime.now())}_${appStore.userId}';
  if (hasCompleted && getIntAsync(monthKey) >= 2) return true;
  if (!context.mounted) return true;
  final go = await showMisonAudioSheet(
    context,
    asset: kAudioWelcomeClient,
    icon: Icons.headphones_rounded,
    caption: 'Avant de commander',
    title: 'Message de MISON',
    subtitle: 'Écoutez ce message jusqu\u2019au bout avant de valider votre commande.',
    continueLabel: 'Valider ma commande',
    mustListen: true,
    // À écouter à chaque fois (pas de « déjà écoutée »).
    listenKey: 'order-audio-${DateTime.now().microsecondsSinceEpoch}',
  );
  if (go && hasCompleted) await setValue(monthKey, getIntAsync(monthKey) + 1);
  return go;
}

/// Le client a déjà une commande terminée (gardé une fois vu, pour ne pas
/// dépendre du réseau ensuite).
Future<bool> _clientHasCompletedOrder() async {
  final key = 'CLIENT_HAS_COMPLETED_ORDER_${appStore.userId}';
  if (getBoolAsync(key)) return true;
  try {
    final orders = (await getMisonOrders().timeout(const Duration(seconds: 6))).data ?? [];
    final done = orders.any((o) => o.isCompleted);
    if (done) await setValue(key, true);
    return done;
  } catch (_) {
    return false; // pas de réseau : considéré sans commande terminée (note jouée)
  }
}

bool _openingAudioShown = false;

/// À l'ouverture de l'app : note de MISON du back-office (« client, à
/// l'ouverture » ou « ouvrier, à l'ouverture »), à chaque ouverture tant
/// qu'une note y est mise. Sans note : rien. Elle peut être fermée à tout moment.
Future<void> showOpeningAudio() async {
  if (_openingAudioShown) return; // une fois par ouverture de l'app
  _openingAudioShown = true;
  final isArtisan = appStore.isLoggedIn && appStore.userType == USER_TYPE_PROVIDER;
  final asset = isArtisan ? kAudioOpenArtisan : kAudioOpenClient;
  await RemoteMedia.ready(timeout: const Duration(seconds: 6));
  if (!RemoteMedia.hasAudio(asset)) return;
  // Note obligatoire d'après l'acceptation à l'écran : pas par-dessus.
  if (_mandatoryAudioOpen) return;
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  await showMisonAudioSheet(
    context,
    asset: asset,
    icon: Icons.campaign_rounded,
    caption: 'Message de MISON',
    title: isArtisan ? 'Bonjour !' : 'Bienvenue sur MISON',
    subtitle: 'Un petit message de l’équipe MISON.',
    continueLabel: 'Continuer',
  );
}
