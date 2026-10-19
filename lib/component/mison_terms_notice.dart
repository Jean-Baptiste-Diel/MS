import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Règle affichée avant l'inscription et la connexion (App Store 1.2).
const kZeroToleranceRule = "Aucun contenu choquant ni comportement abusif n'est toléré : "
    'les contenus signalés sont vérifiés sous 24 h et les comptes concernés sont exclus.';

/// « En continuant, vous acceptez les CGU… » + règle de tolérance zéro, avec
/// les liens vers les conditions et la politique de confidentialité.
class MisonTermsNotice extends StatelessWidget {
  /// Début de la phrase (« En vous connectant », « En continuant »…).
  final String lead;
  final Color linkColor;

  const MisonTermsNotice({Key? key, this.lead = 'En continuant', this.linkColor = const Color(0xFFC99700)})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(color: appTextSecondaryColor, fontSize: 13, height: 1.4);
    final link = TextStyle(color: linkColor, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: '$lead, vous acceptez les '),
          TextSpan(
            text: "Conditions générales d'utilisation",
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => checkIfLink(context, appConfigurationStore.termConditions,
                  title: language.termsCondition),
          ),
          const TextSpan(text: ' et la '),
          TextSpan(
            text: 'Politique de confidentialité',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => checkIfLink(context, appConfigurationStore.privacyPolicy,
                  title: language.privacyPolicy),
          ),
          const TextSpan(text: ' de Mison. $kZeroToleranceRule'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
