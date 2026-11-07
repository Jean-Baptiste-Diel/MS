import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/pin_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_native_contact_picker/model/contact.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:share_plus/share_plus.dart';

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

// ── Signalement ─────────────────────────────────────────────────────────────

/// Motifs de signalement (mêmes codes que le serveur).
const kReportReasons = <String, String>{
  'harassment': 'Insultes ou harcèlement',
  'inappropriate': 'Contenu choquant ou inapproprié',
  'spam': 'Spam ou publicité',
  'fraud': 'Arnaque ou fraude',
  'other': 'Autre',
};

/// Choix du motif d'un signalement (ou d'un blocage). Retourne le code du
/// motif, ou null si annulé.
Future<String?> showMisonReportSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  IconData icon = Icons.flag_outlined,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _sheetFrame(sheetContext, children: [
      _sheetIcon(icon, _dangerRed),
      16.height,
      Text(title, textAlign: TextAlign.center, style: boldTextStyle(size: 20, color: kMisonDark)),
      8.height,
      Text(subtitle, textAlign: TextAlign.center, style: secondaryTextStyle(size: 14)),
      16.height,
      for (final reason in kReportReasons.entries)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(reason.value, style: primaryTextStyle(size: 15, color: kMisonDark)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          onTap: () => Navigator.pop(sheetContext, reason.key),
        ),
      10.height,
      _secondaryButton(label: 'Annuler', onPressed: () => Navigator.pop(sheetContext)),
    ]),
  );
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


// ── Inviter un ami ───────────────────────────────────────────────────────────

/// Numéro d'un contact au format attendu par le serveur : chiffres seuls,
/// « 00221… » devient « +221… » ; sans indicatif, le serveur ajoute +221.
String _contactPhone(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  return cleaned.startsWith('00') ? '+${cleaned.substring(2)}' : cleaned;
}

/// Ouvre la liste de contacts du téléphone (sélecteur du système : l'app ne
/// voit que le contact choisi, aucune autorisation sur tout le répertoire).
Future<Contact?> _pickContact() async {
  try {
    final contact = await FlutterNativeContactPicker().selectPhoneNumber();
    final phone = contact?.selectedPhoneNumber ?? contact?.phoneNumbers?.firstOrNull;
    if (phone == null || phone.trim().isEmpty) return null;
    return Contact(fullName: contact?.fullName, selectedPhoneNumber: phone);
  } catch (_) {
    return null;
  }
}

const _kAndroidAppUrl = 'https://play.google.com/store/apps/details?id=com.mison.serviceuser';

/// Texte partagé sur WhatsApp, Facebook, Messenger, etc.
const _kInviteText = "Je te recommande MISON pour trouver des ouvriers qualifiés et vérifiés près de chez toi. "
    "Télécharge l'application :\n"
    'Android : $_kAndroidAppUrl\n'
    'iPhone : $IOS_LINK_FOR_USER';

/// « Inviter un ami » : partage du lien via les applications du téléphone
/// (WhatsApp, Facebook, Messenger…), ou SMS envoyé par MISON à un contact.
/// Retourne le message de confirmation (SMS), ou null.
Future<String?> showMisonInviteFriendSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _sheetFrame(sheetContext, children: [
      _sheetIcon(Icons.card_giftcard_rounded, kMisonGold),
      16.height,
      Text('Inviter un ami', textAlign: TextAlign.center, style: boldTextStyle(size: 20, color: kMisonDark)),
      8.height,
      Text(
        "Envoyez-lui le lien de l'application MISON, pour Android et iPhone.",
        textAlign: TextAlign.center,
        style: secondaryTextStyle(size: 14),
      ),
      20.height,
      _primaryButton(
        label: 'Partager via WhatsApp, Facebook…',
        color: kMisonGold,
        onPressed: () => Navigator.pop(sheetContext, 'share'),
      ),
      10.height,
      _secondaryButton(
        label: 'Envoyer un SMS à un contact',
        onPressed: () => Navigator.pop(sheetContext, 'sms'),
      ),
    ]),
  );
  if (!context.mounted) return null;
  if (choice == 'share') {
    // Feuille de partage du téléphone : WhatsApp, Facebook, Messenger, SMS…
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: _kInviteText,
      subject: 'Découvre MISON',
      sharePositionOrigin: box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
    ));
    return null;
  }
  if (choice != 'sms') return null;
  final contact = await _pickContact();
  if (contact == null || !context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InviteFriendSheet(contact: contact),
  );
}

class _InviteFriendSheet extends StatefulWidget {
  final Contact contact;

  const _InviteFriendSheet({required this.contact});

  @override
  State<_InviteFriendSheet> createState() => _InviteFriendSheetState();
}

class _InviteFriendSheetState extends State<_InviteFriendSheet> {
  late Contact _contact = widget.contact;
  bool _isLoading = false;
  String? _error;

  Future<void> _changeContact() async {
    final contact = await _pickContact();
    if (contact == null || !mounted) return;
    setState(() {
      _contact = contact;
      _error = null;
    });
  }

  Future<void> _send() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await inviteFriend(_contactPhone(_contact.selectedPhoneNumber!));
      if (!mounted) return;
      Navigator.pop(context, res.message.validate(value: 'Invitation envoyée.'));
    } catch (e) {
      if (!mounted) return;
      // Messages du serveur : « Numéro de téléphone invalide. », « C'est votre propre numéro. »
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      setState(() {
        _isLoading = false;
        _error = message.isNotEmpty ? message : "Impossible d'envoyer l'invitation pour le moment.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _contact.fullName.validate();
    return _sheetFrame(context, children: [
      _sheetIcon(Icons.card_giftcard_rounded, kMisonGold),
      16.height,
      Text('Inviter un ami',
          textAlign: TextAlign.center, style: boldTextStyle(size: 20, color: kMisonDark)),
      8.height,
      Text(
        "MISON lui envoie un SMS avec le lien de l'application, pour Android et iPhone.",
        textAlign: TextAlign.center,
        style: secondaryTextStyle(size: 14),
      ),
      20.height,
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kMisonFieldBg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.person_rounded, color: kMisonGold),
          12.width,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (name.isNotEmpty) Text(name, style: boldTextStyle(size: 15, color: kMisonDark)),
            Text(_contact.selectedPhoneNumber!, style: secondaryTextStyle(size: 14)),
          ]).expand(),
          TextButton(
            onPressed: _isLoading ? null : _changeContact,
            child: Text('Changer', style: boldTextStyle(size: 13, color: kMisonGold)),
          ),
        ]),
      ),
      if (_error != null) ...[
        8.height,
        Text(_error!, style: secondaryTextStyle(size: 13, color: _dangerRed)),
      ],
      20.height,
      _primaryButton(
        label: "Envoyer l'invitation",
        color: kMisonGold,
        loading: _isLoading,
        onPressed: _send,
      ),
      10.height,
      _secondaryButton(
        label: 'Annuler',
        onPressed: _isLoading ? null : () => Navigator.pop(context),
      ),
    ]);
  }
}
