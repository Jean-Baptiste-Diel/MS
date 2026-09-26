import 'dart:async';

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

DocumentReference<Map<String, dynamic>> _doc(String orderId) =>
    FirebaseFirestore.instance.collection('call_status').doc(orderId);

Future<void> _setStatus(String orderId, String status) =>
    _doc(orderId).set({'status': status, 'at': FieldValue.serverTimestamp()}).catchError((e) {
      log('call_status $status: $e');
    });

/// L'appelé refuse l'appel.
Future<void> markCallDeclined(String orderId) => _setStatus(orderId, kCallRejected);

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
void watchIncomingCall(String orderId) {
  StreamSubscription? events;
  StreamSubscription? status;
  Timer? timeout;

  void stop() {
    events?.cancel();
    status?.cancel();
    timeout?.cancel();
  }

  events = FlutterCallkitIncoming.onEvent.listen((event) {
    if (event == null) return;
    final extra = (event.body['extra'] as Map?)?.cast<String, dynamic>() ?? {};
    final id = extra['order_id']?.toString() ?? event.body['id']?.toString();
    if (id != orderId) return;
    switch (event.event) {
      case Event.actionCallDecline:
      case Event.actionCallTimeout:
        markCallDeclined(orderId);
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
      FlutterCallkitIncoming.endCall(orderId).catchError((_) {});
      stop();
    }
  });

  timeout = Timer(const Duration(seconds: 60), stop);
}
