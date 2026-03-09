import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/screens/newDashboard/dashboard_1/component/mison_category_component.dart';
import 'package:booking_system_flutter/screens/newDashboard/dashboard_1/component/mison_service_list_component.dart';
import 'package:booking_system_flutter/screens/newDashboard/dashboard_1/component/mison_slider_dashboard_component.dart';
import 'package:booking_system_flutter/screens/newDashboard/dashboard_1/component/mison_new_request_dashboard_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../component/loader_widget.dart';

class DashboardFragment extends StatefulWidget {
  @override
  _DashboardFragmentState createState() => _DashboardFragmentState();
}

class _DashboardFragmentState extends State<DashboardFragment> {
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
              MisonSliderDashboardComponent(callback: _onRefresh),
              16.height,
            
              // Catégories (services Mison affichés comme catégories)
        /*    //   const MisonCategoryComponent(), */
              // Liste des services avec détails (image, description, prix)
              const MisonServiceListComponent(),
              32.height,
                // Bouton "Nouvelle Demande"
            /*   const MisonNewRequestDashboardComponent(),
              16.height, */
            ],
          ),
          Observer(
            builder: (context) {
              return appStore.isLoading ? LoaderWidget().center() : const SizedBox();
            },
          ),
        ],
      ),
    );
  }
}