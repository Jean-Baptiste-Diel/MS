import 'package:booking_system_flutter/component/unread_badge.dart';
import 'package:booking_system_flutter/services/chat_unread_store.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/image_border_component.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/screens/booking/mison_search_service_screen.dart';
import 'package:booking_system_flutter/screens/chat/chat_list_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/fragment/dashboard_fragment.dart';
import 'package:booking_system_flutter/screens/dashboard/fragment/mison_booking_fragment.dart';
import 'package:booking_system_flutter/screens/dashboard/fragment/profile_fragment.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../component/voice_search_component.dart';
import '../../utils/app_configuration.dart';
import 'artisan_dashboard_screen.dart';

class DashboardScreen extends StatefulWidget {
  final bool? redirectToBooking;

  DashboardScreen({this.redirectToBooking});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int currentIndex = 0;
  bool isInterNetConnect = true;

  @override
  void initState() {
    super.initState();
    ChatUnreadStore.start(); // pastilles « messages non lus »
    openColdStartAcceptedCall(); // iPhone : appel décroché app fermée
    if (widget.redirectToBooking.validate(value: false)) {
      currentIndex = 1;
    }

    afterBuildCreated(() async {
      // Thème clair forcé — l'app ne suit plus le thème système.
    });

    /// Handle Firebase Notification click
    LiveStream().on(LIVESTREAM_FIREBASE, (value) {
      if (value == 3) {
        currentIndex = 3;
        setState(() {});
      }
    });

    // Firebase.initializeApp().then((value) {
    //   //When the app is in the background and opened directly from the push notification.
    //   FirebaseMessaging.onMessageOpenedApp.listen((message) async {
    //     //Handle onClick Notification
    //     log("data 1 ==> ${message.data}");
    //     handleNotificationClick(message);
    //   });
    //
    //   FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
    //     //Handle onClick Notification
    //     if (message != null) {
    //       log("data 2 ==> ${message.data}");
    //       handleNotificationClick(message);
    //     }
    //   });
    // }).catchError(onError);

    init();
  }

  /*Future<void> checkAndShowCustomForceUpdateDialog(BuildContext context) async {
    final result = await PlayxVersionUpdate.checkVersion(
      options:  PlayxUpdateOptions(
        androidPackageName: PackageInfoData().packageName,
        iosBundleId:PackageInfoData().packageName ,
        minVersion: '11.14.4',
      ),
    );

    result.when(
      success: (info) {
        showNewUpdateDialog(context, currentAppVersionCode: 99);
      },
      error: (e) {
        log('Version check failed: ${e.message}');
      },
    );
  }*/

  void init() async {
    await 3.seconds.delay;
    if (getIntAsync(FORCE_UPDATE_USER_APP).getBoolInt()) {
      showForceUpdateDialog(context);
    } /* else if (getBoolAsync(AUTO_UPDATE, defaultValue:false)) {
      checkAndShowCustomForceUpdateDialog(context);
    }*/
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  @override
  void dispose() {
    super.dispose();
    LiveStream().dispose(LIVESTREAM_FIREBASE);
  }

  @override
  Widget build(BuildContext context) {
    if (appStore.userType == USER_TYPE_PROVIDER) {
      return const ArtisanDashboardScreen();
    }

    return DoublePressBackWidget(
      message: language.lblBackPressMsg,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DotGridBackground(
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 500),
            child: [
            // Accueil Mison (les 4 accueils alternatifs du modèle ont été retirés).
            DashboardFragment(),
            Observer(
                builder: (context) => appStore.isLoggedIn
                    ? const MisonBookingFragment()
                    : const SignInScreen(isFromDashboard: true)),
            const MisonSearchServiceScreen(showBackButton: false),
            if (appConfigurationStore.isEnableChat)
              Observer(
                  builder: (context) => appStore.isLoggedIn
                      ? ChatListScreen()
                      : const SignInScreen(isFromDashboard: true)),
            ProfileFragment(),
          ][currentIndex],
          ),
        ),
        bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: context.scaffoldBackgroundColor,
              indicatorColor: kMisonGold.withValues(alpha: 0.15),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? boldTextStyle(size: 12, color: kMisonGold) // onglet actif en doré
                    : primaryTextStyle(size: 12, color: Colors.grey),
              ),
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
            ),
            child: NavigationBar(
              selectedIndex: currentIndex,
              destinations: [
                NavigationDestination(
                  icon: ic_home.iconImage(color: appTextSecondaryColor),
                  selectedIcon: ic_home.iconImage(color: kMisonGold),
                  label: language.home,
                ),
                NavigationDestination(
                  icon: ic_ticket.iconImage(color: appTextSecondaryColor),
                  selectedIcon:
                      ic_ticket.iconImage(color: kMisonGold),
                  label: language.booking,
                ),
                NavigationDestination(
                  icon: ic_category.iconImage(color: appTextSecondaryColor),
                  selectedIcon:
                      ic_category.iconImage(color: kMisonGold),
                  label: 'Service',
                ),
                if (appConfigurationStore.isEnableChat)
                  NavigationDestination(
                    icon: UnreadBadge(
                      count: ChatUnreadStore.ordersTotal,
                      child: ic_chat.iconImage(color: appTextSecondaryColor),
                    ),
                    selectedIcon: UnreadBadge(
                      count: ChatUnreadStore.ordersTotal,
                      child: ic_chat.iconImage(color: kMisonGold),
                    ),
                    label: language.lblChat,
                  ),
                Observer(
                  builder: (context) {
                    return NavigationDestination(
                      icon: (appStore.isLoggedIn &&
                              appStore.userProfileImage.isNotEmpty)
                          ? IgnorePointer(
                              ignoring: true,
                              child: ImageBorder(
                                  src: appStore.userProfileImage, height: 26))
                          : ic_profile2.iconImage(color: appTextSecondaryColor),
                      selectedIcon: (appStore.isLoggedIn &&
                              appStore.userProfileImage.isNotEmpty)
                          ? IgnorePointer(
                              ignoring: true,
                              child: ImageBorder(
                                  src: appStore.userProfileImage, height: 26))
                          : ic_profile2.iconImage(color: kMisonGold),
                      label: language.profile,
                    );
                  },
                ),
              ],
              onDestinationSelected: (index) {
                currentIndex = index;
                setState(() {});
              },
            ),
          ),
        bottomSheet: Observer(builder: (context) {
          return VoiceSearchComponent().visible(appStore.isSpeechActivated);
        }),
      ),
    );
  }
}
