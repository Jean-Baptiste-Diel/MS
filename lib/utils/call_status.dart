import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
/// L'appelé a décroché et rejoint l'appel : l'appelant passe en « appel en cours ».
const kCallAccepted = 'accepted';

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

/// Identifiants CallKit des appels en cours d'une commande ([acceptedOnly] :
/// seulement ceux décrochés ou sortants, pas ceux qui sonnent).
Future<List<String>> callKitIdsFor(String orderId, {bool acceptedOnly = false}) async {
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is! List) return [];
    return [
      for (final call in calls)
        if (call is Map)
          if (((call['extra'] as Map?)?['order_id']?.toString() ?? call['id']?.toString()) == orderId)
            if (!acceptedOnly || call['accepted'] == true || call['isAccepted'] == true)
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
  _clearOngoingNotifications(ids);
}

/// Android : retire les notifications « Appel en cours / Raccrocher » de ces
/// appels. Le module d'appel ne retire que celle de son service ; une autre
/// (deuxième appel système de la même conversation, ou réaffichée par
/// « appel connecté » juste après la fin) restait affichée. Refait 2 s plus
/// tard pour celle qui serait réaffichée après coup.
void _clearOngoingNotifications(Iterable<String> callKitIds) {
  if (!Platform.isAndroid) return;
  final notifIds = [for (final id in callKitIds) _javaHashCode('ongoing_$id')];
  Future<void> cancel() async {
    final plugin = FlutterLocalNotificationsPlugin();
    for (final n in notifIds) {
      await plugin.cancel(n).catchError((_) {});
    }
  }
  cancel();
  Future.delayed(const Duration(seconds: 2), cancel);
}

/// String.hashCode() de Java : identifiant de notification du module d'appel.
int _javaHashCode(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (31 * h + c) & 0xFFFFFFFF;
  }
  return h >= 0x80000000 ? h - 0x100000000 : h;
}

/// Fin d'un appel MISON (un seul appel à la fois) : ferme aussi tout appel
/// encore marqué « en cours » dans le système (décroché ou sortant), pour
/// qu'aucune notification « Appel en cours » ne reste affichée. Les appels qui
/// sonnent encore (pas décrochés) ne sont pas touchés.
Future<void> endLeftoverConnectedCalls() async {
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is! List) return;
    final ended = <String>[];
    for (final call in calls) {
      if (call is! Map) continue;
      // iOS : « accepted » ; Android : « isAccepted » (appel décroché ou sortant).
      if (call['accepted'] != true && call['isAccepted'] != true) continue;
      final id = call['id']?.toString();
      if (id != null && id.isNotEmpty) {
        ended.add(id);
        await FlutterCallkitIncoming.endCall(id).catchError((_) {});
      }
    }
    _clearOngoingNotifications(ended);
    // Filet de sécurité : plus aucun appel qui sonne → on ferme tout ce que le
    // module d'appel garde encore (notification « Raccrocher » restée affichée).
    final left = await FlutterCallkitIncoming.activeCalls();
    final ringing = left is List &&
        left.any((c) => c is Map && c['accepted'] != true && c['isAccepted'] != true);
    if (!ringing) await FlutterCallkitIncoming.endAllCalls();
  } catch (_) {}
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

/// L'appelé a décroché et il est dans l'appel.
Future<void> markCallAccepted(String orderId) => _setStatus(orderId, kCallAccepted);

/// L'appelant raccroche avant que l'appelé ait répondu.
Future<void> markCallCancelled(String orderId) => _setStatus(orderId, kCallCancelled);

/// Efface le statut d'un appel précédent. À faire AVANT de faire sonner
/// l'appelé, sinon un ancien « rejected » / « cancelled » couperait le nouvel appel.
Future<void> resetCallStatus(String orderId) => _doc(orderId).delete().catchError((_) {});

/// Statut courant de l'appel (null tant que personne n'a refusé ni annulé).
///
/// Seules les valeurs confirmées par le serveur comptent : Firestore renvoie
/// d'abord sa copie locale, qui peut contenir le « cancelled » / « missed » d'un
/// appel précédent (le serveur, lui, a été remis à zéro avant ce nouvel appel).
/// Sans ce filtre, l'appel était coupé aussitôt : Android ne sonnait pas,
/// l'iPhone raccrochait juste après le décroché.
Stream<String?> callStatusStream(String orderId) => _doc(orderId)
    .snapshots(includeMetadataChanges: true)
    .where((snap) => !snap.metadata.isFromCache)
    .map((snap) => snap.data()?['status']?.toString())
    .distinct();

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
