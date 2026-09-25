/// Format attendu d'un numéro mobile sénégalais, ajouté à chaque message
/// d'erreur pour guider l'utilisateur.
const String senegalPhoneFormatHint =
    'Format attendu : 9 chiffres commençant par 70, 71, 75, 76, 77 ou 78 (ex : 77 123 45 67)';

/// Préfixes à 2 chiffres qu'aucun opérateur sénégalais n'utilise.
const Set<String> senegalUnusedPrefixes = {'73', '74'};

/// Valide un numéro mobile sénégalais local (sans +221).
/// Contrôle volontairement large : les plages exactes par opérateur sont
/// vérifiées par le back-end (libphonenumber).
/// Retourne un message d'erreur avec le bon format, ou null si le numéro est valide.
String? validateSenegalPhone(String value) {
  final digits = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  if (digits.isNotEmpty && !digits.startsWith('7')) {
    return 'Un numéro sénégalais commence par 7. $senegalPhoneFormatHint';
  }
  if (digits.length >= 2 && senegalUnusedPrefixes.contains(digits.substring(0, 2))) {
    return 'Les numéros en ${digits.substring(0, 2)} n\'existent pas au Sénégal. $senegalPhoneFormatHint';
  }
  if (!RegExp(r'^\d{9}$').hasMatch(digits)) {
    return 'Le numéro doit contenir 9 chiffres. $senegalPhoneFormatHint';
  }
  return null;
}

/// Vrai si le message du serveur signale un numéro invalide
/// ("Numero de telephone invalide." ou "...must be a valid international phone number...").
/// Ne couvre pas "a user with this phone number already exists".
bool isInvalidPhoneError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('telephone invalide') || lower.contains('valid international phone');
}

/// Remplace le message brut du serveur pour un numéro invalide par un message
/// clair rappelant le bon format ; les autres messages sont renvoyés tels quels.
String friendlyPhoneError(String message, {required String phoneCode}) {
  if (!isInvalidPhoneError(message)) return message;
  return phoneCode == '221'
      ? 'Ce numéro n\'existe pas au Sénégal. $senegalPhoneFormatHint'
      : 'Numéro de téléphone invalide pour ce pays';
}

/// Indicatifs des pays où le 0 initial fait partie du numéro international
/// (Côte d'Ivoire, Congo, Gabon, Bénin, Italie/Vatican, Saint-Marin) :
/// il ne faut pas le retirer.
const Set<String> phoneCodesKeepingLeadingZero = {'225', '242', '241', '229', '39', '378', '379'};

/// Construit le numéro international (E.164) à partir de la saisie locale.
/// Retire les séparateurs et le 0 national (ex: 06 12 34 56 78), qui ne se
/// compose pas après l'indicatif.
String buildInternationalPhone(String input, {required String phoneCode}) {
  var local = input.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
  if (local.isEmpty) return '';
  if (!phoneCodesKeepingLeadingZero.contains(phoneCode)) {
    local = local.replaceFirst(RegExp(r'^0+'), '');
  }
  return '+$phoneCode$local';
}
