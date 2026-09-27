import 'dart:io';
import 'dart:typed_data';

import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ── Couleurs de la facture ────────────────────────────────────────────────
const _gold = PdfColor.fromInt(0xFFC99700);
const _goldBadge = PdfColor.fromInt(0xFFF0B429);
const _cream = PdfColor.fromInt(0xFFFFF8EC);
const _creamIcon = PdfColor.fromInt(0xFFFDEBC8);
const _ink = PdfColor.fromInt(0xFF1B1F2A);
const _grey = PdfColor.fromInt(0xFF5F6673);
const _line = PdfColor.fromInt(0xFFE3E3E3);
const _tableHead = PdfColor.fromInt(0xFFF1F2F4);
const _green = PdfColor.fromInt(0xFF1E8E3E);
const _greenBg = PdfColor.fromInt(0xFFE3F5E6);
const _pageBg = PdfColor.fromInt(0xFFF3F3F3);

// Icônes Material (24 × 24) dessinées en SVG : les polices PDF n'ont pas d'icônes.
const _icPerson =
    'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z';
// Ouvrier : casque de chantier, visage et épaules.
const _icWorker =
    'M12 1.5a6.5 6.5 0 0 0-6.5 6.5v1h13V8A6.5 6.5 0 0 0 12 1.5zM11 2.6V6.5h2V2.6zM4 9.8h16v1.7H4zM7.8 12.5a4.2 4.2 0 0 0 8.4 0zM4.5 23c0-3.3 3.4-5.2 7.5-5.2s7.5 1.9 7.5 5.2z';
const _icPin =
    'M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z';
const _icWrench =
    'M22.7 19l-9.1-9.1c.9-2.3.4-5-1.5-6.9-2-2-5-2.4-7.4-1.3L9 6 6 9 1.6 4.7C.4 7.1.9 10.1 2.9 12.1c1.9 1.9 4.6 2.4 6.9 1.5l9.1 9.1c.4.4 1 .4 1.4 0l2.3-2.3c.5-.4.5-1.1.1-1.4z';
const _icCheck = 'M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z';

String _hex(PdfColor c) {
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c.red)}${h(c.green)}${h(c.blue)}';
}

pw.Widget _icon(String path, PdfColor color, double size) => pw.SvgImage(
      svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
          '<path fill="${_hex(color)}" d="$path"/></svg>',
      width: size,
      height: size,
    );

/// Numéro de facture lisible et stable, dérivé de la commande : FA-2026-3F9A2C1B.
String invoiceNumber(MisonOrder order) {
  final year = (DateTime.tryParse(order.updatedAt ?? '') ?? DateTime.now()).year;
  final ref = (order.id ?? '').replaceAll('-', '').toUpperCase().padRight(8, '0').substring(0, 8);
  return 'FA-$year-$ref';
}

/// « 10 100 FCFA »
String _fcfa(num value) {
  final digits = value.abs().toStringAsFixed(0);
  final grouped = digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return '${value < 0 ? '- ' : ''}$grouped FCFA';
}

const _months = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

/// « 27 sept. 2026 » (sans dépendre de l'initialisation des locales intl).
String _date(String? iso) {
  final d = (DateTime.tryParse(iso ?? '') ?? DateTime.now()).toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// Adresse courte : « Pikine, Dakar » à partir d'une adresse complète.
String? _shortAddress(String? address) {
  final parts = <String>[];
  for (final p in (address ?? '').split(',')) {
    final t = p.trim();
    if (t.isNotEmpty && !parts.any((e) => e.toLowerCase() == t.toLowerCase())) parts.add(t);
  }
  if (parts.isEmpty) return null;
  return parts.length <= 2 ? parts.join(', ') : parts.sublist(parts.length - 2).join(', ');
}

String _name(String? first, String? last) {
  final n = [first, last].where((e) => (e ?? '').trim().isNotEmpty).join(' ').trim();
  return n.isEmpty ? '-' : n;
}

/// Bord inférieur en dents de scie, comme un ticket de caisse.
pw.Widget _zigZag(double width) => pw.CustomPaint(
      size: PdfPoint(width, 9),
      painter: (canvas, size) {
        const tooth = 14.0;
        canvas.setFillColor(PdfColors.white);
        // Base des dents collée à la carte (y = 0 ici), pointes vers le bas.
        canvas.moveTo(0, 0);
        var x = 0.0;
        while (x < size.x) {
          canvas.lineTo(x + tooth / 2, size.y);
          canvas.lineTo(x + tooth, 0);
          x += tooth;
        }
        canvas.lineTo(size.x, 0);
        canvas.closePath();
        canvas.fillPath();
      },
    );

/// Construit la facture PDF d'une commande terminée.
/// Même facture pour le client et le prestataire : main d'œuvre + frais de service.
Future<Uint8List> buildOrderInvoicePdf(MisonOrder order) async {
  Future<pw.Font> font(String weight) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/invoice/NotoSans-$weight.ttf'));
  final regular = await font('Regular');
  final semi = await font('SemiBold');
  final bold = await font('Bold');
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/logo/logo_transparent.png')).buffer.asUint8List(),
  );

  final price = order.prestationPrice ?? 0;
  final serviceFee = order.serviceFee;
  final total = price + serviceFee;

  pw.TextStyle st(pw.Font f, double size, [PdfColor color = _ink]) =>
      pw.TextStyle(font: f, fontSize: size, color: color);

  const cardWidth = 400.0;

  pw.Widget dashed() => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _line, width: 1, style: pw.BorderStyle.dashed)),
        ),
      );

  pw.Widget roundIcon(String path, {required PdfColor bg, required PdfColor fg, double size = 44}) =>
      pw.Container(
        width: size,
        height: size,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(color: bg, shape: pw.BoxShape.circle),
        child: _icon(path, fg, size * 0.52),
      );

  pw.Widget separator() =>
      pw.Container(height: 1, color: _line, margin: const pw.EdgeInsets.symmetric(vertical: 7));

  pw.Widget party(String label, String name, String? place, String iconPath) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: _cream, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Row(children: [
          roundIcon(iconPath, bg: _creamIcon, fg: _gold),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(label, style: st(regular, 10, _grey)),
              pw.SizedBox(height: 1),
              pw.Text(name, style: st(bold, 13)),
              if (place != null) ...[
                pw.SizedBox(height: 3),
                pw.Row(children: [
                  _icon(_icPin, _grey, 11),
                  pw.SizedBox(width: 5),
                  pw.Expanded(child: pw.Text(place, style: st(regular, 10, _grey))),
                ]),
              ],
            ]),
          ),
        ]),
      );

  pw.Widget cell(String text, {pw.Font? f, PdfColor color = _ink, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: pw.Text(text, textAlign: align, style: st(f ?? regular, 10, color)),
      );

  pw.TableRow row(String label, num unit) => pw.TableRow(
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line))),
        children: [
          cell(label),
          cell('1', align: pw.TextAlign.center),
          cell(_fcfa(unit), align: pw.TextAlign.center),
          cell(_fcfa(unit), align: pw.TextAlign.right),
        ],
      );

  final card = pw.Container(
    width: cardWidth,
    color: PdfColors.white,
    padding: const pw.EdgeInsets.fromLTRB(22, 22, 22, 18),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      // ── Logo centré + slogan ─────────────────────────────────────────────
      pw.Center(child: pw.Image(logo, height: 72)),
      pw.SizedBox(height: 6),
      pw.Center(child: pw.Text('Ensemble, bâtissons mieux.', style: st(regular, 11, _grey))),
      dashed(),

      // ── FACTURE · numéro · date · Payée ────────────────────────────────────
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('FACTURE', style: st(bold, 24)),
            pw.Text('N° ${invoiceNumber(order)}', style: st(regular, 10.5, _grey)),
            pw.Text(_date(order.updatedAt), style: st(regular, 10.5, _grey)),
          ]),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(8, 6, 12, 6),
          decoration: pw.BoxDecoration(color: _greenBg, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
            roundIcon(_icCheck, bg: _green, fg: PdfColors.white, size: 18),
            pw.SizedBox(width: 7),
            pw.Text('Payée', style: st(bold, 12, _green)),
          ]),
        ),
      ]),
      pw.SizedBox(height: 14),

      // ── Parties ────────────────────────────────────────────────────────────
      party('Client', _name(order.client?.firstName, order.client?.lastName),
          _shortAddress(order.serviceAddress), _icPerson),
      separator(),
      party('Prestataire', _name(order.artisan?.firstName, order.artisan?.lastName),
          _shortAddress(order.artisan?.address), _icWorker),
      separator(),

      // ── Service ────────────────────────────────────────────────────────────
      pw.Row(children: [
        roundIcon(_icWrench, bg: _gold, fg: PdfColors.white, size: 46),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Service', style: st(regular, 10, _grey)),
            pw.Text(order.service?.name ?? '-', style: st(bold, 13.5)),
            pw.Text("Main d'œuvre", style: st(regular, 10, _grey)),
          ]),
        ),
      ]),
      pw.SizedBox(height: 14),

      // ── Détail ─────────────────────────────────────────────────────────────
      pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(2.3),
          1: pw.FlexColumnWidth(0.6),
          2: pw.FlexColumnWidth(1.7),
          3: pw.FlexColumnWidth(1.7),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _tableHead, borderRadius: pw.BorderRadius.circular(6)),
            children: [
              cell('Désignation', f: semi, color: _grey),
              cell('Qté', f: semi, color: _grey, align: pw.TextAlign.center),
              cell('Prix unitaire', f: semi, color: _grey, align: pw.TextAlign.center),
              cell('Montant', f: semi, color: _grey, align: pw.TextAlign.right),
            ],
          ),
          row("Main d'œuvre", price),
          row('Frais de service', serviceFee),
        ],
      ),
      pw.SizedBox(height: 12),

      // ── Total ──────────────────────────────────────────────────────────────
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(14, 7, 7, 7),
        decoration: pw.BoxDecoration(color: _cream, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text('Total TTC', style: st(bold, 17))),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: pw.BoxDecoration(color: _goldBadge, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Text(_fcfa(total), style: st(bold, 17)),
          ),
        ]),
      ),
      dashed(),
      pw.Center(child: pw.Text('Merci de votre confiance.', style: st(bold, 11))),
    ]),
  );

  final doc = pw.Document(title: 'Facture ${invoiceNumber(order)}', author: 'Mison');
  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(vertical: 30),
        buildBackground: (_) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: _pageBg)),
      ),
      build: (_) => pw.Align(
        alignment: pw.Alignment.topCenter,
        child: pw.Column(children: [card, _zigZag(cardWidth)]),
      ),
    ),
  );
  return doc.save();
}

const _filesChannel = MethodChannel('mison/files');

/// Génère la facture et l'enregistre sur le téléphone :
/// - Android : dossier Téléchargements ;
/// - iOS : app Fichiers, « Sur mon iPhone > Mison ».
/// Retourne l'emplacement, à afficher à l'utilisateur.
Future<String> downloadOrderInvoice(MisonOrder order) async {
  final bytes = await buildOrderInvoicePdf(order);
  final name = 'Facture_${invoiceNumber(order)}.pdf';

  if (Platform.isAndroid) {
    await _filesChannel.invokeMethod<String>('saveToDownloads', {
      'name': name,
      'bytes': bytes,
      'mime': 'application/pdf',
    });
    return 'Téléchargements';
  }

  final dir = await getApplicationDocumentsDirectory();
  await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
  return 'Fichiers › Sur mon iPhone › Mison';
}
