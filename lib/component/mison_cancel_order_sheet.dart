import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

const Color _cancelRed = Color(0xFFE53935);

/// Motifs proposés au client pour annuler une commande.
const List<String> kCancelReasons = [
  'J\'ai changé d\'avis',
  'J\'ai trouvé une autre solution',
  'Le délai est trop long',
  'Autre',
];

/// Panneau d'annulation d'une commande (style Mison) : motif, confirmation,
/// chargement pendant la requête. Retourne true si la commande a été annulée.
Future<bool> showMisonCancelOrderSheet(BuildContext context, {required String orderId}) async {
  final cancelled = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CancelOrderSheet(orderId: orderId),
  );
  return cancelled ?? false;
}

class _CancelOrderSheet extends StatefulWidget {
  final String orderId;
  const _CancelOrderSheet({required this.orderId});

  @override
  State<_CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends State<_CancelOrderSheet> {
  String? _reason;
  final TextEditingController _otherCont = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _otherCont.dispose();
    super.dispose();
  }

  String? get _finalReason {
    if (_reason == null) return null;
    if (_reason == 'Autre') {
      final text = _otherCont.text.trim();
      return text.isNotEmpty ? text : 'Autre';
    }
    return _reason;
  }

  Future<void> _confirm() async {
    if (_isLoading) return; // un seul appui
    setState(() => _isLoading = true);
    try {
      await cancelMisonOrder(widget.orderId, reason: _finalReason);
      if (!mounted) return;
      Navigator.pop(context, true);
      TopToast.show(message: 'Commande annulée', type: TopToastType.success);
    } catch (e) {
      log('cancelMisonOrder error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      TopToast.show(
        message: 'Impossible d\'annuler cette commande pour le moment. Réessayez plus tard.',
        type: TopToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Le panneau remonte au-dessus du clavier (motif « Autre »)
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
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
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _cancelRed.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.event_busy_rounded, color: _cancelRed, size: 32),
                ),
              ),
              16.height,
              Text('Annuler la commande ?',
                  textAlign: TextAlign.center,
                  style: boldTextStyle(size: 20, color: kMisonDark)),
              8.height,
              Text('Dites-nous pourquoi (facultatif) :',
                  textAlign: TextAlign.center, style: secondaryTextStyle(size: 14)),
              16.height,

              // Motifs
              ...kCancelReasons.map((r) {
                final selected = _reason == r;
                return GestureDetector(
                  onTap: _isLoading ? null : () => setState(() => _reason = selected ? null : r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? kMisonGold.withValues(alpha: 0.10) : kMisonFieldBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? kMisonGold : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          size: 20,
                          color: selected ? kMisonGold : Colors.grey,
                        ),
                        12.width,
                        Expanded(child: Text(r, style: primaryTextStyle(size: 14))),
                      ],
                    ),
                  ),
                );
              }),
              if (_reason == 'Autre') ...[
                4.height,
                TextField(
                  controller: _otherCont,
                  enabled: !_isLoading,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Précisez le motif…',
                    hintStyle: secondaryTextStyle(size: 14),
                    filled: true,
                    fillColor: kMisonFieldBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kMisonGold, width: 1.5),
                    ),
                  ),
                ),
              ],
              20.height,

              // Oui, annuler (chargement pendant la requête)
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cancelRed,
                    disabledBackgroundColor: _cancelRed.withValues(alpha: 0.6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text('Oui, annuler', style: boldTextStyle(color: Colors.white, size: 15)),
                ),
              ),
              10.height,
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kMisonDark),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Non, garder la commande',
                      style: boldTextStyle(color: kMisonDark, size: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
