import 'package:booking_system_flutter/component/spin_kit_chasing_dots.dart';
import 'package:flutter/material.dart';

/// Gris foncé et doré MISON (kMisonDark, kMisonGold).
const List<Color> _misonColors = [Color(0xFF3A3A3A), Color(0xFFC49716)];

class LoaderWidget extends StatefulWidget {
  /// Couleurs des cercles, en alternance. Par défaut : celles de MISON
  /// (gris foncé et doré), le même chargement sur toutes les pages.
  final List<Color>? colors;

  const LoaderWidget({Key? key, this.colors}) : super(key: key);

  @override
  _LoaderWidgetState createState() => _LoaderWidgetState();
}

class _LoaderWidgetState extends State<LoaderWidget> with TickerProviderStateMixin {
  late AnimationController controller;

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    controller = AnimationController(vsync: this, duration: Duration(milliseconds: 1000))..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = (widget.colors == null || widget.colors!.isEmpty) ? _misonColors : widget.colors!;
    return SpinKitChasingDots(
      itemBuilder: (context, index) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors[index % colors.length],
        ),
      ),
    );
  }
}
