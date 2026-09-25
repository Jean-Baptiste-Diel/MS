import 'dart:async';

/// Bus d'événements « commande modifiée ».
///
/// Remplace LiveStream (nb_utils) pour ce besoin : LiveStream n'enregistre que
/// le premier abonné d'une clé (et aucun si la clé a déjà été émise), et son
/// dispose() supprime la clé pour tous les écrans. Ici chaque écran a sa propre
/// souscription et l'annule sans impacter les autres.
class OrderEvents {
  static final StreamController<String?> _controller = StreamController<String?>.broadcast();

  static Stream<String?> get stream => _controller.stream;

  /// [orderId] null = toutes les commandes sont potentiellement concernées.
  static void emit([String? orderId]) => _controller.add(orderId);
}
