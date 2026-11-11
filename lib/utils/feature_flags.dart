import 'dart:io' show Platform;

import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:nb_utils/nb_utils.dart';

/// Nouveautés de l'app activées depuis le back-office (Réglages de la
/// plateforme), sans nouveau build. Reçues avec les versions (app/version) et
/// gardées sur le téléphone pour le lancement suivant. Cachées par défaut.
class FeatureFlags {
  static const _prefix = 'feature_';

  /// Appui long sur un message : réactions, Modifier, Supprimer.
  static bool get chatMessageActions => getBoolAsync('${_prefix}chat_message_actions');

  /// Bouton « Appeler le support » dans la discussion avec le support.
  static bool get supportCall => getBoolAsync('${_prefix}support_call');

  /// Fenêtre « Noter l'application » après 3 commandes.
  static bool get appReviewPrompt => getBoolAsync('${_prefix}app_review_prompt');

  /// Suivi des paiements en espèces (« Le client m'a payé en espèces », solde à régler).
  static bool get cashTracking => getBoolAsync('${_prefix}cash_tracking_enabled');

  /// Paiement Wave (coché par défaut).
  static bool get wave => getBoolAsync('${_prefix}wave_payment', defaultValue: true);

  /// Paiement Orange Money.
  static bool get orangeMoney => getBoolAsync('${_prefix}orange_money');

  /// Modes de paiement à proposer (au moins Wave si rien n'est coché).
  static List<String> get paymentMethodList {
    final list = [if (wave) 'Wave', if (orangeMoney) 'Orange Money'];
    return list.isEmpty ? ['Wave'] : list;
  }

  /// « Wave », « Orange Money » ou « Wave ou Orange Money » selon les cases cochées.
  static String get paymentMethods => paymentMethodList.join(' ou ');

  /// Relit les cases du back-office (ex. à l'ouverture d'une commande, avant
  /// de valider le prix ou de payer). Ne lève jamais.
  static Future<void> refresh() async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final res = await buildHttpResponse('app/version?platform=$platform', method: HttpMethodType.GET);
      if (res.statusCode != 200) return;
      final body = await handleResponse(res);
      if (body is Map) await apply(body['features']);
    } catch (_) {}
  }

  static Future<void> apply(dynamic features) async {
    if (features is! Map) return;
    for (final entry in features.entries) {
      await setValue('$_prefix${entry.key}', entry.value == true);
    }
  }
}
