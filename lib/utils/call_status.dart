import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:nb_utils/nb_utils.dart';

/// Signalisation d'un appel entre les deux téléphones, via Firestore
/// (call_status/{orderId}) :
/// - "rejected"  : l'appelé a refusé → l'appel se termine chez l'appelant ;
/// - "cancelled" : l'appelant a raccroché avant la réponse → la sonnerie
///   s'arrête chez l'appelé.
const kCallRejected = 'rejected';
const kCallCancelled = 'cancelled';
/// L'appel a sonné sans réponse chez l'appelé (délai dépassé).
const kCallMissed = 'missed';

// ── Identifiant de l'appel dans l'écran d'appel du téléphone (CallKit) ──────
// Un identifiant UNIQUE par appel (recommandation Apple). Avant, c'était
// l'identifiant de la commande : un nouvel appel sur la même commande, alors
// que le précédent n'était pas encore libéré par iOS, était refusé — le
// téléphone sonnait sans rien afficher et ne raccrochait plus. Le numéro de
// commande voyage dans extra['order_id'] ; on retrouve les appels avec.

/// Nouvel identifiant d'appel (UUID v4).
String newCallKitId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Identifiants CallKit des appels en cours d'une commande.
Future<List<String>> callKitIdsFor(String orderId) async {
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is! List) return [];
    return [
      for (final call in calls)
        if (call is Map)
          if (((call['extra'] as Map?)?['order_id']?.toString() ?? call['id']?.toString()) == orderId)
            call['id'].toString(),
    ];
  } catch (_) {
    return [];
  }
}

/// Termine l'écran d'appel du téléphone pour cette commande (sonnerie ou appel).
Future<void> endCallKitForOrder(String orderId) async {
  final ids = await callKitIdsFor(orderId);
  // Anciennes versions : l'identifiant était celui de la commande.
  if (!ids.contains(orderId)) ids.add(orderId);
  for (final id in ids) {
    await FlutterCallkitIncoming.endCall(id).catchError((_) {});
  }
}

/// Indique au téléphone que l'appel de cette commande est connecté.
Future<void> connectCallKitForOrder(String orderId) async {
  for (final id in await callKitIdsFor(orderId)) {
    await FlutterCallkitIncoming.setCallConnected(id).catchError((_) {});
  }
}

DocumentReference<Map<String, dynamic>> _doc(String orderId) =>
    FirebaseFirestore.instance.collection('call_status').doc(orderId);

Future<void> _setStatus(String orderId, String status) =>
    _doc(orderId).set({'status': status, 'at': FieldValue.serverTimestamp()}).catchError((e) {
      log('call_status $status: $e');
    });

/// L'appelé refuse l'appel.
Future<void> markCallDeclined(String orderId) => _setStatus(orderId, kCallRejected);

/// L'appel a sonné sans réponse chez l'appelé.
Future<void> markCallMissed(String orderId) => _setStatus(orderId, kCallMissed);

/// L'appelant raccroche avant que l'appelé ait répondu.
Future<void> markCallCancelled(String orderId) => _setStatus(orderId, kCallCancelled);

/// Efface le statut d'un appel précédent. À faire AVANT de faire sonner
/// l'appelé, sinon un ancien « rejected » / « cancelled » couperait le nouvel appel.
Future<void> resetCallStatus(String orderId) => _doc(orderId).delete().catchError((_) {});

/// Statut courant de l'appel (null tant que personne n'a refusé ni annulé).
Stream<String?> callStatusStream(String orderId) =>
    _doc(orderId).snapshots().map((snap) => snap.data()?['status']?.toString());

/// Suit un appel entrant pendant qu'il sonne, y compris app en arrière-plan ou
/// fermée (appelé depuis le handler FCM, qui tourne sans l'interface) :
/// - « Refuser » dans la notification / CallKit → l'appelant est prévenu ;
/// - l'appelant annule → la sonnerie s'arrête.
/// S'arrête seul une fois l'appel accepté, refusé, terminé, ou après 60 s.
/// Appels déjà suivis (un seul suivi par appel, même s'il est lancé de
/// plusieurs endroits : notification FCM, écran d'appel natif, démarrage).
final Set<String> _watchedCalls = {};

void watchIncomingCall(String orderId) {
  if (!_watchedCalls.add(orderId)) return;
  StreamSubscription? events;
  StreamSubscription? status;
  Timer? timeout;

  void stop() {
    events?.cancel();
    status?.cancel();
    timeout?.cancel();
    _watchedCalls.remove(orderId);
  }

  events = FlutterCallkitIncoming.onEvent.listen((event) {
    if (event == null) return;
    final extra = (event.body['extra'] as Map?)?.cast<String, dynamic>() ?? {};
    final id = extra['order_id']?.toString() ?? event.body['id']?.toString();
    if (id != orderId) return;
    switch (event.event) {
      case Event.actionCallDecline:
        markCallDeclined(orderId);
        stop();
      case Event.actionCallTimeout:
        markCallMissed(orderId); // sonné sans réponse ≠ refusé
        stop();
      case Event.actionCallAccept:
      case Event.actionCallEnded:
        stop();
      default:
        break;
    }
  });

  status = callStatusStream(orderId).listen((value) {
    if (value == kCallCancelled) {
      endCallKitForOrder(orderId);
      stop();
    }
  });

  timeout = Timer(const Duration(seconds: 60), stop);
}
