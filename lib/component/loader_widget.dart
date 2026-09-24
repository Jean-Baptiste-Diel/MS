import 'package:booking_system_flutter/component/spin_kit_chasing_dots.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';

class LoaderWidget extends StatefulWidget {
  /// Couleurs des cercles, en alternance. Par défaut : primaryColor.
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
    final colors = widget.colors;
    if (colors == null || colors.isEmpty) {
      return SpinKitChasingDots(color: primaryColor);
    }
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
