import 'package:booking_system_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../component/loader_widget.dart';
import 'component/mison_category_component.dart';
import 'component/mison_new_request_dashboard_component.dart';
import 'component/mison_service_list_component.dart';
import 'component/mison_slider_dashboard_component.dart';

class DashboardFragment1 extends StatefulWidget {
  @override
  _DashboardFragment1State createState() => _DashboardFragment1State();
}

class _DashboardFragment1State extends State<DashboardFragment1> {
  final GlobalKey<MisonCategoryComponentState> _categoryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    setStatusBarColorChange();
  }

  Future<void> setStatusBarColorChange() async {
    setStatusBarColor(
      statusBarIconBrightness: appStore.isDarkMode
          ? Brightness.light
          : await isNetworkAvailable()
              ? Brightness.light
              : Brightness.dark,
      transparentColor,
      delayInMilliSeconds: 800,
    );
  }

  void _onRefresh() {
    setState(() {});
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AnimatedScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            listAnimationType: ListAnimationType.FadeIn,
            fadeInConfiguration: FadeInConfiguration(duration: 2.seconds),
            onSwipeRefresh: () async {
              setState(() {});
              return await 2.seconds.delay;
            },
            children: [
              // Slider avec images des services Mison et barre de recherche/localisation
              MisonSliderDashboardComponent(
                callback: _onRefresh,
              ),
              16.height,
              // Bouton "Nouvelle Demande" - déplacé vers l'écran des réservations
              // const MisonNewRequestDashboardComponent(),
              // 16.height,
              // Catégories commentées - les services sont maintenant accessibles via "Voir tout"
              // MisonCategoryComponent(key: _categoryKey),
              // Liste des services avec détails (image, description, prix)
              const MisonServiceListComponent(),
              32.height,
            ],
          ),
          Observer(builder: (context) => LoaderWidget().visible(appStore.isLoading)),
        ],
      ),
    );
  }
}