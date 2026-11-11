import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/feature_flags.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:nb_utils/nb_utils.dart';

/// Fenêtre « Noter l'application » du téléphone (App Store sur iPhone,
/// Google Play sur Android), proposée une seule fois par compte :
/// - client : après 3 commandes passées (hors commandes annulées) ;
/// - ouvrier : après 3 commandes terminées.
///
/// Apple et Google décident ensuite eux-mêmes de l'afficher ou non (quelques
/// fois par an au plus) : la fenêtre peut donc ne pas apparaître.
class AppReviewPrompt {
  static const _threshold = 3;
  static bool _checking = false;

  static String get _askedKey => 'app_review_asked_${appStore.userId}';

  /// Appelé avec la liste complète des commandes du compte.
  static Future<void> maybeAsk(List<MisonOrder> orders) async {
    if (!FeatureFlags.appReviewPrompt) return; // activé dans le back-office
    if (_checking || !appStore.isLoggedIn || getBoolAsync(_askedKey)) return;
    final isArtisan = appStore.userType == USER_TYPE_PROVIDER;
    final count = isArtisan
        ? orders.where((o) => o.isCompleted).length
        : orders.where((o) => !o.isCancelled && !o.isRejected).length;
    if (count < _threshold) return;

    _checking = true;
    try {
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      // Pas au milieu d'un chargement d'écran : un court délai.
      await Future.delayed(const Duration(seconds: 2));
      await setValue(_askedKey, true);
      await review.requestReview();
    } catch (_) {
      // Fenêtre indisponible (pas de Google Play, simulateur...) : rien à faire.
    } finally {
      _checking = false;
    }
  }
}
