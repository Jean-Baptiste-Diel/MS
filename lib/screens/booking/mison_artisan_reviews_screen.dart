import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Avis laissés par les clients sur un prestataire (note, commentaire, date).
class MisonArtisanReviewsScreen extends StatefulWidget {
  final String artisanId;
  final String artisanName;

  const MisonArtisanReviewsScreen({Key? key, required this.artisanId, required this.artisanName}) : super(key: key);

  @override
  State<MisonArtisanReviewsScreen> createState() => _MisonArtisanReviewsScreenState();
}

class _MisonArtisanReviewsScreenState extends State<MisonArtisanReviewsScreen> {
  late Future<Map<String, dynamic>> _future;

  /// Avis signalés : masqués tout de suite.
  final Set<String> _reported = {};

  Future<void> _report(String orderId) async {
    // Visiteur sans compte : signaler demande d'être connecté.
    if (!appStore.isLoggedIn) {
      TopToast.show(message: 'Connectez-vous pour signaler un avis.');
      await SignInScreen(returnExpected: true).launch(context);
      if (!appStore.isLoggedIn || !mounted) return;
    }
    final reason = await showMisonReportSheet(
      context,
      title: 'Signaler cet avis',
      subtitle: "Pourquoi signalez-vous cet avis ? L'équipe Mison le vérifiera sous 24 h.",
    );
    if (reason == null) return;
    try {
      await reportArtisanReview(widget.artisanId, orderId, reason: reason);
      if (!mounted) return;
      setState(() => _reported.add(orderId));
      TopToast.show(
        message: "Merci, votre signalement a été envoyé à l'équipe Mison. Il sera traité sous 24 h.",
        type: TopToastType.success,
      );
    } catch (_) {
      TopToast.show(message: 'Signalement non envoyé, réessayez.', type: TopToastType.error);
    }
  }

  @override
  void initState() {
    super.initState();
    _future = getArtisanReviews(widget.artisanId);
  }

  static const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  Widget _stars(int rating, {double size = 16}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Icon(i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size, color: i < rating ? ratingBarColor : Colors.grey.shade300),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: MisonAppBar(
        title: 'Avis clients',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kMisonDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: DotGridBackground(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: kMisonGold));
            }
            if (snap.hasError) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Impossible de charger les avis', style: secondaryTextStyle(size: 15)),
                  12.height,
                  TextButton(
                    onPressed: () => setState(() => _future = getArtisanReviews(widget.artisanId)),
                    child: const Text('Réessayer', style: TextStyle(color: kMisonGold)),
                  ),
                ]),
              );
            }
            final data = snap.data ?? {};
            final reviews = (data['reviews'] as List?)
                    ?.whereType<Map>()
                    .where((r) => !_reported.contains(r['id']?.toString()))
                    .toList() ??
                [];
            final average = double.tryParse('${data['average_rating']}') ?? 0;
            final total = int.tryParse('${data['total_reviews']}') ?? reviews.length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                // ── Résumé ─────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: Row(children: [
                    Text(average.toStringAsFixed(1), style: boldTextStyle(size: 40, color: kMisonDark)),
                    16.width,
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.artisanName, style: boldTextStyle(size: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                        6.height,
                        _stars(average.round(), size: 20),
                        4.height,
                        Text('$total avis', style: secondaryTextStyle(size: 14)),
                      ]),
                    ),
                  ]),
                ),
                16.height,
                if (reviews.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text('Ce prestataire n\'a pas encore reçu d\'avis.',
                        textAlign: TextAlign.center, style: secondaryTextStyle(size: 15)),
                  )
                else
                  ...reviews.map((r) {
                    final comment = (r['comment'] ?? '').toString().trim();
                    final service = (r['service_name'] ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text((r['client_name'] ?? 'Client').toString(), style: boldTextStyle(size: 15)),
                          ),
                          Text(_date(r['rated_at']?.toString()), style: secondaryTextStyle(size: 13)),
                          4.width,
                          // Signaler un avis choquant ou injurieux.
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _report(r['id'].toString()),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.flag_outlined, size: 18, color: Colors.grey),
                            ),
                          ),
                        ]),
                        6.height,
                        _stars(int.tryParse('${r['rating']}') ?? 0),
                        if (service.isNotEmpty) ...[
                          4.height,
                          Text(service, style: secondaryTextStyle(size: 13, color: kMisonGold)),
                        ],
                        if (comment.isNotEmpty) ...[
                          8.height,
                          Text(comment, style: primaryTextStyle(size: 15)),
                        ],
                      ]),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}
