import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/services/mison_call_session.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

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
  if (active != null && active.orderId == orderId) {
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
