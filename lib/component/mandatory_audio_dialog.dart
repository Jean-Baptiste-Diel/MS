import 'package:flutter/material.dart';
import 'package:booking_system_flutter/component/mison_audio_sheet.dart';
import 'package:nb_utils/nb_utils.dart';

export 'package:booking_system_flutter/component/mison_audio_sheet.dart' show kAudioAfterAccept;

bool _mandatoryAudioOpen = false;

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
      title: 'Commande acceptée',
      subtitle: 'Écoutez ce message en entier avant de continuer.',
      continueLabel: "J'ai écouté",
      mustListen: true,
    );
  } finally {
    _mandatoryAudioOpen = false;
  }
}
