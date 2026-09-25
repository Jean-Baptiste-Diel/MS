import 'package:booking_system_flutter/model/mison_notification_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/screens/newDashboard/dashboard_1/component/mison_artisan_list_component.dart';
import 'package:booking_system_flutter/screens/newDashboard/dashboard_1/component/mison_service_list_component.dart';
import 'package:booking_system_flutter/screens/newDashboard/dashboard_1/component/mison_slider_dashboard_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../component/loader_widget.dart';

class DashboardFragment extends StatefulWidget {
  @override
  _DashboardFragmentState createState() => _DashboardFragmentState();
}

class _DashboardFragmentState extends State<DashboardFragment> {
  final ScrollController _scrollController = ScrollController();
  bool _isCollapsed = false;

  @override
  void initState() {
    super.initState();
    setStatusBarColorChange();
    // Compteur de la cloche : notifications non lues (historique serveur)
    if (appStore.isLoggedIn) getMisonNotifications().catchError((_) => const MisonNotificationResponse(unreadCount: 0, data: []));
    _scrollController.addListener(() {
      final collapsed =
          _scrollController.hasClients && _scrollController.offset > 4;
      if (collapsed != _isCollapsed) setState(() => _isCollapsed = collapsed);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> setStatusBarColorChange() async {
    setStatusBarColor(
      statusBarIconBrightness:
          appStore.isDarkMode ? Brightness.light : Brightness.dark,
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

  static const double _toolbarHeight = 84;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          RefreshIndicator(
            color: kMisonGold,
            onRefresh: () async {
              setState(() {});
              await 2.seconds.delay;
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Barre fixe du logo : le contenu défile et passe dessous
                SliverAppBar(
                  pinned: true,
                  backgroundColor: kMisonHeaderBg,
                  surfaceTintColor: Colors.transparent,
                  // Pendant le défilement, la barre du logo garde son fond gris
                  // et une légère ombre la sépare du contenu
                  forceElevated: _isCollapsed,
                  elevation: _isCollapsed ? 3 : 0,
                  scrolledUnderElevation: _isCollapsed ? 3 : 0,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  systemOverlayStyle: SystemUiOverlayStyle.dark,
                  automaticallyImplyLeading: false,
                  toolbarHeight: _toolbarHeight,
                  centerTitle: true,
                  title: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Image.asset('assets/logo/logo_transparent.png', height: 58),
                  ),
                  actions: [
                    Observer(
                      builder: (_) => appStore.isLoggedIn
                          ? const Padding(
                              padding: EdgeInsets.only(right: 16, top: 12),
                              child: Center(child: MisonNotificationBell()),
                            )
                          : const SizedBox(),
                    ),
                  ],
                ),

                // Fond gris jusqu'à la barre de recherche ; ce bloc défile
                // et passe sous la barre du logo
                SliverToBoxAdapter(
                  child: Container(
                    color: kMisonHeaderBg,
                    child: MisonSliderDashboardComponent(callback: _onRefresh),
                  ),
                ),

                SliverList(
                  delegate: SliverChildListDelegate([
                    16.height,
                    // Liste des prestataires disponibles
                    const MisonArtisanListComponent(),

                    // Liste des services avec détails (image, description, prix)
                    const MisonServiceListComponent(),
                    32.height,
                  ]),
                ),
              ],
            ),
          ),
          Observer(
            builder: (context) {
              return appStore.isLoading
                  ? LoaderWidget(colors: const [kMisonDark, kMisonGold]).center()
                  : const SizedBox();
            },
          ),
        ],
      ),
    );
  }
}
