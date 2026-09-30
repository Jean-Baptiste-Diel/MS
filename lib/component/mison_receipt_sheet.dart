import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:image/image.dart' as img;

import 'package:nb_utils/nb_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../model/mison_order_model.dart';
import '../utils/colors.dart';
import '../utils/order_invoice_pdf.dart';
import '../utils/top_toast.dart';

/// Télécharge et enregistre le reçu directement au format JPEG (.jpg) dans le téléphone.
Future<String> downloadOrderInvoiceJpeg(BuildContext context, MisonOrder order) async {
  appStore.setLoading(true);
  try {
    final pngBytes = await generateReceiptPngBytes(context, order);
    if (pngBytes == null || pngBytes.isEmpty) {
      throw 'Impossible de générer le reçu.';
    }

    final decoded = img.decodePng(pngBytes);
    if (decoded == null) throw 'Erreur de conversion de l\'image.';
    final jpegBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 95));

    final name = 'Recu_MISON_${invoiceNumber(order)}.jpg';

    if (Platform.isAndroid) {
      await const MethodChannel('mison/files').invokeMethod<String>('saveToDownloads', {
        'name': name,
        'bytes': jpegBytes,
        'mime': 'image/jpeg',
      });
      return 'Téléchargements';
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(jpegBytes, flush: true);
    return 'Fichiers › Sur mon iPhone › Mison';
  } finally {
    appStore.setLoading(false);
  }
}

/// Génère l'image du reçu Mison et ouvre DIRECTEMENT le menu système natif
/// (Share Sheet avec WhatsApp, Mail, Save Image, Save to Files, AirDrop, etc.).
Future<void> shareMisonReceiptDirectly(BuildContext context, MisonOrder order) async {
  appStore.setLoading(true);
  try {
    final pngBytes = await generateReceiptPngBytes(context, order);
    final tempDir = await getTemporaryDirectory();

    if (pngBytes != null && pngBytes.isNotEmpty) {
      final fileName = 'Receipt_De_Mison_${invoiceNumber(order)}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes, flush: true);

      appStore.setLoading(false);

      // Ouvre directement le menu Share Sheet natif (iOS / Android)
      await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: 'image/png',
            name: 'Reçu MISON',
          )
        ],
        subject: 'Reçu MISON',
      );
    } else {
      // Fallback au PDF si la génération PNG échoue
      final pdfBytes = await buildOrderInvoicePdf(order);
      final fileName = 'Facture_${invoiceNumber(order)}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes, flush: true);

      appStore.setLoading(false);

      await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: 'application/pdf',
            name: 'Facture MISON ${invoiceNumber(order)}',
          )
        ],
        subject: 'Reçu MISON',
      );
    }
  } catch (e) {
    appStore.setLoading(false);
    log('Error opening share sheet: $e');
    TopToast.show(
      message: 'Erreur lors de l\'ouverture du menu de partage.',
      type: TopToastType.error,
    );
  }
}

/// Rendu hors-écran de la carte de reçu en image PNG haute définition.
Future<Uint8List?> generateReceiptPngBytes(BuildContext context, MisonOrder order) async {
  final repaintKey = GlobalKey();
  final overlayState = Overlay.of(context);

  // Logo chargé AVANT la capture : sinon, au premier reçu ou sur un téléphone
  // lent, l'image est prise alors que le logo n'est pas encore décodé.
  await precacheImage(const AssetImage('assets/logo/logo_transparent.png'), context);

  final overlayEntry = OverlayEntry(
    builder: (_) => Positioned(
      left: -9999,
      top: -9999,
      child: Material(
        color: Colors.transparent,
        child: RepaintBoundary(
          key: repaintKey,
          child: Container(
            width: 420,
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: MisonReceiptCardWidget(order: order),
          ),
        ),
      ),
    ),
  );

  overlayState.insert(overlayEntry);
  // Attend que la carte soit réellement dessinée avant de la capturer.
  await WidgetsBinding.instance.endOfFrame;
  await Future.delayed(const Duration(milliseconds: 50));

  Uint8List? pngBytes;
  try {
    final boundary = repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      pngBytes = byteData?.buffer.asUint8List();
    }
  } catch (e) {
    log('Error capturing offscreen receipt png: $e');
  } finally {
    overlayEntry.remove();
  }
  return pngBytes;
}

/// Affiche la feuille modale d'aperçu du reçu (optionnel).
void showMisonReceiptSheet(BuildContext context, MisonOrder order) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MisonReceiptSheet(order: order),
  );
}

class MisonReceiptSheet extends StatefulWidget {
  final MisonOrder order;

  const MisonReceiptSheet({super.key, required this.order});

  @override
  State<MisonReceiptSheet> createState() => _MisonReceiptSheetState();
}

class _MisonReceiptSheetState extends State<MisonReceiptSheet> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _isExporting = false;

  Future<Uint8List?> _capturePngBytes() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      log('Error capturing receipt image: $e');
      return null;
    }
  }

  Future<void> _shareAsImage() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final bytes = await _capturePngBytes();
      if (bytes == null || bytes.isEmpty) {
        TopToast.show(
          message: 'Impossible de capturer le reçu sous forme d\'image.',
          type: TopToastType.error,
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'Receipt_De_Mison_${invoiceNumber(widget.order)}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: 'image/png',
            name: 'Reçu MISON',
          )
        ],
        subject: 'Reçu MISON',
      );
    } catch (e) {
      log('Error sharing receipt as image: $e');
      TopToast.show(
        message: 'Erreur lors du partage en image.',
        type: TopToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _shareAsPdf() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final pdfBytes = await buildOrderInvoicePdf(widget.order);
      final tempDir = await getTemporaryDirectory();
      final fileName = 'Facture_${invoiceNumber(widget.order)}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes, flush: true);

      await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: 'application/pdf',
            name: 'Facture MISON ${invoiceNumber(widget.order)}',
          )
        ],
        subject: 'Reçu MISON',
      );
    } catch (e) {
      log('Error sharing receipt as PDF: $e');
      TopToast.show(
        message: 'Erreur lors de la génération du PDF.',
        type: TopToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _downloadDirectly() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final where = await downloadOrderInvoice(widget.order);
      TopToast.show(
        message: 'Facture enregistrée dans $where',
        type: TopToastType.success,
      );
    } catch (e) {
      TopToast.show(
        message: 'Impossible de télécharger la facture.',
        type: TopToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: context.height() * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reçu MISON',
                        style: boldTextStyle(size: 17),
                      ),
                      4.height,
                      Text(
                        'Aperçu & options d\'enregistrement',
                        style: secondaryTextStyle(size: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => finish(context),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: _repaintKey,
                child: MisonReceiptCardWidget(order: widget.order),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: AppButton(
                    text: 'Enregistrer / Partager en Image',
                    textStyle: boldTextStyle(size: 15, color: Colors.black),
                    color: primaryColor,
                    shapeBorder: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: _isExporting ? null : _shareAsImage,
                  ),
                ),
                10.height,
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isExporting ? null : _shareAsPdf,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: Text('Partager PDF', style: boldTextStyle(size: 13)),
                      ),
                    ),
                    12.width,
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isExporting ? null : _downloadDirectly,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text('Sauvegarder', style: boldTextStyle(size: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte visuelle du reçu de paiement Mison.
class MisonReceiptCardWidget extends StatelessWidget {
  final MisonOrder order;

  // Couleurs fixes : le reçu est toujours sur fond blanc, même en mode sombre
  // (les styles du thème passeraient en blanc sur blanc).
  static const _ink = Color(0xFF1B1F2A);
  static const _muted = Color(0xFF5F6673);
  static const _gold = Color(0xFFC99700);

  const MisonReceiptCardWidget({super.key, required this.order});

  String _formatFcfa(num value) {
    final digits = value.abs().toStringAsFixed(0);
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ' ',
    );
    return '${value < 0 ? '- ' : ''}$grouped FCFA';
  }

  static const _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];

  String _formatDate(String? iso) {
    final d = (DateTime.tryParse(iso ?? '') ?? DateTime.now()).toLocal();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year} · $h:$m';
  }

  String _formatName(String? first, String? last) {
    final n = [first, last]
        .where((e) => (e ?? '').trim().isNotEmpty)
        .join(' ')
        .trim();
    return n.isEmpty ? '-' : n;
  }

  @override
  Widget build(BuildContext context) {
    final price = order.prestationPrice ?? 0;
    final serviceFee = order.serviceFee;
    final total = price + serviceFee;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo & En-tête Mison
            Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/logo/logo_transparent.png',
                    height: 50,
                    errorBuilder: (_, __, ___) => Text(
                      'MISON SERVICES',
                      style: boldTextStyle(size: 20, color: _gold),
                    ),
                  ),
                  6.height,
                  Text(
                    'Ensemble, bâtissons mieux.',
                    style: secondaryTextStyle(
                      size: 11,
                      color: _muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            16.height,

            _dashedLine(),
            16.height,

            // Titre & Numéro
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('REÇU DE PAIEMENT', style: boldTextStyle(size: 18, color: _ink)),
                      4.height,
                      Text('N° ${invoiceNumber(order)}', style: secondaryTextStyle(size: 12, color: _muted)),
                      Text(_formatDate(order.updatedAt), style: secondaryTextStyle(size: 12, color: _muted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F5E6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF1E8E3E),
                        size: 16,
                      ),
                      6.width,
                      Text(
                        'Payé',
                        style: boldTextStyle(
                          size: 12,
                          color: const Color(0xFF1E8E3E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            16.height,

            // Parties Client & Prestataire
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8EC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _partyRow(
                    label: 'Client',
                    name: _formatName(order.client?.firstName, order.client?.lastName),
                    address: order.serviceAddress,
                    icon: Icons.person_outline_rounded,
                  ),
                  const Divider(height: 16, color: Color(0xFFE6DCC6)),
                  _partyRow(
                    label: 'Prestataire',
                    name: _formatName(order.artisan?.firstName, order.artisan?.lastName),
                    address: order.artisan?.address,
                    icon: Icons.engineering_outlined,
                  ),
                ],
              ),
            ),
            16.height,

            // Service
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.construction_rounded, color: _gold, size: 22),
                ),
                12.width,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Service', style: secondaryTextStyle(size: 11, color: _muted)),
                      Text(order.service?.name ?? '-', style: boldTextStyle(size: 14, color: _ink)),
                    ],
                  ),
                ),
              ],
            ),
            16.height,

            // Tableau des montants
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _priceRow('Main d\'œuvre', _formatFcfa(price)),
                  const Divider(height: 1, color: Color(0xFFE3E3E3)),
                  _priceRow('Frais de service', _formatFcfa(serviceFee)),
                ],
              ),
            ),
            16.height,

            // Total TTC
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Payé', style: boldTextStyle(size: 16, color: Colors.black)),
                  Text(_formatFcfa(total), style: boldTextStyle(size: 18, color: Colors.black)),
                ],
              ),
            ),
            16.height,

            Center(
              child: Text(
                'Merci de votre confiance.',
                style: secondaryTextStyle(
                  size: 12,
                  color: _muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashedLine() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth;
        const dashWidth = 6.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.grey),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _partyRow({
    required String label,
    required String name,
    String? address,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade700),
        10.width,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: secondaryTextStyle(size: 11, color: _muted)),
              Text(name, style: boldTextStyle(size: 13, color: _ink)),
              if (address != null && address.trim().isNotEmpty)
                Text(
                  address,
                  style: secondaryTextStyle(size: 11, color: _muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _priceRow(String title, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: primaryTextStyle(size: 13, color: _ink)),
          Text(amount, style: boldTextStyle(size: 13, color: _ink)),
        ],
      ),
    );
  }
}
