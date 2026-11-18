import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark;
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Choix de l'ouvrier sur la page « Prix de la prestation ».
enum PriceFirstAction { chat, call, enterPrice, goAnyway }

/// Ouvrier, avant d'aller chez le client : page qui l'invite à discuter avec
/// le client pour tomber d'accord sur le prix (même style que la page de
/// paiement). Renvoie le choix, ou null si la page est fermée.
Future<PriceFirstAction?> showPriceFirstSheet(BuildContext context, {required MisonOrder order}) {
  return showModalBottomSheet<PriceFirstAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PriceFirstSheet(order: order),
  );
}

class _PriceFirstSheet extends StatelessWidget {
  final MisonOrder order;

  const _PriceFirstSheet({required this.order});

  String get _clientFirstName {
    final name = order.client?.fullName ?? '';
    return name.isNotEmpty ? name.split(' ').first : 'le client';
  }

  bool get _waitingClient => order.priceProposal != null && order.priceProposedBy == 'artisan';

  @override
  Widget build(BuildContext context) {
    final canGo = !order.priceAgreementRequired;
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 14, 16, MediaQuery.of(context).padding.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset('assets/logo/logo_transparent.png', height: 30,
                    errorBuilder: (_, __, ___) => Text('MISON', style: boldTextStyle(size: 20, color: kMisonDark))),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 26),
                  color: kMisonDark,
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Fermer',
                ),
              ],
            ),
            14.height,
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PRIX DE LA PRESTATION', style: boldTextStyle(size: 15, color: kMisonGold, letterSpacing: 0.3)),
                  6.height,
                  Text(
                    _waitingClient ? 'En attente de $_clientFirstName' : 'Mettez-vous d’accord sur le prix',
                    style: primaryTextStyle(size: 30, color: kMisonDark, weight: FontWeight.w600),
                  ),
                  6.height,
                  Text(
                    _waitingClient
                        ? 'Vous avez envoyé votre prix : $_clientFirstName doit le valider dans l’application.'
                        : 'Avant d’aller chez $_clientFirstName, discutez avec lui par message ou par appel '
                            'pour tomber d’accord sur le prix.',
                    style: secondaryTextStyle(size: 14, color: kMisonDark.withValues(alpha: 0.7)),
                  ),
                  20.height,

                  // Discuter : message ou appel
                  _button(
                    context,
                    label: 'Discuter avec le client',
                    icon: Icons.chat_bubble_outline_rounded,
                    action: PriceFirstAction.chat,
                    filled: true,
                  ),
                  10.height,
                  _button(context, label: 'Appeler le client', icon: Icons.call_rounded, action: PriceFirstAction.call),

                  // Accord trouvé : entrer le prix (après avoir discuté)
                  if (!_waitingClient && order.canChat) ...[
                    10.height,
                    Opacity(
                      opacity: order.hasDiscussed ? 1 : 0.45,
                      child: IgnorePointer(
                        ignoring: !order.hasDiscussed,
                        child: _button(
                          context,
                          label: 'Nous sommes d’accord : entrer le prix',
                          icon: Icons.handshake_outlined,
                          action: PriceFirstAction.enterPrice,
                        ),
                      ),
                    ),
                  ],
                  if (canGo) ...[
                    10.height,
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, PriceFirstAction.goAnyway),
                        child: Text('Partir sans prix convenu',
                            style: secondaryTextStyle(size: 14, color: kMisonDark.withValues(alpha: 0.75))),
                      ),
                    ),
                  ],
                  8.height,
                  Text(
                    order.hasDiscussed || _waitingClient
                        ? 'Le client valide le prix • Il est ferme ensuite'
                        : 'Discutez d’abord, puis entrez le prix convenu',
                    style: secondaryTextStyle(size: 13, color: kMisonDark.withValues(alpha: 0.75)),
                  ),
                  22.height,

                  // Avertissement
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_outlined, color: kMisonGold, size: 24),
                      14.width,
                      Expanded(
                        child: Text(
                          canGo
                              ? 'Un prix convenu avant de partir évite les désaccords sur place.'
                              : 'Vous pourrez partir dès que le client aura validé le prix.',
                          style: primaryTextStyle(size: 15, color: kMisonDark.withValues(alpha: 0.85)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(
    BuildContext context, {
    required String label,
    required IconData icon,
    required PriceFirstAction action,
    bool filled = false,
  }) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: filled ? Colors.white : kMisonDark),
        8.width,
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: boldTextStyle(size: 16, color: filled ? Colors.white : kMisonDark)),
        ),
      ],
    );
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: filled
          ? ElevatedButton(
              onPressed: () => Navigator.pop(context, action),
              style: ElevatedButton.styleFrom(backgroundColor: kMisonGold, elevation: 0, shape: shape),
              child: content,
            )
          : OutlinedButton(
              onPressed: () => Navigator.pop(context, action),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.4)),
                shape: shape,
              ),
              child: content,
            ),
    );
  }
}
