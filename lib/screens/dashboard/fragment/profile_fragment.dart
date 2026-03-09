import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/user_data_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/about_screen.dart';
import 'package:booking_system_flutter/screens/auth/change_password_screen.dart';
import 'package:booking_system_flutter/screens/auth/edit_profile_screen.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/screens/service/favourite_service_screen.dart';
import 'package:booking_system_flutter/screens/setting_screen.dart';
import 'package:booking_system_flutter/screens/wallet/user_wallet_balance_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/extensions/num_extenstions.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../bankDetails/view/bank_details.dart';
import '../../favourite_provider_screen.dart';
import '../../helpDesk/help_desk_list_screen.dart';
import '../component/wallet_history.dart';

class ProfileFragment extends StatefulWidget {
  @override
  ProfileFragmentState createState() => ProfileFragmentState();
}

class ProfileFragmentState extends State<ProfileFragment> {
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    init();
    afterBuildCreated(() {
      appStore.setLoading(false);
      setStatusBarColor(context.primaryColor);
    });
  }

  Future<void> init() async {
    if (appStore.isLoggedIn) {
      appStore.setUserWalletAmount();
      await userDetailAPI();
    }
  }

  Future<void> userDetailAPI() async {
    try {
      final currentUser = await getCurrentUserProfile();
      await _applyCurrentUserProfile(currentUser);
      setState(() {});
    } catch (e) {
      // Fallback legacy endpoint if /auth/me is unavailable in some environments.
      await getUserDetail(appStore.userId, forceUpdate: false)
          .then((value) async {
        await saveUserData(value, forceSyncAppConfigurations: false);
        setState(() {});
      }).catchError((_) {
        appStore.setLoading(false);
      });
    }
  }

  Future<void> _applyCurrentUserProfile(UserData data) async {
    if (data.id != null) await appStore.setUserId(data.id.validate());
    if (data.uid.validate().isNotEmpty)
      await appStore.setUId(data.uid.validate());
    if (data.firstName.validate().isNotEmpty) {
      await appStore.setFirstName(data.firstName.validate());
    }
    if (data.lastName.validate().isNotEmpty) {
      await appStore.setLastName(data.lastName.validate());
    }
    if (data.email.validate().isNotEmpty) {
      await appStore.setUserEmail(data.email.validate());
    }

    // /api/auth/me returns profile_picture_url; store it for all avatar widgets.
    await appStore.setUserProfile(data.profileImage.validate());
  }

  Future<void> _onRefresh() async {
    await removeKey(LAST_USER_DETAILS_SYNCED_TIME);
    await init();
    setState(() {});
  }

  void _openBookings() {
    DashboardScreen(redirectToBooking: true).launch(
      context,
      isNewTask: true,
      pageRouteAnimation: PageRouteAnimation.Fade,
    );
  }

  void _deleteAccount() {
    showConfirmDialogCustom(
      context,
      negativeText: language.lblCancel,
      positiveText: language.lblDelete,
      onAccept: (_) {
        ifNotTester(() {
          appStore.setLoading(true);

          deleteAccountCompletely().then((value) async {
            try {
              await userService.removeDocument(appStore.uid);
              await userService.deleteUser();
            } catch (_) {}

            appStore.setLoading(false);
            await clearPreferences();
            toast(value.message);

            push(
              DashboardScreen(),
              isNewTask: true,
              pageRouteAnimation: PageRouteAnimation.Fade,
            );
          }).catchError((e) {
            appStore.setLoading(false);
            toast(e.toString());
          });
        });
      },
      dialogType: DialogType.DELETE,
      title: language.lblDeleteAccountConformation,
    );
  }

  Widget _sectionTitle(String title, {Color? color}) {
    return Text(
      title,
      style: boldTextStyle(size: 14, color: color ?? primaryColor),
    ).paddingOnly(left: 4, bottom: 10, top: 20);
  }

  Widget _menuCard(List<Widget> items) {
    return Container(
      decoration: boxDecorationWithRoundedCorners(
        borderRadius: radius(16),
        backgroundColor: context.cardColor,
        border: Border.all(color: context.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i != items.length - 1)
              Divider(
                  height: 1,
                  color: context.dividerColor.withValues(alpha: 0.5)),
          ],
        ],
      ),
    );
  }

  Widget _menuItem({
    required String title,
    String? icon,
    required VoidCallback onTap,
    String? subtitle,
    Color? accent,
    Color? titleColor,
  }) {
    final Color itemAccent = accent ?? context.primaryColor;

    return InkWell(
      onTap: onTap,
      borderRadius: radius(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: itemAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Image.asset(
                    icon,
                    width: 18,
                    height: 18,
                    color: itemAccent,
                  ),
                ),
              ),
              12.width,
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: boldTextStyle(size: 13, color: titleColor)),
                if (subtitle.validate().isNotEmpty) ...[
                  2.height,
                  Text(
                    subtitle!,
                    style: secondaryTextStyle(size: 11),
                  ),
                ],
              ],
            ).expand(),
            Image.asset(
              ic_arrow_right,
              width: 14,
              height: 14,
              color: context.iconColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: boxDecorationWithRoundedCorners(
        borderRadius: radius(18),
        backgroundColor:
            appStore.isDarkMode ? context.cardColor : lightPrimaryColor,
        border: Border.all(color: primaryColor.withValues(alpha: 0.55)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Builder(builder: (_) {
                final String profileUrl = appStore.userProfileImage.validate();
                final bool hasProfileImage = profileUrl.isNotEmpty;

                return Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: hasProfileImage
                      ? CachedImageWidget(
                          url: profileUrl,
                          height: 96,
                          width: 96,
                          circle: true,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                primaryColor.withValues(alpha: 0.22),
                                primaryColor.withValues(alpha: 0.08),
                              ],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.person_rounded,
                            size: 44,
                            color: primaryColor.withValues(alpha: 0.72),
                          ),
                        ),
                );
              }),
              14.width,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appStore.userFullName.validate(),
                    style: boldTextStyle(size: 16, color: primaryColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  4.height,
                  Text(
                    appStore.userEmail.validate(),
                    style: secondaryTextStyle(size: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ).expand(),
            ],
          ),
          if (appConfigurationStore.isEnableUserWallet) ...[
            12.height,
            Container(
              width: context.width(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: boxDecorationWithRoundedCorners(
                borderRadius: radius(12),
                backgroundColor: primaryColor,
              ),
              child: Row(
                children: [
                  Image.asset(ic_wallet_cartoon, height: 20),
                  8.width,
                  Text(language.walletBalance,
                      style: boldTextStyle(color: white, size: 12)),
                  const Spacer(),
                  Text(
                    appStore.userWalletAmount.toPriceFormat(),
                    style: boldTextStyle(color: white, size: 12),
                  ),
                ],
              ),
            ).onTap(() {
              UserWalletBalanceScreen().launch(context);
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildGuestHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: boxDecorationWithRoundedCorners(
        borderRadius: radius(16),
        backgroundColor: context.cardColor,
        border: Border.all(color: context.dividerColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bienvenue sur Mison', style: boldTextStyle(size: 18)),
          6.height,
          Text(
            'Connectez-vous pour gérer votre profil, vos favoris et vos réservations.',
            style: secondaryTextStyle(size: 12),
          ),
          14.height,
          AppButton(
            width: context.width(),
            text: 'Se connecter',
            color: primaryColor,
            textStyle: boldTextStyle(color: white),
            onTap: () {
              const SignInScreen().launch(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarWidget(
        language.profile,
        textColor: white,
        textSize: APP_BAR_TEXT_SIZE,
        elevation: 0.0,
        color: context.primaryColor,
        showBack: false,
      ),
      body: Observer(
        builder: (BuildContext context) {
          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: _onRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    appStore.isLoggedIn
                        ? _buildLoggedHeader()
                        : _buildGuestHeader(),
                    if (appStore.isLoggedIn) ...[
                      _sectionTitle('Compte'),
                      _menuCard([
                        _menuItem(
                          title: 'Mon profil',
                          subtitle: 'Modifier vos informations personnelles',
                          icon: ic_profile2,
                          onTap: () {
                            EditProfileScreen().launch(context);
                          },
                        ),
                        _menuItem(
                          title: 'Sécurité',
                          subtitle: 'Changer votre mot de passe',
                          icon: ic_lock,
                          onTap: () {
                            ChangePasswordScreen().launch(context);
                          },
                        ),
                        _menuItem(
                          title: 'Paramètres',
                          subtitle: 'Préférences de l\'application',
                          icon: ic_setting,
                          onTap: () {
                            SettingScreen().launch(context);
                          },
                        ),
                      ]),
                      _sectionTitle('Activité'),
                      _menuCard([
                        _menuItem(
                          title: 'Mes réservations',
                          subtitle: 'Suivre vos services en cours',
                          icon: ic_ticket,
                          onTap: _openBookings,
                        ),
                        if (appConfigurationStore.isEnableUserWallet)
                          _menuItem(
                            title: language.walletBalance,
                            subtitle: 'Recharger et suivre votre solde',
                            icon: ic_un_fill_wallet,
                            onTap: () {
                              UserWalletBalanceScreen().launch(context);
                            },
                          ),
                        if (appConfigurationStore.isEnableUserWallet)
                          _menuItem(
                            title: language.walletHistory,
                            subtitle: 'Historique de vos transactions',
                            icon: ic_wallet_history,
                            onTap: () {
                              const UserWalletHistoryScreen().launch(context);
                            },
                          ),
                        _menuItem(
                          title: 'Services favoris',
                          subtitle: 'Retrouvez vos services enregistrés',
                          icon: ic_heart,
                          onTap: () {
                            const FavouriteServiceScreen().launch(context);
                          },
                        ),
                        _menuItem(
                          title: 'Prestataires favoris',
                          subtitle: 'Vos artisans suivis',
                          icon: ic_profile2,
                          onTap: () {
                            const FavouriteProviderScreen().launch(context);
                          },
                        ),
                        if (rolesAndPermissionStore.bankList)
                          _menuItem(
                            title: language.lblBankDetails,
                            subtitle: 'Comptes bancaires et paiements',
                            icon: ic_card,
                            onTap: () {
                              const BankDetails().launch(context);
                            },
                          ),
                      ]),
                    ],
                    _sectionTitle('Assistance et légal'),
                    _menuCard([
                      if (appStore.isLoggedIn &&
                          rolesAndPermissionStore.helpDeskList)
                        _menuItem(
                          title: language.helpDesk,
                          subtitle: 'Support et suivi de vos demandes',
                          icon: ic_help_desk,
                          onTap: () {
                            HelpDeskListScreen().launch(context);
                          },
                        ),
                      if (rolesAndPermissionStore.aboutUs)
                        _menuItem(
                          title: language.lblAboutApp,
                          subtitle: 'Informations sur Mison',
                          icon: ic_about_us,
                          onTap: () {
                            AboutScreen().launch(context);
                          },
                        ),
                      if (rolesAndPermissionStore.privacyPolicy)
                        _menuItem(
                          title: language.privacyPolicy,
                          subtitle: 'Protection de vos données',
                          icon: ic_shield_done,
                          onTap: () {
                            checkIfLink(
                                context, appConfigurationStore.privacyPolicy,
                                title: language.privacyPolicy);
                          },
                        ),
                      if (rolesAndPermissionStore.termCondition)
                        _menuItem(
                          title: language.termsCondition,
                          subtitle: 'Conditions d\'utilisation',
                          icon: ic_document,
                          onTap: () {
                            checkIfLink(
                                context, appConfigurationStore.termConditions,
                                title: language.termsCondition);
                          },
                        ),
                      if (rolesAndPermissionStore.refundAndCancellationPolicy)
                        _menuItem(
                          title: language.refundPolicy,
                          subtitle: 'Modalités de remboursement',
                          icon: ic_refund,
                          onTap: () {
                            checkIfLink(
                                context, appConfigurationStore.refundPolicy,
                                title: language.refundPolicy);
                          },
                        ),
                    ]),
                    _sectionTitle('Session',
                        color: appStore.isLoggedIn ? redColor : primaryColor),
                    _menuCard([
                      if (!appStore.isLoggedIn)
                        _menuItem(
                          title: language.signIn,
                          subtitle: 'Accéder à votre compte',
                          icon: ic_lock,
                          onTap: () {
                            const SignInScreen().launch(context);
                          },
                        ),
                      if (appStore.isLoggedIn)
                        _menuItem(
                          title: language.logout,
                          subtitle: 'Fermer votre session',
                          icon: ic_lock,
                          titleColor: redColor,
                          accent: redColor,
                          onTap: () {
                            logout(context);
                          },
                        ),
                      if (appStore.isLoggedIn)
                        _menuItem(
                          title: language.lblDeleteAccount,
                          subtitle: 'Supprimer définitivement votre compte',
                          icon: ic_delete_account,
                          titleColor: redColor,
                          accent: redColor,
                          onTap: _deleteAccount,
                        ),
                    ]),
                    20.height,
                    SnapHelperWidget<PackageInfoData>(
                      future: getPackageInfo(),
                      onSuccess: (data) {
                        return TextButton(
                          child: VersionInfoWidget(
                            prefixText: 'v',
                            textStyle: secondaryTextStyle(),
                          ),
                          onPressed: () {
                            showAboutDialog(
                              context: context,
                              applicationName: APP_NAME,
                              applicationVersion: data.versionName,
                              applicationIcon: Image.asset(appLogo, height: 50),
                            );
                          },
                        ).center();
                      },
                    ),
                  ],
                ),
              ),
              Observer(
                  builder: (context) =>
                      LoaderWidget().visible(appStore.isLoading)),
            ],
          );
        },
      ),
    );
  }
}
