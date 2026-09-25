import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/screens/maintenance_mode_screen.dart';
import 'package:booking_system_flutter/screens/mison_welcome_screen.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nb_utils/nb_utils.dart';

import '../component/loader_widget.dart';
import '../network/rest_apis.dart';
import '../utils/firebase_messaging_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  bool appNotSynced = false;

  // ── Animation d'ouverture du logo ──────────────────────────────────────────
  static const Color _brandGold = Color(0xFFC49716);
  late final AnimationController _introController;
  late final Animation<double> _symbolScale;
  late final Animation<double> _symbolFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _lineWidth;
  late final Future<void> _introDone;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    // 1) le symbole « M » grossit et apparaît
    _symbolScale = Tween<double>(begin: 0.5, end: 1).animate(CurvedAnimation(
        parent: _introController, curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack)));
    _symbolFade = CurvedAnimation(parent: _introController, curve: const Interval(0.0, 0.3, curve: Curves.easeIn));
    // 2) « MISON » monte en fondu
    _textFade = CurvedAnimation(parent: _introController, curve: const Interval(0.35, 0.7, curve: Curves.easeOut));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(CurvedAnimation(
        parent: _introController, curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic)));
    // 3) un trait doré se dessine sous le nom
    _lineWidth = CurvedAnimation(parent: _introController, curve: const Interval(0.65, 1.0, curve: Curves.easeInOut));
    _introDone = _introController.forward().orCancel.catchError((_) {});

    afterBuildCreated(() {
      setStatusBarColor(Colors.transparent, statusBarBrightness: Brightness.dark, statusBarIconBrightness: appStore.isDarkMode ? Brightness.light : Brightness.dark);
      init();
    });
  }

  Future<void> _fetchAndStorePosition() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 6)),
      );
      await setValue(LATITUDE, pos.latitude);
      await setValue(LONGITUDE, pos.longitude);
    } catch (_) {}
  }

  Future<void> init() async {
    _fetchAndStorePosition(); // fire-and-forget — ne bloque pas le splash
    await appStore.setLanguage(getStringAsync(SELECTED_LANGUAGE_CODE, defaultValue: DEFAULT_LANGUAGE));

    // Sync new configurations when app is open
    await setValue(LAST_APP_CONFIGURATION_SYNCED_TIME, 0);

    ///Set app configurations
    await getAppConfigurations().then((value) {}).catchError((e) async {
      if (!await isNetworkAvailable()) {
        TopToast.show(message: errorInternetNotAvailable, type: TopToastType.error);
      }
      log(e);
    });

    appStore.setLoading(false);
    // Laisser l'animation du logo se terminer avant de changer d'écran
    await _introDone;
    if (!mounted) return;
    if (!getBoolAsync(IS_APP_CONFIGURATION_SYNCED_AT_LEAST_ONCE)) {
      appNotSynced = true;
      setState(() {});
    } else {
      // Thème clair forcé — l'app ne suit plus le thème système.
      // Check if the user is unauthorized and logged in, then clear preferences and cached data.
      // This condition occurs when the user is marked as inactive from the admin panel,
      if (!appConfigurationStore.isUserAuthorized && appStore.isLoggedIn) {
        await clearPreferences();

        // Clear cached wallet history if it exists and is not empty
        if (cachedWalletHistoryList != null && cachedWalletHistoryList!.isNotEmpty) cachedWalletHistoryList!.clear();
      }
      
      if (appConfigurationStore.maintenanceModeStatus) {
        MaintenanceModeScreen().launch(context, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
      } else {
        if (getBoolAsync(IS_FIRST_TIME, defaultValue: true)) {
          const MisonWelcomeScreen().launch(context, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
        } else if (appStore.isLoggedIn) {
          subscribeToFirebaseTopic();
          // Re-synchronise les tokens push à chaque démarrage : sans cela un
          // token régénéré empêche de recevoir appels et messages.
          syncVoipToken();
          refreshPushTokens();
          DashboardScreen().launch(context, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
        } else {
          SignInScreen().launch(context, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
        }
      }
    }
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Symbole « M »
            FadeTransition(
              opacity: _symbolFade,
              child: ScaleTransition(
                scale: _symbolScale,
                child: Image.asset('assets/logo/logo_symbol.png', width: 96),
              ),
            ),
            22.height,
            // Nom « MISON »
            ClipRect(
              child: SlideTransition(
                position: _textSlide,
                child: FadeTransition(
                  opacity: _textFade,
                  child: Image.asset('assets/logo/logo_text.png', width: 220),
                ),
              ),
            ),
            14.height,
            // Trait doré
            AnimatedBuilder(
              animation: _lineWidth,
              builder: (_, __) => Container(
                width: 70 * _lineWidth.value,
                height: 3,
                decoration: BoxDecoration(
                  color: _brandGold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (appNotSynced) ...[
              28.height,
              Observer(
                builder: (_) => appStore.isLoading
                    ? LoaderWidget(colors: const [Color(0xFF3A3A3A), _brandGold]).center()
                    : TextButton(
                        child: Text(language.reload, style: boldTextStyle(color: _brandGold)),
                        onPressed: () {
                          appStore.setLoading(true);
                          init();
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
