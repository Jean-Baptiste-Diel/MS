import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/user_data_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/auth/change_password_screen.dart';
import 'package:booking_system_flutter/screens/auth/artisan_edit_profile_screen.dart';
import 'package:booking_system_flutter/screens/auth/edit_profile_screen.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/screens/setting_screen.dart';
import 'package:booking_system_flutter/screens/support_chat/support_chat_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

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
            TopToast.show(message: value.message.validate());

            push(
              DashboardScreen(),
              isNewTask: true,
              pageRouteAnimation: PageRouteAnimation.Fade,
            );
          }).catchError((e) {
            appStore.setLoading(false);
            TopToast.show(message: e.toString(), type: TopToastType.error);
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
      style: boldTextStyle(size: 16, color: color ?? primaryColor),
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
                Text(title, style: boldTextStyle(size: 16, color: titleColor)),
                if (subtitle.validate().isNotEmpty) ...[
                  2.height,
                  Text(
                    subtitle!,
                    style: secondaryTextStyle(size: 14),
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
              Observer(builder: (_) {
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
                    style: boldTextStyle(size: 18, color: primaryColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  4.height,
                  Text(
                    appStore.userEmail.validate(),
                    style: secondaryTextStyle(size: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ).expand(),
            ],
          ),
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
          Text('Bienvenue sur Mison', style: boldTextStyle(size: 19)),
          6.height,
          Text(
            'Connectez-vous pour gérer votre profil et vos paramètres.',
            style: secondaryTextStyle(size: 14),
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
      backgroundColor: Colors.transparent,
      // Logo centré + fond de la page, comme l'accueil
      appBar: MisonAppBar(title: language.profile),
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
                            if (appStore.userType == USER_TYPE_PROVIDER) {
                              const ArtisanEditProfileScreen().launch(context);
                            } else {
                              EditProfileScreen().launch(context);
                            }
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
                    ],
                    if (appStore.isLoggedIn) ...[
                      _sectionTitle('Aide'),
                      _menuCard([
                        _menuItem(
                          title: 'Contacter le support',
                          subtitle: 'Discuter avec notre équipe',
                          icon: ic_helpAndSupport,
                          onTap: () {
                            const SupportChatScreen().launch(context);
                          },
                        ),
                      ]),
                    ],
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
