import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark;
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';

/// « 10 100 FCFA »
String _fcfa(num value) {
  final digits = value.toStringAsFixed(0);
  return '${digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} FCFA';
}

/// Accord sur le prix entre le client et le prestataire, avant le déplacement.
/// Chacun peut proposer un prix ou faire une contre-proposition ; l'autre
/// l'accepte ou la refuse. Le prix accepté est ferme et payé à la fin.
class MisonPriceAgreementCard extends StatefulWidget {
  final MisonOrder order;
  final bool isArtisan;

  /// Appelé après chaque action (proposition, acceptation, refus).
  final VoidCallback onChanged;

  const MisonPriceAgreementCard({
    Key? key,
    required this.order,
    required this.isArtisan,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<MisonPriceAgreementCard> createState() => _MisonPriceAgreementCardState();
}

class _MisonPriceAgreementCardState extends State<MisonPriceAgreementCard> {
  bool _busy = false;

  MisonOrder get order => widget.order;
  String get _me => widget.isArtisan ? 'artisan' : 'client';
  bool get _proposedByMe => order.priceProposal != null && order.priceProposedBy == _me;
  bool get _proposedByOther => order.priceProposal != null && order.priceProposedBy.isNotEmpty && !_proposedByMe;

  String get _otherName {
    final name = widget.isArtisan ? order.client?.fullName : order.artisan?.fullName;
    if (name != null && name.isNotEmpty) return name;
    return widget.isArtisan ? 'Le client' : 'Le prestataire';
  }

  Future<void> _run(Future<MisonActionResponse> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      TopToast.show(message: success, type: TopToastType.success);
      widget.onChanged();
    } catch (e) {
      TopToast.show(message: e.toString(), type: TopToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose({bool counter = false}) async {
    final price = await _askPrice(context, order: order, counter: counter);
    if (price == null) return;
    await _run(
      () => proposeOrderPrice(order.id!, price),
      'Proposition de ${_fcfa(price)} envoyée à ${_otherName.split(' ').first}.',
    );
  }

  Future<void> _accept() async {
    final price = order.priceProposal!;
    final ok = await showMisonConfirmSheet(
      context,
      title: 'Valider ${_fcfa(price)} ?',
      subtitle: widget.isArtisan
          ? 'Ce prix est ferme : c\'est celui que le client paiera à la fin de la prestation.'
          : "Ce prix est ferme : vous le paierez avec Wave, dans l'application MISON, à la fin de la prestation "
              '(+ ${_fcfa(order.serviceFee)} de frais de service). Ne payez jamais le prestataire en espèces. '
              'Le prestataire pourra alors se mettre en route.',
      icon: Icons.handshake_outlined,
      confirmLabel: 'Oui, je valide',
    );
    if (!ok) return;
    await _run(() => acceptOrderPrice(order.id!), 'Prix validé : ${_fcfa(price)}.');
  }

  Future<void> _decline() async {
    await _run(() => declineOrderPrice(order.id!), 'Prix refusé. Vous pouvez faire une nouvelle proposition.');
  }

  @override
  Widget build(BuildContext context) {
    if (order.isPriceAgreed) return _buildAgreed();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kMisonGold.withValues(alpha: 0.45), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.handshake_outlined, color: kMisonGold, size: 22),
            10.width,
            Expanded(child: Text('Prix de la prestation', style: boldTextStyle(size: 16, color: kMisonDark))),
          ]),
          8.height,
          Text(
            widget.isArtisan
                ? 'Mettez-vous d\'accord avec le client sur le prix avant de vous déplacer '
                    '(par message ou par appel). Il doit le valider.'
                : 'Avant que le prestataire se déplace, mettez-vous d\'accord sur le prix '
                    '(par message ou par appel). Vous le paierez à la fin de la prestation.',
            style: secondaryTextStyle(size: 13),
          ),
          if (!widget.isArtisan) ...[
            12.height,
            const MisonWavePaymentNotice(),
          ],
          14.height,
          if (_proposedByOther) ..._otherProposal()
          else if (_proposedByMe) ..._myProposal()
          else
            _button('Proposer un prix', Icons.edit_rounded, () => _propose(), filled: true),
        ],
      ),
    );
  }

  List<Widget> _otherProposal() {
    final price = order.priceProposal!;
    return [
      _priceLine('$_otherName propose', price),
      if (!widget.isArtisan)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Total à payer à la fin : ${_fcfa(price + order.serviceFee)} (frais de service inclus)',
            style: secondaryTextStyle(size: 12),
          ),
        ),
      14.height,
      _button('Accepter ce prix', Icons.check_rounded, _accept, filled: true),
      8.height,
      Row(children: [
        Expanded(child: _button('Contre-proposer', Icons.swap_horiz_rounded, () => _propose(counter: true))),
        8.width,
        Expanded(child: _button('Refuser', Icons.close_rounded, _decline, danger: true)),
      ]),
    ];
  }

  List<Widget> _myProposal() {
    return [
      _priceLine('Vous avez proposé', order.priceProposal!),
      6.height,
      Row(children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: kMisonGold),
        ),
        8.width,
        Expanded(
          child: Text('En attente de la réponse de ${_otherName.split(' ').first}', style: secondaryTextStyle(size: 13)),
        ),
      ]),
      14.height,
      _button('Modifier ma proposition', Icons.edit_rounded, () => _propose()),
    ];
  }

  Widget _buildAgreed() {
    final price = order.agreedPrice!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.verified_rounded, color: Colors.green, size: 26),
        12.width,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Prix convenu : ${_fcfa(price)}', style: boldTextStyle(size: 16, color: kMisonDark)),
            4.height,
            Text(
              widget.isArtisan
                  ? "Prix ferme, payé par le client avec Wave dans l'application MISON à la fin "
                      "de la prestation. N'acceptez pas de paiement en espèces."
                  : "Prix ferme, à payer avec Wave dans l'application MISON à la fin de la prestation "
                      '(${_fcfa(price + order.serviceFee)} avec les frais de service). '
                      'Ne payez jamais le prestataire en espèces.',
              style: secondaryTextStyle(size: 13),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _priceLine(String label, int price) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(label, style: primaryTextStyle(size: 14, color: kMisonDark))),
        Text(_fcfa(price), style: boldTextStyle(size: 20, color: kMisonDark)),
      ],
    );
  }

  Widget _button(String label, IconData icon, VoidCallback onTap, {bool filled = false, bool danger = false}) {
    final color = danger ? const Color(0xFFE53935) : kMisonGold;
    final child = _busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: filled ? Colors.white : color),
          )
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: filled ? Colors.white : color),
            6.width,
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: boldTextStyle(size: 14, color: filled ? Colors.white : color)),
            ),
          ]);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: filled
          ? ElevatedButton(
              onPressed: _busy ? null : onTap,
              style: ElevatedButton.styleFrom(backgroundColor: color, elevation: 0, shape: shape),
              child: child,
            )
          : OutlinedButton(
              onPressed: _busy ? null : onTap,
              style: OutlinedButton.styleFrom(side: BorderSide(color: color), shape: shape),
              child: child,
            ),
    );
  }
}

/// Saisie du prix proposé. Retourne le montant (FCFA) ou null si annulé.
Future<int?> _askPrice(BuildContext context, {required MisonOrder order, bool counter = false}) {
  final ctrl = TextEditingController(text: order.priceProposal?.toString() ?? '');
  final minPrice = num.tryParse(order.service?.minPrice ?? '')?.round();
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      void submit() {
        final value = int.tryParse(ctrl.text.replaceAll(RegExp(r'\D'), ''));
        if (value == null || value <= 0) {
          TopToast.show(message: 'Veuillez saisir un montant valide');
          return;
        }
        Navigator.pop(sheetContext, value);
      }

      return Container(
        decoration: BoxDecoration(
          color: sheetContext.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            20.height,
            Text(counter ? 'Votre contre-proposition' : 'Proposer un prix', style: boldTextStyle(size: 18)),
            6.height,
            Text(
              'Prix de la prestation, en FCFA. Une fois validé par les deux, il ne pourra plus changer.'
              '${minPrice != null && minPrice > 0 ? '\nPrix indicatif : à partir de ${_fcfa(minPrice)}.' : ''}',
              style: secondaryTextStyle(size: 13),
            ),
            16.height,
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              style: boldTextStyle(size: 18),
              decoration: InputDecoration(
                hintText: 'Montant',
                suffixText: 'FCFA',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.35)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kMisonGold, width: 1.5),
                ),
              ),
            ),
            20.height,
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMisonGold,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Envoyer la proposition', style: boldTextStyle(color: Colors.white, size: 15)),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Avis au client : la prestation se paie uniquement par Wave, dans l'app
/// MISON (jamais en espèces au prestataire).
class MisonWavePaymentNotice extends StatelessWidget {
  const MisonWavePaymentNotice({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1DC4FF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1DC4FF).withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF0A8FC4), size: 20),
          10.width,
          Expanded(
            child: Text.rich(
              TextSpan(
                style: secondaryTextStyle(size: 13, color: kMisonDark),
                children: const [
                  TextSpan(text: 'La prestation se paie '),
                  TextSpan(text: "uniquement par Wave, dans l'application MISON", style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: ", à la fin de l'intervention. Ne payez jamais le prestataire en espèces : "
                      "sans paiement dans l'app, Mison ne peut pas vous protéger en cas de litige."),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
