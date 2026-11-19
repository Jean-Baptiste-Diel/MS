import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark, kMisonFieldBg;
import 'package:booking_system_flutter/screens/support_chat/voice_note_player.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Messages audio de MISON (fichiers dans assets/sounds/).
const kAudioBeforePayment = 'sounds/avant_paiement.m4a';
const kAudioAfterAccept = 'sounds/apres_acceptation.m4a';
const kAudioWorkerPaymentReminder = 'sounds/rappel_paiement_ouvrier.m4a';
const kAudioWelcomeClient = 'sounds/bienvenue_client.m4a';

/// Notes vocales déjà écoutées jusqu'au bout (clé : [listenKey]) : une page
/// rouverte pour la même étape ne réimpose pas l'écoute.
final Set<String> _listenedKeys = {};

/// Page d'étape au style de la page de paiement (fiche Google Play) :
/// logo, petit libellé en couleur, grand titre, note vocale éventuelle,
/// bouton, mention, avertissement.
///
/// [asset] : note vocale de l'étape (démarre seule). Avec [mustListen], le
/// bouton reste grisé et la page ne se ferme pas tant qu'elle n'a pas été
/// écoutée en entier. Renvoie true si l'utilisateur a choisi de continuer.
Future<bool> showMisonAudioSheet(
  BuildContext context, {
  String? asset,
  required String title,
  required String subtitle,
  required String continueLabel,
  String? caption,
  String? footnote,
  String? warning,
  IconData icon = Icons.headphones_rounded,
  bool mustListen = false,
  String? laterLabel,
  String? listenKey,
  bool locked = false,
}) async {
  final key = listenKey ?? asset;
  final mustWait = mustListen && asset != null && !(key != null && _listenedKeys.contains(key));
  // [locked] : ne se ferme que par le bouton principal (ni croix, ni retour).
  final noClose = locked || mustWait;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    isDismissible: !noClose,
    enableDrag: !noClose,
    backgroundColor: Colors.transparent,
    builder: (_) => _MisonAudioSheet(
      asset: asset,
      title: title,
      subtitle: subtitle,
      continueLabel: continueLabel,
      caption: caption,
      footnote: footnote,
      warning: warning,
      icon: icon,
      mustListen: mustWait,
      laterLabel: laterLabel,
      listenKey: key,
      locked: locked,
    ),
  );
  return ok == true;
}

class _MisonAudioSheet extends StatefulWidget {
  final String? asset;
  final String title;
  final String subtitle;
  final String continueLabel;
  final String? caption;
  final String? footnote;
  final String? warning;
  final IconData icon;
  final bool mustListen;
  final String? laterLabel;
  final String? listenKey;
  final bool locked;

  const _MisonAudioSheet({
    this.locked = false,
    this.asset,
    required this.title,
    required this.subtitle,
    required this.continueLabel,
    this.caption,
    this.footnote,
    this.warning,
    required this.icon,
    required this.mustListen,
    this.laterLabel,
    this.listenKey,
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
      canPop: _canContinue && !widget.locked,
      child: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 14, 16, MediaQuery.of(context).padding.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête : logo MISON, fermer (seulement si la page peut se fermer)
              Row(
                children: [
                  Image.asset('assets/logo/logo_transparent.png', height: 30,
                      errorBuilder: (_, __, ___) => Text('MISON', style: boldTextStyle(size: 20, color: kMisonDark))),
                  const Spacer(),
                  if (_canContinue && !widget.locked)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 26),
                      color: kMisonDark,
                      onPressed: () => Navigator.pop(context, false),
                      tooltip: 'Fermer',
                    )
                  else
                    const SizedBox(height: 48),
                ],
              ),
              14.height,
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((widget.caption ?? '').isNotEmpty) ...[
                      Text(widget.caption!.toUpperCase(),
                          style: boldTextStyle(size: 15, color: kMisonGold, letterSpacing: 0.3)),
                      6.height,
                    ],
                    Text(widget.title, style: primaryTextStyle(size: 30, color: kMisonDark, weight: FontWeight.w600)),
                    6.height,
                    Text(widget.subtitle, style: secondaryTextStyle(size: 14, color: kMisonDark.withValues(alpha: 0.7))),
                    16.height,

                    // Note vocale (démarre seule)
                    if (widget.asset != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: kMisonFieldBg,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: VoiceNotePlayer(
                          asset: widget.asset,
                          color: kMisonGold,
                          autoPlay: true,
                          expand: true,
                          onCompleted: () {
                            if (widget.listenKey != null) _listenedKeys.add(widget.listenKey!);
                            if (mounted) setState(() => _listened = true);
                          },
                        ),
                      ),
                      if (widget.mustListen && !_listened) ...[
                        8.height,
                        Text('Écoutez le message jusqu’au bout pour continuer.',
                            style: secondaryTextStyle(size: 13)),
                      ],
                      20.height,
                    ] else
                      4.height,

                    // Bouton principal
                    SizedBox(
                      width: double.infinity,
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
                          style: boldTextStyle(color: _canContinue ? Colors.white : Colors.grey.shade600, size: 16),
                        ),
                      ),
                    ),
                    // Deuxième bouton, aussi sur une page verrouillée (ex. « Voir la carte »).
                    if (widget.laterLabel != null && _canContinue) ...[
                      10.height,
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kMisonDark,
                            side: BorderSide(color: Colors.grey.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(widget.laterLabel!, style: boldTextStyle(color: kMisonDark, size: 16)),
                        ),
                      ),
                    ],
                    if ((widget.footnote ?? '').isNotEmpty) ...[
                      8.height,
                      Text(widget.footnote!,
                          style: secondaryTextStyle(size: 13, color: kMisonDark.withValues(alpha: 0.75))),
                    ],
                    if ((widget.warning ?? '').isNotEmpty) ...[
                      22.height,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(widget.icon, color: kMisonGold, size: 24),
                          14.width,
                          Expanded(
                            child: Text(widget.warning!,
                                style: primaryTextStyle(size: 15, color: kMisonDark.withValues(alpha: 0.85))),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
