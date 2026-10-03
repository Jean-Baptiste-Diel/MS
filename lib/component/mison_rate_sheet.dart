import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Panneau « Noter le prestataire » (même style que le panneau d'annulation) :
/// étoiles vides au départ, commentaire facultatif, envoi avec chargement.
/// Retourne true si l'avis a été envoyé.
Future<bool> showMisonRateSheet(BuildContext context, {required String orderId, String? artisanName}) async {
  final rated = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true, // au-dessus de la barre de navigation du bas
    backgroundColor: Colors.transparent,
    builder: (_) => _RateSheet(orderId: orderId, artisanName: artisanName),
  );
  return rated ?? false;
}

class _RateSheet extends StatefulWidget {
  final String orderId;
  final String? artisanName;
  const _RateSheet({required this.orderId, this.artisanName});

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  int _rating = 0; // étoiles vides au départ
  final TextEditingController _comment = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  static const _labels = ['', 'Très décevant', 'Décevant', 'Correct', 'Bien', 'Excellent !'];

  Future<void> _submit() async {
    if (_isLoading || _rating == 0) return;
    setState(() => _isLoading = true);
    try {
      await rateMisonOrder(widget.orderId, _rating, _comment.text.trim());
      if (!mounted) return;
      Navigator.pop(context, true);
      TopToast.show(message: 'Merci pour votre avis !', type: TopToastType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.artisanName ?? '').trim();
    return Padding(
      // Le panneau remonte au-dessus du clavier (commentaire)
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
                  decoration: BoxDecoration(color: kMisonGold.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.star_rounded, color: kMisonGold, size: 34),
                ),
              ),
              16.height,
              Text('Prestation terminée !',
                  textAlign: TextAlign.center, style: boldTextStyle(size: 20, color: kMisonDark)),
              8.height,
              Text(
                name.isEmpty ? 'Comment s\'est passée la prestation ?' : 'Comment s\'est passée la prestation avec $name ?',
                textAlign: TextAlign.center,
                style: secondaryTextStyle(size: 14),
              ),
              18.height,

              // Étoiles : vides au départ, un appui remplit jusqu'à celle touchée.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return GestureDetector(
                    onTap: _isLoading ? null : () => setState(() => _rating = i + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 150),
                        scale: filled ? 1.1 : 1,
                        child: Icon(
                          filled ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: filled ? kMisonGold : Colors.grey.shade400,
                          size: 44,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              8.height,
              SizedBox(
                height: 20,
                child: Text(
                  _rating == 0 ? 'Touchez une étoile pour noter' : _labels[_rating],
                  textAlign: TextAlign.center,
                  style: _rating == 0
                      ? secondaryTextStyle(size: 13)
                      : boldTextStyle(size: 14, color: kMisonGold),
                ),
              ),
              16.height,

              TextField(
                controller: _comment,
                enabled: !_isLoading,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Un commentaire ? (facultatif)',
                  hintStyle: secondaryTextStyle(size: 14),
                  filled: true,
                  fillColor: kMisonFieldBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kMisonGold, width: 1.5),
                  ),
                ),
              ),
              20.height,

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading || _rating == 0 ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kMisonGold,
                    disabledBackgroundColor: kMisonGold.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text('Envoyer mon avis', style: boldTextStyle(color: Colors.white, size: 15)),
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
                  child: Text('Plus tard', style: boldTextStyle(color: kMisonDark, size: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
