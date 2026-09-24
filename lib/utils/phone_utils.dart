/// Préfixes valides des numéros mobiles sénégalais.
const List<String> senegalPhonePrefixes = ['70', '71', '75', '76', '77', '78', '79'];

/// Valide un numéro sénégalais local (sans +221).
/// Retourne un message d'erreur précis, ou null si le numéro est valide.
String? validateSenegalPhone(String value) {
  final digits = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  if (digits.length >= 2 && !senegalPhonePrefixes.contains(digits.substring(0, 2))) {
    return 'Le numéro doit commencer par 70, 71, 75, 76, 77, 78 ou 79';
  }
  if (!RegExp(r'^\d{9}$').hasMatch(digits)) {
    return 'Le numéro doit être composé de 9 chiffres';
  }
  return null;
}
