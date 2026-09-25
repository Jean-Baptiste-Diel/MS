import 'package:booking_system_flutter/utils/artisan_eta_tracker.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nb_utils/nb_utils.dart';

/// Heure d'arrivée estimée de l'ouvrier, calculée comme Google Maps : trajet
/// en voiture (trafic compris) de sa position en direct jusqu'à l'adresse.
///
/// La position vient de Firestore (artisan_locations/{orderId}), mise à jour par
/// l'app de l'ouvrier. Tant qu'elle n'est pas connue, [fallback] est affiché.
class ArtisanArrivalEta extends StatefulWidget {
  final String orderId;
  final LatLng? destination;
  final String fallback;
  final TextStyle? style;

  const ArtisanArrivalEta({
    Key? key,
    required this.orderId,
    required this.destination,
    required this.fallback,
    this.style,
  }) : super(key: key);

  @override
  State<ArtisanArrivalEta> createState() => _ArtisanArrivalEtaState();
}

class _ArtisanArrivalEtaState extends State<ArtisanArrivalEta> {
  // Suivi partagé avec la carte de suivi : un seul calcul Google Directions
  late final ArtisanEtaTracker _tracker;

  @override
  void initState() {
    super.initState();
    _tracker = ArtisanEtaTracker.acquire(widget.orderId, widget.destination);
    _tracker.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tracker.removeListener(_onUpdate);
    _tracker.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eta = _tracker.eta;
    final String text;
    if (eta == null) {
      text = widget.fallback;
    } else if (eta.seconds < 60) {
      text = 'Arrive dans moins d\'une minute';
    } else {
      // Comme Google Maps : heure d'arrivée + durée restante.
      text = 'Arrivée ~${eta.arrivalTime} · ${eta.durationText}';
    }
    return Text(text, style: widget.style ?? boldTextStyle(size: 16), maxLines: 2, overflow: TextOverflow.ellipsis);
  }
}
