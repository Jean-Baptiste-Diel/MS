import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

const Color _startGreen = Color(0xFF2E7D32);

/// Panneau « Commencer la prestation » (même style que le panneau
/// d'annulation) : un seul bouton, chargement pendant la requête. Il ne se ferme
/// pas (ni geste, ni appui à côté, ni bouton retour) : il disparaît seulement
/// quand le prestataire a appuyé sur « Oui, commencer » et que c'est enregistré. Retourne true si la prestation a démarré.
Future<bool> showMisonStartPrestationSheet(BuildContext context, {required String orderId}) async {
  final started = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true, // au-dessus de la barre de navigation du bas
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => PopScope(canPop: false, child: _StartPrestationSheet(orderId: orderId)),
  );
  return started ?? false;
}

class _StartPrestationSheet extends StatefulWidget {
  final String orderId;
  const _StartPrestationSheet({required this.orderId});

  @override
  State<_StartPrestationSheet> createState() => _StartPrestationSheetState();
}

class _StartPrestationSheetState extends State<_StartPrestationSheet> {
  bool _isLoading = false;

  Future<void> _confirm() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final res = await artisanStartOrder(widget.orderId);
      if (!mounted) return;
      Navigator.pop(context, true);
      TopToast.show(message: res.message ?? 'Prestation démarrée', type: TopToastType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            12.height, // pas de poignée : le panneau ne se ferme pas d'un geste
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _startGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: _startGreen, size: 36),
              ),
            ),
            16.height,
            Text('Commencer la prestation ?',
                textAlign: TextAlign.center, style: boldTextStyle(size: 20, color: kMisonDark)),
            8.height,
            Text('Vous êtes chez le client : lancez la prestation quand vous êtes prêt.',
                textAlign: TextAlign.center, style: secondaryTextStyle(size: 14)),
            24.height,

            // Oui, commencer (chargement pendant la requête)
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _startGreen,
                  disabledBackgroundColor: _startGreen.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text('Oui, commencer', style: boldTextStyle(color: Colors.white, size: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
