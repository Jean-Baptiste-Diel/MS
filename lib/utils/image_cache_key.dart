/// Clé de cache stable pour une image stockée sur MinIO.
///
/// Les liens d'images sont signés (paramètres X-Amz-… dans l'adresse) et
/// changent régulièrement. Mis en cache sous leur adresse complète, la même
/// image était retéléchargée à chaque nouveau lien. La clé ne garde que
/// l'emplacement du fichier : une image déjà vue s'affiche tout de suite.
/// Les fichiers ont des noms uniques (nouvelle photo = nouveau nom), donc
/// une image modifiée n'est jamais confondue avec l'ancienne.
String? imageCacheKey(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.queryParameters.containsKey('X-Amz-Signature')) return null;
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
}
