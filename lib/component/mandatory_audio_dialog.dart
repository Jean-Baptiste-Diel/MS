import 'package:booking_system_flutter/utils/remote_media.dart';
import 'package:flutter/material.dart';
import 'package:booking_system_flutter/component/mison_audio_sheet.dart';
import 'package:booking_system_flutter/main.dart' show appStore;
import 'package:booking_system_flutter/utils/constant.dart' show USER_TYPE_PROVIDER;
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

/// Client (connecté ou simple visiteur) : message de bienvenue de MISON, à la
/// première ouverture de l'accueil (une seule fois sur ce téléphone).
Future<void> showClientWelcomeAudio() async {
  if (appStore.isLoggedIn && appStore.userType == USER_TYPE_PROVIDER) return;
  const key = 'WELCOME_AUDIO_PLAYED';
  if (getBoolAsync(key)) return;
  // Première ouverture : la note vient du serveur.
  await RemoteMedia.ready();
  // Pas (encore) de note : proposée à la prochaine ouverture.
  if (!RemoteMedia.hasAudio(kAudioWelcomeClient)) return;
  final context = navigatorKey.currentContext;
  if (context == null) return;
  await setValue(key, true);
  await showMisonAudioSheet(
    context,
    asset: kAudioWelcomeClient,
    icon: Icons.waving_hand_rounded,
    caption: 'Bienvenue',
    title: 'Bienvenue sur MISON',
    subtitle: 'Écoutez ce petit message pour bien commencer.',
    continueLabel: 'Commencer',
  );
}
