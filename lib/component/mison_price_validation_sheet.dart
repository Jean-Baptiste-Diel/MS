import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark;
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/feature_flags.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

String _fcfa(num value) {
  final digits = value.toStringAsFixed(0);
  return '${digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} FCFA';
}

/// Client : l'ouvrier a proposé un prix. Page au style de la page de paiement
/// (prix en grand, avertissement, boutons) ; elle ne se ferme pas tant que le
/// client n'a pas validé ou refusé. Renvoie true si une réponse a été envoyée.
Future<bool> showPriceValidationSheet(BuildContext context, MisonOrder order) async {
  final answered = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _PriceValidationSheet(order: order),
  );
  return answered == true;
}

class _PriceValidationSheet extends StatefulWidget {
  final MisonOrder order;

  const _PriceValidationSheet({required this.order});

  @override
  State<_PriceValidationSheet> createState() => _PriceValidationSheetState();
}

class _PriceValidationSheetState extends State<_PriceValidationSheet> {
  bool _busy = false;

  MisonOrder get order => widget.order;

  String get _artisanName {
    final name = order.artisan?.fullName ?? '';
    return name.isNotEmpty ? name : 'votre ouvrier';
  }

  Future<void> _answer(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    final price = order.priceProposal ?? 0;
    try {
      if (accept) {
        await acceptOrderPrice(order.id!);
        TopToast.show(message: 'Prix validé : ${_fcfa(price)}.', type: TopToastType.success);
      } else {
        await declineOrderPrice(order.id!);
        TopToast.show(message: 'Prix refusé. Le prestataire va vous faire une nouvelle proposition.');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Proposition plus valable (retirée, commande annulée…) : la page se
      // ferme et la commande est rechargée ; elle se rouvre s'il faut encore
      // répondre, sans jamais laisser le client bloqué sur une page morte.
      TopToast.show(message: e.toString(), type: TopToastType.error);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = order.priceProposal ?? 0;
    return PopScope(
      canPop: false,
      child: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 14, 24, MediaQuery.of(context).padding.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête : logo MISON
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset('assets/logo/logo_transparent.png', height: 30,
                      errorBuilder: (_, __, ___) => Text('MISON', style: boldTextStyle(size: 20, color: kMisonDark))),
                ),
              ),
              14.height,
              Text('PRIX PROPOSÉ PAR ${_artisanName.toUpperCase()}',
                  style: boldTextStyle(size: 15, color: kMisonGold, letterSpacing: 0.3)),
              6.height,
              Text(_fcfa(price), style: primaryTextStyle(size: 36, color: kMisonDark, weight: FontWeight.w600)),
              22.height,

              // Valider
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _answer(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kMisonGold,
                    disabledBackgroundColor: kMisonGold.withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text('Valider ce prix', style: boldTextStyle(color: Colors.white, size: 16)),
                ),
              ),
              10.height,
              // Refuser
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _answer(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kMisonDark,
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Refuser', style: boldTextStyle(color: kMisonDark, size: 16)),
                ),
              ),
              8.height,
              Text('Prix ferme • Payé à la fin de la prestation',
                  style: secondaryTextStyle(size: 13, color: kMisonDark.withValues(alpha: 0.75))),
              22.height,

              // Avertissement
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified_user_outlined, color: kMisonGold, size: 24),
                  14.width,
                  Expanded(
                    child: Text(
                      "Si vous validez, vous paierez ce prix avec ${FeatureFlags.paymentMethods}, dans l'application "
                      'MISON, à la fin de la prestation. Ne payez jamais le prestataire en espèces.',
                      style: primaryTextStyle(size: 15, color: kMisonDark.withValues(alpha: 0.85)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
