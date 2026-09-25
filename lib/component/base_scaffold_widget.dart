import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:nb_utils/nb_utils.dart';
import '../utils/constant.dart';

class AppScaffold extends StatelessWidget {
  final String? appBarTitle;
  final List<Widget>? actions;
  final Widget child;
  final Color? scaffoldBackgroundColor;
  final Widget? bottomNavigationBar;
  final Observable<bool>? isLoading;
  final bool showLoader;

  /// En-tête Mison : logo centré sur le fond gris clair, titre dessous,
  /// flèche retour gris foncé ; loader aux couleurs Mison.
  final bool useMisonHeader;

  AppScaffold({
    this.appBarTitle,
    required this.child,
    this.actions,
    this.scaffoldBackgroundColor,
    this.bottomNavigationBar,
    this.showLoader = true,
    this.isLoading,
    this.useMisonHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: useMisonHeader
          ? MisonAppBar(
              title: appBarTitle,
              leading: context.canPop
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, color: kMisonDark),
                      onPressed: () => Navigator.pop(context),
                    )
                  : null,
              actions: actions,
            )
          : appBarTitle != null
          ? AppBar(
              title: Text(
                appBarTitle.validate(),
                style: boldTextStyle(color: Colors.white, size: APP_BAR_TEXT_SIZE),
              ),
              elevation: 0.0,
              backgroundColor: context.primaryColor,
              leading: context.canPop ? BackWidget() : null,
              actions: actions,
            )
          : null,
      backgroundColor: scaffoldBackgroundColor ?? Colors.transparent,
      body: DotGridBackground(
        child: Observer(
          builder: (_) {
            final loading = showLoader && (isLoading?.value ?? false);
            return Stack(
              children: [
                AbsorbPointer(
                  absorbing: loading,
                  child: child,
                ),
                if (loading)
                  (useMisonHeader
                          ? LoaderWidget(colors: const [kMisonDark, kMisonGold])
                          : LoaderWidget())
                      .center(),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}