import 'package:booking_system_flutter/model/mison_service_model.dart';

/// Texte en minuscules, sans accents : « Électricité » → « electricite ».
String normalizeSearch(String text) {
  const from = 'àâäáãçéèêëíìîïñóòôöõúùûüÿ';
  const to = 'aaaaaceeeeiiiinooooouuuuy';
  final out = StringBuffer();
  for (final ch in text.toLowerCase().trim().split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}

/// Services correspondant à [query], les plus pertinents d'abord : nom qui
/// commence par le texte (« car » → Carreleur), puis un mot du nom qui
/// commence par le texte, puis le nom qui le contient, puis la description.
/// Accents ignorés. Recherche vide : tous les services, dans l'ordre reçu.
List<MisonService> searchServices(List<MisonService> services, String query) {
  final q = normalizeSearch(query);
  if (q.isEmpty) return services;
  int score(MisonService s) {
    final name = normalizeSearch(s.name ?? '');
    if (name.startsWith(q)) return 0;
    if (name.split(RegExp(r'[\s\-/]+')).any((w) => w.startsWith(q))) return 1;
    if (name.contains(q)) return 2;
    if (normalizeSearch(s.description ?? '').contains(q)) return 3;
    return 99;
  }

  final scored = [
    for (final s in services)
      if (score(s) < 99) (s, score(s)),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final e in scored) e.$1];
}
