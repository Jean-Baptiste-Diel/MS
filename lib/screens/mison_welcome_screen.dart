import 'dart:ui';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';

/// Écran de bienvenue Mison avec image floutée et logo
/// Affiché au premier lancement de l'application
class MisonWelcomeScreen extends StatefulWidget {
  const MisonWelcomeScreen({Key? key}) : super(key: key);

  @override
  State<MisonWelcomeScreen> createState() => _MisonWelcomeScreenState();
}

class _MisonWelcomeScreenState extends State<MisonWelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _setStatusBar();
  }

  void _setStatusBar() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onCommencer() async {
    await setValue(IS_FIRST_TIME, false);
    DashboardScreen().launch(context, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.asset(
            mison_welcome_bg,
            fit: BoxFit.cover,
            height: context.height(),
            width: context.width(),
            errorBuilder: (context, error, stackTrace) {
              // Fallback si l'image n'existe pas encore
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF2D3436),
                      const Color(0xFF636E72),
                    ],
                  ),
                ),
              );
            },
          ),

          // Blur overlay
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo and title
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _fadeAnimation.value,
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo
                            Image.asset(
                              appLogo,
                              height: 100,
                              width: 100,
                            ),
                            24.height,
                            // App name
                            Text(
                              'Mison',
                              style: boldTextStyle(
                                size: 42,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const Spacer(flex: 3),

                // Commencer button
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _fadeAnimation.value,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _onCommencer,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC99700),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.construction,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                12.width,
                                Text(
                                  'Commencer',
                                  style: boldTextStyle(
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                12.width,
                                const Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                48.height,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
