import 'package:booking_system_flutter/utils/image_cache_key.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Photo du chat en plein écran, comme WhatsApp : fond noir, zoom à deux
/// doigts (double appui pour zoomer / dézoomer), glisser vers le bas ou la
/// croix pour fermer.
class ChatImageViewer extends StatefulWidget {
  final String? url;
  final Uint8List? bytes;
  final String heroTag;

  const ChatImageViewer({super.key, this.url, this.bytes, required this.heroTag});

  static void open(BuildContext context, {String? url, Uint8List? bytes, required String heroTag}) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => ChatImageViewer(url: url, bytes: bytes, heroTag: heroTag),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  State<ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<ChatImageViewer> {
  final _transform = TransformationController();
  TapDownDetails? _doubleTap;
  double _dragDy = 0;

  bool get _zoomed => _transform.value.getMaxScaleOnAxis() > 1.01;

  void _toggleZoom() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
    } else {
      final p = _doubleTap?.localPosition ?? Offset.zero;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.bytes != null
        ? Image.memory(widget.bytes!, fit: BoxFit.contain)
        : CachedNetworkImage(
            imageUrl: widget.url ?? '',
            cacheKey: imageCacheKey(widget.url),
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 48),
          );

    final opacity = (1 - _dragDy.abs() / 400).clamp(0.3, 1.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: opacity),
        body: Stack(
          children: [
            GestureDetector(
              onDoubleTapDown: (d) => _doubleTap = d,
              onDoubleTap: _toggleZoom,
              // Glisser vers le bas (sans zoom) : ferme, comme WhatsApp.
              onVerticalDragUpdate: _zoomed ? null : (d) => setState(() => _dragDy += d.delta.dy),
              onVerticalDragEnd: _zoomed
                  ? null
                  : (_) {
                      if (_dragDy.abs() > 120) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _dragDy = 0);
                      }
                    },
              child: Transform.translate(
                offset: Offset(0, _dragDy),
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 5,
                  child: SizedBox.expand(
                    child: Hero(tag: widget.heroTag, child: image),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
