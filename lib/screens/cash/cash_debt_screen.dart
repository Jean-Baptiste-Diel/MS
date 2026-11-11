import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark;
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart' show formatFcfa;
import 'package:booking_system_flutter/utils/feature_flags.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ouvrier qui doit à MISON (commandes payées en espèces, échéance passée) :
/// l'app reste sur cet écran tant qu'il n'a pas réglé. Il reçoit toujours les
/// notifications, mais ne peut pas accepter de commande.
class CashDebtScreen extends StatefulWidget {
  final CashBalance balance;
  /// Ouvert depuis le profil (« Dette MISON ») : payer avant d'être bloqué,
  /// et revenir en arrière librement.
  final bool fromProfile;
  const CashDebtScreen({super.key, required this.balance, this.fromProfile = false});

  /// Profil › Dette MISON.
  static Future<void> open(BuildContext context) async {
    try {
      final balance = await getCashBalance();
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CashDebtScreen(balance: balance, fromProfile: true),
      ));
    } catch (e) {
      TopToast.show(message: '$e', type: TopToastType.error);
    }
  }

  static bool _shown = false;

  /// Vérifie le solde ; bloqué → ouvre l'écran (une seule fois à la fois).
  static Future<void> checkAndShow(BuildContext context) async {
    if (_shown) return;
    try {
      final balance = await getCashBalance();
      if (!balance.blocked || !context.mounted) return;
      _shown = true;
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CashDebtScreen(balance: balance),
      ));
    } catch (_) {
      // Hors ligne : on revérifiera au prochain retour dans l'app.
    } finally {
      _shown = false;
    }
  }

  @override
  State<CashDebtScreen> createState() => _CashDebtScreenState();
}

class _CashDebtScreenState extends State<CashDebtScreen> with WidgetsBindingObserver {
  late CashBalance _balance = widget.balance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retour dans l'app après le paiement Wave : on vérifie.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(silent: true);
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final balance = await getCashBalance();
      if (!mounted) return;
      final settled = widget.fromProfile ? balance.owed == 0 && _balance.owed > 0 : !balance.blocked;
      if (settled) {
        TopToast.show(message: 'Merci, votre règlement est confirmé.', type: TopToastType.success);
        Navigator.of(context).pop();
        return;
      }
      setState(() => _balance = balance);
      if (!silent) TopToast.show(message: "Le paiement n'est pas encore confirmé. Réessayez dans un instant.");
    } catch (e) {
      if (!silent) TopToast.show(message: '$e', type: TopToastType.error);
    }
  }

  Future<void> _pay(String provider) async {
    setState(() => _busy = true);
    try {
      final url = await payCashBalance(provider: provider);
      if (url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      TopToast.show(message: '$e', type: TopToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _balance;
    final nothing = b.owed <= 0;
    return PopScope(
      canPop: widget.fromProfile,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: widget.fromProfile
            ? AppBar(backgroundColor: Colors.white, elevation: 0, foregroundColor: kMisonDark, title: const Text('Dette MISON'))
            : null,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              if (!widget.fromProfile) ...[
                Center(child: Image.asset('assets/logo/logo_transparent.png', height: 56)),
                24.height,
              ],
              Text(nothing ? 'Vous ne devez rien à MISON' : 'À régler à MISON',
                  style: boldTextStyle(size: 24, color: kMisonDark), textAlign: TextAlign.center),
              8.height,
              Text(
                nothing
                    ? "Quand un client vous paie en espèces, la part de MISON (frais de service, commission et "
                        "assurance) apparaît ici."
                    : widget.fromProfile && !b.blocked
                        ? "Des clients vous ont payé en espèces. Réglez la part de MISON (frais de service, commission "
                            "et assurance) avant ${b.deadlineHour} h pour ne pas être bloqué."
                        : "Des clients vous ont payé en espèces. Réglez la part de MISON (frais de service, commission et "
                            "assurance) pour continuer à accepter des commandes.",
                style: secondaryTextStyle(size: 14),
                textAlign: TextAlign.center,
              ),
              if (!nothing) ...[
              24.height,
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: kMisonGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kMisonGold, width: 1.5),
                ),
                child: Column(
                  children: [
                    Text('Montant à régler', style: secondaryTextStyle(size: 13)),
                    4.height,
                    Text(formatFcfa(b.owed), style: boldTextStyle(size: 34, color: kMisonDark)),
                    4.height,
                    Text(
                      '${b.debts.length} commande${b.debts.length > 1 ? 's' : ''} payée${b.debts.length > 1 ? 's' : ''} en espèces',
                      style: secondaryTextStyle(size: 13),
                    ),
                  ],
                ),
              ),
              16.height,
              for (final d in b.debts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${d.service} · #${d.reference} · ${DateFormat('d MMM', 'fr_FR').format(DateTime.tryParse(d.date)?.toLocal() ?? DateTime.now())}',
                          style: secondaryTextStyle(size: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(formatFcfa(d.amount), style: boldTextStyle(size: 13, color: kMisonDark)),
                    ],
                  ),
                ),
              24.height,
              // Moyens cochés dans Réglages de la plateforme (Wave par défaut).
              for (final method in FeatureFlags.paymentMethodList) ...[
                ElevatedButton.icon(
                  onPressed: _busy ? null : () => _pay(method == 'Orange Money' ? 'orange' : 'wave'),
                  icon: const Icon(Icons.payment_rounded),
                  label: Text(_busy ? 'Ouverture…' : 'Payer avec $method'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: method == 'Orange Money' ? const Color(0xFFFF7900) : const Color(0xFF1BA1F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: boldTextStyle(size: 16, color: Colors.white),
                  ),
                ),
                12.height,
              ],
              OutlinedButton(
                onPressed: () => _refresh(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text("J'ai payé : vérifier", style: boldTextStyle(color: kMisonDark)),
              ),
              16.height,
              Text(
                "Vous pouvez aussi régler au bureau MISON : l'équipe validera votre paiement.",
                style: secondaryTextStyle(size: 12),
                textAlign: TextAlign.center,
              ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
