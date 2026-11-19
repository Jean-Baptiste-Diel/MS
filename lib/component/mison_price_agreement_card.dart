import 'package:booking_system_flutter/utils/feature_flags.dart';
import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark;
import 'package:booking_system_flutter/component/mison_audio_sheet.dart';
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
/// Le prestataire annonce son prix ; le client l'accepte ou le refuse (pas de
/// contre-proposition). Le prix accepté est ferme et payé à la fin.
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

  /// Ouvrier, pas encore sur place, aucun prix proposé : il passe par les
  /// boutons du bas de la page.
  bool get _artisanUsesBottomButtons =>
      widget.isArtisan && !order.hasArrived && order.priceProposal == null;
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

  /// Ouvrier : « Êtes-vous tombés d'accord sur le prix ? » — Oui : il entre
  /// le prix (envoyé au client pour validation) ; Non : il discute d'abord.
  Future<void> _askAgreed() async {
    final yes = await showMisonAudioSheet(
      context,
      icon: Icons.handshake_outlined,
      caption: 'Prix de la prestation',
      title: 'Êtes-vous tombés d\u2019accord sur le prix ?',
      subtitle: 'Avec ${_otherName.split(' ').first}, par message ou par appel.',
      continueLabel: 'Oui, j\u2019entre le prix',
      laterLabel: 'Non, pas encore',
      warning: 'Le client devra valider ce prix dans l\u2019application. '
          'Il ne pourra plus changer ensuite.',
    );
    if (!mounted) return;
    if (yes) {
      await _propose();
    } else {
      TopToast.show(message: 'Discutez du prix avec le client, puis revenez entrer le prix convenu.');
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
          : "Ce prix est ferme : vous le paierez avec ${FeatureFlags.paymentMethods}, dans l'application MISON, à la fin de la prestation "
              '(+ ${_fcfa(order.serviceFee)} de frais de service). Ne payez jamais le prestataire en espèces.',
      icon: Icons.handshake_outlined,
      confirmLabel: 'Oui, je valide',
    );
    if (!ok) return;
    await _run(() => acceptOrderPrice(order.id!), 'Prix validé : ${_fcfa(price)}.');
  }

  Future<void> _decline() async {
    await _run(
      () => declineOrderPrice(order.id!),
      widget.isArtisan
          ? 'Prix refusé. Vous pouvez faire une nouvelle proposition.'
          : 'Prix refusé. Le prestataire va vous faire une nouvelle proposition.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (order.isPriceAgreed) return _buildAgreed();
    // Sans texte ni bouton, la carte serait vide : les boutons du bas suffisent.
    if (_artisanUsesBottomButtons) return const SizedBox.shrink();

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
            // Client : « Prix proposé » tant qu'il n'a pas validé, puis
            // « Prix de la prestation » une fois le prix validé.
            Expanded(
              child: Text(
                !widget.isArtisan && _proposedByOther ? 'Prix proposé' : 'Prix de la prestation',
                style: boldTextStyle(size: 16, color: kMisonDark),
              ),
            ),
          ]),
          // Ouvrier avant d'être sur place : les boutons du bas de la page
          // (« Appeler », « Discuter », « Prix convenu ») remplacent ce bouton.
          if (!_artisanUsesBottomButtons) 14.height,
          if (_proposedByOther) ..._otherProposal()
          else if (_proposedByMe) ..._myProposal()
          else if (_artisanUsesBottomButtons) const SizedBox.shrink()
          else if (widget.isArtisan && !order.hasDiscussed) ...[
            // Un prix se propose après avoir discuté avec le client.
            Opacity(
              opacity: 0.45,
              child: IgnorePointer(
                child: _button('Êtes-vous d\u2019accord sur le prix ?', Icons.handshake_outlined, () {}, filled: true),
              ),
            ),
            8.height,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.forum_outlined, size: 16, color: kMisonGold),
                6.width,
                Expanded(
                  child: Text(
                    'Discutez d\'abord avec le client (message ou appel) pour vous mettre d\'accord sur le prix.',
                    style: secondaryTextStyle(size: 13),
                  ),
                ),
              ],
            ),
          ]
          else if (widget.isArtisan)
            _button('Êtes-vous d\u2019accord sur le prix ?', Icons.handshake_outlined, () => _askAgreed(), filled: true)
          else
            // Le client ne propose pas en premier : il attend le prix du prestataire.
            _waitingLine('En attente du prix de ${_otherName.split(' ').first}'),
        ],
      ),
    );
  }

  List<Widget> _otherProposal() {
    final price = order.priceProposal!;
    return [
      if (widget.isArtisan)
        _priceLine('$_otherName propose', price)
      else
        // Client : juste le prix proposé, sans les frais de service ni texte.
        // (le titre de la carte dit déjà « Prix proposé »).
        _clientPriceCard('', price),
      14.height,
      // Client : il valide ou refuse dans la page « Prix proposé » qui s'ouvre
      // d'elle-même (plus de boutons ici). Ouvrier : accepter / refuser.
      if (widget.isArtisan)
        Row(children: [
          Expanded(child: _button('Refuser', Icons.close_rounded, _decline, danger: true)),
          8.width,
          Expanded(child: _button('Accepter', Icons.check_rounded, _accept, filled: true)),
        ]),
      if (widget.isArtisan) ...[
        8.height,
        _button('Contre-proposer', Icons.swap_horiz_rounded, () => _propose(counter: true)),
      ],
    ];
  }

  List<Widget> _myProposal() {
    return [
      _priceLine('Vous avez proposé', order.priceProposal!),
      6.height,
      _waitingLine('En attente de la réponse de ${_otherName.split(' ').first}'),
      // Seul le prestataire propose un prix.
      if (widget.isArtisan) ...[
        14.height,
        _button('Modifier ma proposition', Icons.edit_rounded, () => _propose()),
      ],
    ];
  }

  Widget _waitingLine(String text) {
    return Row(children: [
      const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: kMisonGold),
      ),
      8.width,
      Expanded(child: Text(text, style: secondaryTextStyle(size: 13))),
    ]);
  }

  Widget _buildAgreed() {
    final price = order.agreedPrice!;
    if (!widget.isArtisan) return _buildClientToPay(price);
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
                  ? "Prix ferme, payé par le client avec ${FeatureFlags.paymentMethods} dans l'application MISON à la fin "
                      "de la prestation. N'acceptez pas de paiement en espèces."
                  : "Prix ferme, à payer avec ${FeatureFlags.paymentMethods} dans l'application MISON à la fin de la prestation "
                      '(${_fcfa(price + order.serviceFee)} avec les frais de service). '
                      'Ne payez jamais le prestataire en espèces.',
              style: secondaryTextStyle(size: 13),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Client : montant à payer dans l'app, en gros, pour qu'il ne paie pas
  /// l'ouvrier en espèces.
  /// Client : juste le prix convenu, sans les frais de service ni texte.
  Widget _buildClientToPay(int price) => _clientPriceCard('Prix de la prestation', price);

  Widget _clientPriceCard(String label, int price) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kMisonGold.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Text(label.toUpperCase(), style: boldTextStyle(size: 13, color: kMisonGold, letterSpacing: 0.3)),
            4.height,
          ],
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_fcfa(price), style: boldTextStyle(size: 30, color: kMisonDark)),
          ),
        ],
      ),
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

      // Même présentation que la page de paiement (fiche Google Play) :
      // logo, petit libellé en couleur, prix en grand, bouton, mention, avertissement.
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: sheetContext.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 14, 16, MediaQuery.of(sheetContext).padding.bottom + 20),
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
                      onPressed: () => Navigator.pop(sheetContext),
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
                      Text(counter ? 'VOTRE CONTRE-PROPOSITION' : 'PRIX CONVENU AVEC LE CLIENT',
                          style: boldTextStyle(size: 15, color: kMisonGold, letterSpacing: 0.3)),
                      6.height,
                      // Le prix, saisi en grand
                      TextField(
                        controller: ctrl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(),
                        style: primaryTextStyle(size: 36, color: kMisonDark, weight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: primaryTextStyle(size: 36, color: Colors.grey.shade400, weight: FontWeight.w600),
                          suffixText: 'FCFA',
                          suffixStyle: boldTextStyle(size: 18, color: kMisonDark.withValues(alpha: 0.6)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 6),
                          border: InputBorder.none,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.35)),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: kMisonGold, width: 1.5),
                          ),
                        ),
                      ),
                      22.height,
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kMisonGold,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text('Envoyer au client', style: boldTextStyle(color: Colors.white, size: 16)),
                        ),
                      ),
                      22.height,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.verified_user_outlined, color: kMisonGold, size: 24),
                          14.width,
                          Expanded(
                            child: Text(
                              'Le client doit valider ce prix dans l\u2019application. Une fois validé, il ne pourra plus changer.',
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
        ),
      );
    },
  );
}

/// Avis au client : la prestation se paie uniquement par Wave ou Orange Money, dans l'app
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
                children: [
                  const TextSpan(text: 'La prestation se paie '),
                  TextSpan(
                    text: "uniquement par ${FeatureFlags.paymentMethods}, dans l'application MISON",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ", à la fin de l'intervention. Ne payez jamais le prestataire en espèces : "
                      "sans paiement dans l'app, MISON ne peut pas vous protéger en cas de litige."),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Montant à payer dans l'app MISON, en gros, avec l'avertissement contre les
/// espèces (prix convenu, puis commande en attente de paiement).
class MisonPayInAppCard extends StatelessWidget {
  final int price;
  final int fee;
  final String title;
  /// Prestation terminée : le client paie maintenant.
  final bool awaitingPayment;

  const MisonPayInAppCard({
    Key? key,
    required this.price,
    required this.fee,
    this.title = 'Prix convenu avec votre ouvrier',
    this.awaitingPayment = false,
  }) : super(key: key);


  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kMisonGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kMisonGold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.verified_rounded, color: Colors.green, size: 20),
            6.width,
            Expanded(child: Text(title, style: boldTextStyle(size: 13, color: Colors.green))),
          ]),
          12.height,
          Text("À payer dans l'app MISON", style: boldTextStyle(size: 22, color: kMisonGold)),
          4.height,
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_fcfa(price + fee), style: boldTextStyle(size: 30, color: kMisonDark)),
          ),
          4.height,
          Text('Prestation ${_fcfa(price)} + frais de service ${_fcfa(fee)}', style: secondaryTextStyle(size: 13)),
          6.height,
          Text(
            awaitingPayment
                ? "Avec ${FeatureFlags.paymentMethods}, maintenant, avec le bouton « Payer la prestation »."
                : "Avec ${FeatureFlags.paymentMethods}, à la fin de la prestation.",
            style: primaryTextStyle(size: 14, color: kMisonDark),
          ),
          14.height,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.money_off_rounded, color: Color(0xFFE53935), size: 20),
                8.width,
                Expanded(
                  child: Text(
                    "Ne payez jamais l'ouvrier en espèces : sans paiement dans l'app, MISON ne peut pas "
                    'vous protéger en cas de litige.',
                    style: boldTextStyle(size: 13, color: const Color(0xFFB3261E)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

/// Ouvrier : saisit le prix convenu avec le client et l'envoie pour validation.
/// Utilisé hors de la carte du prix (page « Prix de la prestation » avant le
/// départ). Renvoie true si le prix a été envoyé.
Future<bool> proposeAgreedPrice(BuildContext context, MisonOrder order) async {
  final price = await _askPrice(context, order: order);
  if (price == null) return false;
  try {
    await proposeOrderPrice(order.id!, price);
    TopToast.show(message: 'Prix de ${_fcfa(price)} envoyé au client pour validation.', type: TopToastType.success);
    return true;
  } catch (e) {
    TopToast.show(message: e.toString(), type: TopToastType.error);
    return false;
  }
}
