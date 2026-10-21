import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold;
import 'package:booking_system_flutter/utils/service_search.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Icône et couleur d'un service (carte des prestataires), d'après son nom.
class ServiceStyle {
  final IconData icon;
  final Color color;

  const ServiceStyle(this.icon, this.color);
}

// Ordre important : « Menuisier Aluminium » avant « Menuisier ».
const List<(String, ServiceStyle)> _styles = [
  ('alumin', ServiceStyle(Icons.window_rounded, Color(0xFF607D8B))),
  ('metal', ServiceStyle(Icons.hardware_rounded, Color(0xFF455A64))),
  ('bois', ServiceStyle(Icons.carpenter_rounded, Color(0xFF8D6E63))),
  ('menuis', ServiceStyle(Icons.carpenter_rounded, Color(0xFF8D6E63))),
  ('clim', ServiceStyle(Icons.ac_unit_rounded, Color(0xFF29B6F6))),
  ('froid', ServiceStyle(Icons.ac_unit_rounded, Color(0xFF29B6F6))),
  ('engin', ServiceStyle(Icons.agriculture_rounded, Color(0xFFF9A825))),
  ('carrel', ServiceStyle(Icons.grid_view_rounded, Color(0xFF26A69A))),
  ('peint', ServiceStyle(Icons.format_paint_rounded, Color(0xFFAB47BC))),
  ('electr', ServiceStyle(Icons.electrical_services_rounded, Color(0xFFFFB300))),
  ('coffr', ServiceStyle(Icons.view_in_ar_rounded, Color(0xFF6D4C41))),
  ('macon', ServiceStyle(Icons.foundation_rounded, Color(0xFFE64A19))),
  ('plomb', ServiceStyle(Icons.plumbing_rounded, Color(0xFF1E88E5))),
  ('ferrail', ServiceStyle(Icons.straighten_rounded, Color(0xFF78909C))),
  ('manoeuvre', ServiceStyle(Icons.engineering_rounded, Color(0xFFEF6C00))),
];

const ServiceStyle _defaultStyle = ServiceStyle(Icons.handyman_rounded, kMisonGold);

ServiceStyle serviceStyle(String? serviceName) {
  final name = normalizeSearch((serviceName ?? '').replaceAll('œ', 'oe').replaceAll('Œ', 'oe'));
  for (final (keyword, style) in _styles) {
    if (name.contains(keyword)) return style;
  }
  return _defaultStyle;
}

/// Épingle de lieu à la couleur du service, avec son icône dans la tête ;
/// grisée si le prestataire n'est pas disponible. La pointe touche la
/// position : ancre `Offset(0.5, 1)`. Carte « Notre réseau » et recherche.
Future<BitmapDescriptor> serviceMarkerIcon(ServiceStyle style, {bool available = true, bool big = false}) async {
  return BitmapDescriptor.bytes(
    await serviceMarkerPng(style, available: available),
    width: big ? 72 : 54,
    height: big ? 88 : 66,
  );
}

/// Image PNG de l'épingle (150 × 184 px).
Future<Uint8List> serviceMarkerPng(ServiceStyle style, {bool available = true}) async {
  const double w = 150, h = 184;
  const double r = 62; // rayon de la tête
  const head = Offset(w / 2, r + 8);
  final color = available ? style.color : Colors.grey.shade500;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));

  // Goutte d'un seul tenant : arc du cercle, puis les deux tangentes jusqu'à
  // la pointe (pas de jointure visible entre la tête et la pointe).
  const tip = Offset(w / 2, h - 12);
  final theta = math.acos(r / (tip.dy - head.dy)); // angle des tangentes
  final drop = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(head.dx + r * math.sin(theta), head.dy + r * math.cos(theta))
    ..arcTo(Rect.fromCircle(center: head, radius: r), math.pi / 2 - theta, -(2 * math.pi - 2 * theta), false)
    ..close();

  canvas.drawPath(
    drop.shift(const Offset(0, 3)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );
  canvas.drawPath(drop, Paint()..color = color);
  canvas.drawPath(
    drop,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawCircle(head, r - 16, Paint()..color = Colors.white);

  final painter = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(style.icon.codePoint),
      style: TextStyle(
        fontSize: r * 1.0,
        fontFamily: style.icon.fontFamily,
        package: style.icon.fontPackage,
        color: color,
      ),
    )
    ..layout();
  painter.paint(canvas, head - Offset(painter.width / 2, painter.height / 2));

  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
