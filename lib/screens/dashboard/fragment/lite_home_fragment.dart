import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

class LiteHomeFragment extends StatelessWidget {
  const LiteHomeFragment({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarWidget(
        'Accueil',
        textColor: white,
        textSize: APP_BAR_TEXT_SIZE,
        elevation: 0.0,
        color: context.primaryColor,
        showBack: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: boxDecorationWithRoundedCorners(
              borderRadius: radius(16),
              backgroundColor:
                  appStore.isDarkMode ? context.cardColor : lightPrimaryColor,
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Image.asset(
                      ic_hi,
                      width: 26,
                      height: 26,
                      color: primaryColor,
                    ),
                  ),
                ),
                12.width,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appStore.isLoggedIn
                          ? 'Bonjour ${appStore.userFirstName.validate()}'
                          : 'Bienvenue sur Mison',
                      style: boldTextStyle(size: 18, color: primaryColor),
                    ),
                    4.height,
                    Text(
                      'Utilisez les onglets Services, Chat et Profil.',
                      style: secondaryTextStyle(size: 12),
                    ),
                  ],
                ).expand(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
