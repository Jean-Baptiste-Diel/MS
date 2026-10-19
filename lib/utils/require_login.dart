import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Les visiteurs parcourent l'app sans compte (App Store 5.1.1) ; passer une
/// commande demande d'être connecté. Propose la connexion et retourne true si
/// un client est connecté au retour.
Future<bool> requireClientLogin(BuildContext context) async {
  if (appStore.isLoggedIn) return appStore.userType != USER_TYPE_PROVIDER;

  final goToLogin = await showMisonConfirmSheet(
    context,
    title: 'Connectez-vous pour commander',
    subtitle: 'Vous pouvez parcourir les services sans compte. '
        'Pour passer une commande, connectez-vous ou créez votre compte.',
    icon: Icons.lock_outline_rounded,
    confirmLabel: 'Se connecter',
    cancelLabel: 'Plus tard',
  );
  if (!goToLogin || !context.mounted) return false;

  await SignInScreen(returnExpected: true).launch(context);
  if (!appStore.isLoggedIn || !context.mounted) return false;
  // Compte prestataire : il n'a rien à commander, on ouvre son accueil.
  if (appStore.userType == USER_TYPE_PROVIDER) {
    DashboardScreen().launch(context, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
    return false;
  }
  return true;
}
