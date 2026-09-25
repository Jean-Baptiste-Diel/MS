import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

enum TopToastType { error, success, warning, info }

class TopToast {
  static OverlayEntry? _currentEntry;

  static void show({
    required String message,
    TopToastType type = TopToastType.info,
    Duration duration = const Duration(seconds: 5),
    IconData? icon,
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    final entry = OverlayEntry(
      builder: (_) => _TopToastWidget(
        message: message,
        type: type,
        icon: icon,
        duration: duration,
        onDismiss: () {
          _currentEntry?.remove();
          _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _TopToastWidget extends StatefulWidget {
  final String message;
  final TopToastType type;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
    this.icon,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6)),
    );

    _controller.forward();

    Future.delayed(widget.duration, _dismiss);
  }

  void _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _resolveColors(widget.type);
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if (d.primaryVelocity != null && d.primaryVelocity! < 0) _dismiss();
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    // Légèrement transparent
                    colors: [
                      colors.gradientStart.withValues(alpha: 0.85),
                      colors.gradientEnd.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.gradientStart.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: topPadding + 12,
                        bottom: 18,
                        left: 20,
                        right: 20,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.icon ?? colors.defaultIcon,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          16.width,
                          Expanded(
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                          8.width,
                          GestureDetector(
                            onTap: _dismiss,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _ToastColors _resolveColors(TopToastType type) {
    switch (type) {
      case TopToastType.error:
        return _ToastColors(
          gradientStart: const Color(0xFFE53E3E),
          gradientEnd: const Color(0xFFC53030),
          defaultIcon: Icons.lock_outline_rounded,
        );
      case TopToastType.success:
        return _ToastColors(
          gradientStart: const Color(0xFF38A169),
          gradientEnd: const Color(0xFF276749),
          defaultIcon: Icons.check_circle_outline_rounded,
        );
      case TopToastType.warning:
        return _ToastColors(
          gradientStart: const Color(0xFFDD6B20),
          gradientEnd: const Color(0xFFC05621),
          defaultIcon: Icons.warning_amber_rounded,
        );
      case TopToastType.info:
        return _ToastColors(
          // Couleur unie (pas de dégradé)
          gradientStart: const Color(0xFFC49716),
          gradientEnd: const Color(0xFFC49716),
          defaultIcon: Icons.info_outline_rounded,
        );
    }
  }
}

class _ToastColors {
  final Color gradientStart;
  final Color gradientEnd;
  final IconData defaultIcon;

  const _ToastColors({
    required this.gradientStart,
    required this.gradientEnd,
    required this.defaultIcon,
  });
}
