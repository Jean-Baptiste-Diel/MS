import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/services/mison_call_session.dart';
import 'package:booking_system_flutter/utils/call_status.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Appel en cours de lancement (jeton demandé, écran pas encore ouvert).
/// Un deuxième appui pendant ce temps renvoyait une demande de jeton avec
/// notify=true : l'appelé sonnait 2 à 4 fois. Les boutons « Appeler »
/// l'écoutent pour se désactiver.
final ValueNotifier<bool> isStartingCall = ValueNotifier(false);

/// Lance un appel (Agora) avec l'autre partie d'une commande.
/// Utilisé par le détail de commande et par la discussion de la commande.
Future<void> startMisonOrderCall(
  BuildContext context, {
  required String orderId,
  required String otherPartyName,
}) async {
  // Appel déjà en cours pour cette commande (écran réduit) : on y revient au
  // lieu d'en relancer un, qui referait sonner l'autre partie.
  final active = MisonCallSession.current.value;
  if (active != null && !active.ended && active.orderId == orderId) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MisonCallScreen(
        orderId: active.orderId,
        otherPartyName: active.otherPartyName,
        appId: active.appId,
        channel: active.channel,
        token: active.token,
        uid: active.uid,
        isCaller: active.isCaller,
      ),
    ));
    return;
  }

  // Un seul lancement à la fois (double appui, deux boutons).
  if (isStartingCall.value) return;
  // Un autre appel est en cours : on n'en lance pas un second.
  if (active != null && !active.ended) {
    TopToast.show(message: 'Un appel est déjà en cours');
    return;
  }
  isStartingCall.value = true;
  try {
    await _startOrderCall(context, orderId: orderId, otherPartyName: otherPartyName);
  } finally {
    isStartingCall.value = false;
  }
}

Future<void> _startOrderCall(
  BuildContext context, {
  required String orderId,
  required String otherPartyName,
}) async {
  // Efface le refus / l'annulation d'un appel précédent AVANT de faire sonner
  // l'appelé : sinon ce vieux statut couperait immédiatement le nouvel appel.
  await resetCallStatus(orderId);

  // Await the SharedPreferences write before the API call triggers FCM.
  // data-only FCM (content-available:1) can arrive in the background isolate
  // before the async write completes if not awaited here.
  await MisonCallScreen.markOutgoing(orderId);
  appStore.setLoading(true);
  try {
    final tokenData = await getCallToken(orderId);
    appStore.setLoading(false);
    if (tokenData.appId == null || tokenData.appId!.isEmpty || (tokenData.token ?? '').isEmpty) {
      MisonCallScreen.clearOutgoing(orderId);
      TopToast.show(message: 'Service d\'appel indisponible pour le moment');
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MisonCallScreen(
          orderId: orderId,
          otherPartyName: otherPartyName.isNotEmpty ? otherPartyName : 'Correspondant',
          appId: tokenData.appId ?? '',
          channel: tokenData.channel ?? '',
          token: tokenData.token ?? '',
          uid: tokenData.uid ?? 1,
          isCaller: true,
        ),
      ),
    );
  } catch (e, st) {
    MisonCallScreen.clearOutgoing(orderId);
    appStore.setLoading(false);
    log('startMisonOrderCall error: $e\n$st');
    TopToast.show(
      message: isNotFoundError(e) ? kOrderUnavailableMessage : 'Impossible d\'initier l\'appel : $e',
      type: TopToastType.error,
    );
  }
}

/// Appeler le support MISON depuis la discussion : ça sonne dans le
/// back-office, le premier membre de l'équipe qui décroche répond.
Future<void> startSupportCall(BuildContext context, {required String conversationId}) async {
  final callId = supportCallId(conversationId);
  final active = MisonCallSession.current.value;
  if (active != null && !active.ended && active.orderId == callId) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MisonCallScreen(
        orderId: active.orderId,
        otherPartyName: active.otherPartyName,
        appId: active.appId,
        channel: active.channel,
        token: active.token,
        uid: active.uid,
        isCaller: active.isCaller,
      ),
    ));
    return;
  }
  if (isStartingCall.value) return;
  if (active != null && !active.ended) {
    TopToast.show(message: 'Un appel est déjà en cours');
    return;
  }
  isStartingCall.value = true;
  try {
    await _startSupportCall(context, conversationId: conversationId, callId: callId);
  } finally {
    isStartingCall.value = false;
  }
}

Future<void> _startSupportCall(BuildContext context, {required String conversationId, required String callId}) async {
  await resetCallStatus(callId);
  await MisonCallScreen.markOutgoing(callId);
  appStore.setLoading(true);
  try {
    final tokenData = await getSupportCallToken(conversationId);
    appStore.setLoading(false);
    if (tokenData.appId == null || tokenData.appId!.isEmpty || (tokenData.token ?? '').isEmpty) {
      MisonCallScreen.clearOutgoing(callId);
      TopToast.show(message: "Service d'appel indisponible pour le moment");
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MisonCallScreen(
          orderId: callId,
          otherPartyName: 'Support MISON',
          appId: tokenData.appId ?? '',
          channel: tokenData.channel ?? '',
          token: tokenData.token ?? '',
          uid: tokenData.uid ?? 2,
          isCaller: true,
        ),
      ),
    );
  } catch (e) {
    MisonCallScreen.clearOutgoing(callId);
    appStore.setLoading(false);
    TopToast.show(message: "Impossible d'appeler le support : $e", type: TopToastType.error);
  }
}
