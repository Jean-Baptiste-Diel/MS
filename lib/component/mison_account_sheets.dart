import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/pin_utils.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

const Color _dangerRed = Color(0xFFE53935);

/// Panneau commun (style Mison) : poignée, icône dans un rond, titre, texte.
Widget _sheetFrame(BuildContext context, {required List<Widget> children}) {
  return Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 20),
      child: SingleChildScrollView(
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
            ...children,
          ],
        ),
      ),
    ),
  );
}

Widget _sheetIcon(IconData icon, Color color) => Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 32),
      ),
    );

Widget _primaryButton({
  required String label,
  required Color color,
  required VoidCallback? onPressed,
  bool loading = false,
}) {
  return SizedBox(
    height: 52,
    child: ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: 0.6),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            )
          : Text(label, style: boldTextStyle(color: Colors.white, size: 15)),
    ),
  );
}

Widget _secondaryButton({required String label, required VoidCallback? onPressed}) {
  return SizedBox(
    height: 52,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: kMisonDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: boldTextStyle(color: kMisonDark, size: 15)),
    ),
  );
}

// ── Confirmation générique ───────────────────────────────────────────────────

/// Confirmation d'une action (accepter, démarrer, se désister…), style Mison.
/// [danger] : bouton et icône rouges. Retourne true si l'utilisateur confirme.
Future<bool> showMisonConfirmSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  IconData icon = Icons.help_outline_rounded,
  String confirmLabel = 'Confirmer',
  String cancelLabel = 'Annuler',
  bool danger = false,
}) async {
  final color = danger ? _dangerRed : kMisonGold;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _sheetFrame(sheetContext, children: [
      _sheetIcon(icon, color),
      16.height,
      Text(title, textAlign: TextAlign.center, style: boldTextStyle(size: 20, color: kMisonDark)),
      8.height,
      Text(subtitle, textAlign: TextAlign.center, style: secondaryTextStyle(size: 14)),
      24.height,
      _primaryButton(
        label: confirmLabel,
        color: color,
        onPressed: () => Navigator.pop(sheetContext, true),
      ),
      10.height,
      _secondaryButton(
        label: cancelLabel,
        onPressed: () => Navigator.pop(sheetContext, false),
      ),
    ]),
  );
  return confirmed ?? false;
}

// ── Déconnexion ──────────────────────────────────────────────────────────────

/// Confirmation de déconnexion. Retourne true si l'utilisateur confirme.
Future<bool> showMisonLogoutSheet(BuildContext context) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _sheetFrame(sheetContext, children: [
      _sheetIcon(Icons.logout_rounded, kMisonGold),
      16.height,
      Text('Se déconnecter ?',
          textAlign: TextAlign.center, style: boldTextStyle(size: 20, color: kMisonDark)),
      8.height,
      Text(
        'Vous devrez saisir à nouveau votre numéro et votre code PIN pour vous reconnecter.',
        textAlign: TextAlign.center,
        style: secondaryTextStyle(size: 14),
      ),
      24.height,
      _primaryButton(
        label: 'Oui, me déconnecter',
        color: kMisonGold,
        onPressed: () => Navigator.pop(sheetContext, true),
      ),
      10.height,
      _secondaryButton(
        label: 'Non, rester connecté',
        onPressed: () => Navigator.pop(sheetContext, false),
      ),
    ]),
  );
  return confirmed ?? false;
}

// ── Suppression du compte ────────────────────────────────────────────────────

/// Suppression du compte confirmée par le code PIN. Appelle le serveur ;
/// retourne le message de succès, ou null si annulé.
Future<String?> showMisonDeleteAccountSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DeleteAccountSheet(),
  );
}

class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet();

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final TextEditingController _pinCont = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _pinCont.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final pinError = validatePin(_pinCont.text);
    if (pinError != null) {
      setState(() => _error = pinError);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await deleteAccountCompletely(_pinCont.text.trim());
      if (!mounted) return;
      Navigator.pop(context, res.message.validate(value: 'Votre compte a été supprimé.'));
    } catch (e) {
      if (!mounted) return;
      // Messages du serveur : « Code PIN incorrect. », « Vous avez une commande en cours… »
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      setState(() {
        _isLoading = false;
        _error = message.isNotEmpty ? message : 'Impossible de supprimer le compte pour le moment.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(context, children: [
      _sheetIcon(Icons.person_off_outlined, _dangerRed),
      16.height,
      Text('Supprimer mon compte ?',
          textAlign: TextAlign.center, style: boldTextStyle(size: 20, color: kMisonDark)),
      8.height,
      Text(
        'Cette action est définitive. Vos informations personnelles seront effacées ; '
        'l\'historique de vos commandes est conservé de façon anonyme.',
        textAlign: TextAlign.center,
        style: secondaryTextStyle(size: 14),
      ),
      8.height,
      Text(
        'Impossible tant qu\'une commande est en cours.',
        textAlign: TextAlign.center,
        style: secondaryTextStyle(size: 13, color: _dangerRed),
      ),
      20.height,
      Text('Confirmez avec votre code PIN', style: boldTextStyle(size: 14, color: kMisonDark)),
      8.height,
      TextField(
        controller: _pinCont,
        enabled: !_isLoading,
        obscureText: true,
        keyboardType: pinKeyboardType,
        inputFormatters: pinInputFormatters,
        textAlign: TextAlign.center,
        style: boldTextStyle(size: 22, letterSpacing: 12),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _confirm(),
        decoration: InputDecoration(
          hintText: '••••',
          hintStyle: secondaryTextStyle(size: 22, letterSpacing: 12),
          filled: true,
          fillColor: kMisonFieldBg,
          errorText: _error,
          errorMaxLines: 3,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kMisonGold, width: 1.5),
          ),
        ),
      ),
      20.height,
      _primaryButton(
        label: 'Supprimer définitivement',
        color: _dangerRed,
        loading: _isLoading,
        onPressed: _confirm,
      ),
      10.height,
      _secondaryButton(
        label: 'Annuler',
        onPressed: _isLoading ? null : () => Navigator.pop(context),
      ),
    ]);
  }
}
