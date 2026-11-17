import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark, kMisonFieldBg;
import 'package:booking_system_flutter/screens/support_chat/voice_note_player.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Messages audio de MISON (fichiers dans assets/sounds/).
const kAudioBeforePayment = 'sounds/avant_paiement.m4a';
const kAudioAfterAccept = 'sounds/apres_acceptation.m4a';
const kAudioWorkerPaymentReminder = 'sounds/rappel_paiement_ouvrier.m4a';

/// Panneau « message audio », même présentation que « Annuler la commande » :
/// il monte du bas, l'audio démarre tout seul.
/// [mustListen] : impossible de fermer ou de continuer avant la fin de l'audio.
/// Renvoie true si l'utilisateur a choisi de continuer.
Future<bool> showMisonAudioSheet(
  BuildContext context, {
  required String asset,
  required String title,
  required String subtitle,
  required String continueLabel,
  IconData icon = Icons.headphones_rounded,
  bool mustListen = false,
  String? laterLabel,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    isDismissible: !mustListen,
    enableDrag: !mustListen,
    backgroundColor: Colors.transparent,
    builder: (_) => _MisonAudioSheet(
      asset: asset,
      title: title,
      subtitle: subtitle,
      continueLabel: continueLabel,
      icon: icon,
      mustListen: mustListen,
      laterLabel: laterLabel,
    ),
  );
  return ok == true;
}

class _MisonAudioSheet extends StatefulWidget {
  final String asset;
  final String title;
  final String subtitle;
  final String continueLabel;
  final IconData icon;
  final bool mustListen;
  final String? laterLabel;

  const _MisonAudioSheet({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.continueLabel,
    required this.icon,
    required this.mustListen,
    this.laterLabel,
  });

  @override
  State<_MisonAudioSheet> createState() => _MisonAudioSheetState();
}

class _MisonAudioSheetState extends State<_MisonAudioSheet> {
  bool _listened = false;

  bool get _canContinue => !widget.mustListen || _listened;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canContinue,
      child: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            20.height,
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: kMisonGold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: kMisonGold, size: 32),
              ),
            ),
            16.height,
            Text(widget.title, textAlign: TextAlign.center, style: boldTextStyle(size: 20, color: kMisonDark)),
            8.height,
            Text(widget.subtitle, textAlign: TextAlign.center, style: secondaryTextStyle(size: 14)),
            18.height,
            // Lecteur : gros bouton lecture / pause doré, barre de progression.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kMisonFieldBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: VoiceNotePlayer(
                asset: widget.asset,
                color: kMisonGold,
                autoPlay: true,
                expand: true,
                onCompleted: () {
                  if (mounted) setState(() => _listened = true);
                },
              ),
            ),
            if (widget.mustListen && !_listened) ...[
              8.height,
              Text('Écoutez le message jusqu\'au bout pour continuer.',
                  textAlign: TextAlign.center, style: secondaryTextStyle(size: 12)),
            ],
            20.height,
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _canContinue ? () => Navigator.pop(context, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMisonGold,
                  disabledBackgroundColor: Colors.grey.shade300,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  widget.continueLabel,
                  style: boldTextStyle(color: _canContinue ? Colors.white : Colors.grey.shade600, size: 15),
                ),
              ),
            ),
            if (!widget.mustListen && widget.laterLabel != null) ...[
              10.height,
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(widget.laterLabel!, style: boldTextStyle(color: kMisonDark, size: 15)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
