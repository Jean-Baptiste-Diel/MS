import 'package:booking_system_flutter/screens/booking/mison_search_service_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../../main.dart';
import '../../../auth/sign_in_screen.dart';

/// Composant dashboard pour lancer le nouveau flow de réservation Mison
/// Affiche un bouton "Nouvelle Demande" qui mène vers la sélection de service
class MisonNewRequestDashboardComponent extends StatelessWidget {
  const MisonNewRequestDashboardComponent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: boxDecorationDefault(
        color: primaryColor,
        borderRadius: radius(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      width: context.width(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.handyman, color: Colors.white, size: 24),
              ),
              16.width,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Besoin d\'un ouvrier ?',
                      style: boldTextStyle(color: Colors.white, size: 16),
                    ),
                    4.height,
                    Text(
                      'Postez votre demande et trouvez le meilleur professionnel',
                      style: secondaryTextStyle(color: Colors.white.withOpacity(0.8), size: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
          16.height,
          AppButton(
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline, color: primaryColor, size: 20),
                8.width,
                Text('Nouvelle Demande', style: boldTextStyle(color: primaryColor, size: 14)),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: Colors.white,
            shapeBorder: RoundedRectangleBorder(borderRadius: radius(12)),
            onTap: () async {
              if (appStore.isLoggedIn) {
                const MisonSearchServiceScreen().launch(context);
              } else {
                setStatusBarColor(Colors.white, statusBarIconBrightness: Brightness.dark);
                bool? res = await const SignInScreen(isFromDashboard: true).launch(context);

                if (res ?? false) {
                  const MisonSearchServiceScreen().launch(context);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
