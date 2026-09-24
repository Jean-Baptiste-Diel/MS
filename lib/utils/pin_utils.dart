import 'package:flutter/services.dart';

/// Le mot de passe de l'application est un code PIN de 4 chiffres.
const int PIN_LENGTH = 4;

/// Clavier et saisie limitée à 4 chiffres.
const TextInputType pinKeyboardType = TextInputType.number;
final List<TextInputFormatter> pinInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(PIN_LENGTH),
];

/// Retourne un message d'erreur, ou null si le PIN est valide.
String? validatePin(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Code PIN requis';
  if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'Le code PIN doit contenir 4 chiffres';
  return null;
}

/// Vérifie la confirmation du PIN.
String? validatePinConfirmation(String? value, String pin) {
  final error = validatePin(value);
  if (error != null) return error;
  if (value!.trim() != pin.trim()) return 'Les codes PIN ne correspondent pas';
  return null;
}
