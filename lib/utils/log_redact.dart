/// Masque les données sensibles avant de les écrire dans la console.
///
/// Les journaux de développement contenaient en clair le jeton de connexion,
/// les jetons de notification, les codes PIN / OTP, les noms, e-mails et
/// numéros de téléphone : partagés pour déboguer, ils suffisaient à se
/// connecter au compte de l'utilisateur.
library;

final _sensitiveJsonKeys = RegExp(
  r'"(authorization|access|refresh|token|access_token|refresh_token|fcm_token|voip_token|'
  r'password|new_password|old_password|pin|otp|otp_code|first_name|last_name|full_name|'
  r'sender_name|email|phone|identifier)"\s*:\s*"[^"]*"',
  caseSensitive: false,
);
final _bearer = RegExp(r'Bearer\s+[A-Za-z0-9\-_\.=]+');
final _jwt = RegExp(r'eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+');
final _tokenParam = RegExp(r'((?:token|key)=)[^&\s"]+', caseSensitive: false);
final _fcmToken = RegExp(r'[A-Za-z0-9\-_]{20,}:APA91[A-Za-z0-9\-_]+');
final _senegalPhone = RegExp(r'(\+?221)(\d{2})\d{5}(\d{2})');

String redactForLog(Object? value) {
  var text = value?.toString() ?? '';
  text = text.replaceAllMapped(_sensitiveJsonKeys, (m) => '"${m.group(1)}":"***"');
  text = text.replaceAll(_bearer, 'Bearer ***');
  text = text.replaceAll(_jwt, '***');
  text = text.replaceAllMapped(_tokenParam, (m) => '${m.group(1)}***');
  text = text.replaceAll(_fcmToken, '***');
  text = text.replaceAllMapped(_senegalPhone, (m) => '${m.group(1)}${m.group(2)}*****${m.group(3)}');
  return text;
}
