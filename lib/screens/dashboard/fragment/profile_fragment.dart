import 'package:booking_system_flutter/utils/feature_flags.dart';
import 'package:booking_system_flutter/screens/cash/cash_debt_screen.dart';
import 'package:booking_system_flutter/component/mison_favorite_places.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/model/user_data_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/auth/change_password_screen.dart';
import 'package:booking_system_flutter/screens/auth/artisan_edit_profile_screen.dart';
import 'package:booking_system_flutter/screens/auth/edit_profile_screen.dart';
import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/screens/auth/profile_selection_screen.dart';
import 'package:booking_system_flutter/screens/setting_screen.dart';
import 'package:booking_system_flutter/screens/support_chat/support_chat_screen.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';

class ProfileFragment extends StatefulWidget {
  @override
  ProfileFragmentState createState() => ProfileFragmentState();
}

class ProfileFragmentState extends State<ProfileFragment> {
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  /// Métier principal (prestataire uniquement), lu depuis /api/auth/me.
  String _profession = '';

  @override
  void initState() {
    super.initState();
    init();
    afterBuildCreated(() {
      appStore.setLoading(false);
      setStatusBarColor(Colors.transparent, statusBarIconBrightness: Brightness.dark);
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
    if (data.contactNumber.validate().isNotEmpty) {
      await appStore.setContactNumber(data.contactNumber.validate());
    }
    _profession = data.designation.validate();

    // /api/auth/me returns profile_picture_url; store it for all avatar widgets.
    await appStore.setUserProfile(data.profileImage.validate());
  }

  Future<void> _onRefresh() async {
    await removeKey(LAST_USER_DETAILS_SYNCED_TIME);
    await init();
    setState(() {});
  }

  /// Suppression du compte : panneau Mison (explications, code PIN,
  /// messages clairs du serveur), puis nettoyage et retour à l'accueil.
  Widget _sectionTitle(String title, {Color? color}) {
    return Text(
      title,
      style: boldTextStyle(size: 16, color: color ?? kMisonGold),
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
    IconData? iconData,
    required VoidCallback onTap,
    String? subtitle,
    Color? accent,
    Color? titleColor,
  }) {
    final Color itemAccent = accent ?? kMisonGold;

    return InkWell(
      onTap: onTap,
      borderRadius: radius(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            if (icon != null || iconData != null) ...[
              // Icône seule, sans rond derrière (même largeur pour aligner les titres).
              SizedBox(
                width: 24,
                child: icon != null
                    ? Image.asset(
                        icon,
                        width: 20,
                        height: 20,
                        color: itemAccent,
                      )
                    : Icon(iconData, size: 22, color: itemAccent),
              ),
              14.width,
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
            appStore.isDarkMode ? context.cardColor : kMisonGold.withValues(alpha: 0.08),
        border: Border.all(color: kMisonGold.withValues(alpha: 0.45)),
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
                      color: kMisonGold.withValues(alpha: 0.2),
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
                                kMisonGold.withValues(alpha: 0.22),
                                kMisonGold.withValues(alpha: 0.08),
                              ],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.person_rounded,
                            size: 44,
                            color: kMisonGold.withValues(alpha: 0.72),
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
                    style: boldTextStyle(size: 18, color: kMisonDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Métier principal du prestataire
                  if (_profession.isNotEmpty) ...[
                    4.height,
                    Row(children: [
                      const Icon(Icons.handyman_rounded, size: 14, color: kMisonGold),
                      4.width,
                      Flexible(
                        child: Text(
                          _profession,
                          style: boldTextStyle(size: 14, color: kMisonGold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ],
                  if (appStore.userContactNumber.validate().isNotEmpty) ...[
                    4.height,
                    Row(children: [
                      const Icon(Icons.phone_rounded, size: 14, color: kMisonGold),
                      4.width,
                      Flexible(
                        child: Text(
                          appStore.userContactNumber.validate(),
                          style: secondaryTextStyle(size: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ],
                  if (appStore.userEmail.validate().isNotEmpty) ...[
                    4.height,
                    Row(children: [
                      const Icon(Icons.mail_outline_rounded, size: 14, color: kMisonGold),
                      4.width,
                      Flexible(
                        child: Text(
                          appStore.userEmail.validate(),
                          style: secondaryTextStyle(size: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ],
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
          Text('Bienvenue sur MISON', style: boldTextStyle(size: 19)),
          6.height,
          Text(
            'Connectez-vous pour gérer votre profil et vos paramètres.',
            style: secondaryTextStyle(size: 14),
          ),
          14.height,
          Row(
            children: [
              AppButton(
                text: "S'inscrire",
                color: context.cardColor,
                shapeBorder: RoundedRectangleBorder(
                  borderRadius: radius(defaultRadius),
                  side: const BorderSide(color: kMisonGold),
                ),
                textStyle: boldTextStyle(color: kMisonGold),
                onTap: () {
                  // Comme depuis la connexion : d'abord le type de compte.
                  const ProfileSelectionScreen().launch(context);
                },
              ).expand(),
              10.width,
              AppButton(
                text: 'Se connecter',
                color: kMisonGold,
                textStyle: boldTextStyle(color: white),
                onTap: () {
                  const SignInScreen().launch(context);
                },
              ).expand(),
            ],
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
                        // Ouvrier : ce qu'il doit à MISON (commandes payées en espèces),
                        // à payer avant d'être bloqué. Activé dans le back-office.
                        if (appStore.userType == USER_TYPE_PROVIDER && FeatureFlags.cashTracking)
                          _menuItem(
                            title: 'Dette MISON',
                            subtitle: "Payer ce que vous devez à MISON (commandes payées en espèces)",
                            iconData: Icons.account_balance_wallet_outlined,
                            onTap: () => CashDebtScreen.open(context),
                          ),
                        if (appStore.userType != USER_TYPE_PROVIDER)
                          _menuItem(
                            title: 'Mes lieux favoris',
                            subtitle: 'Adresses proposées à chaque commande',
                            iconData: Icons.star_outline_rounded,
                            onTap: () => const MisonFavoritePlacesScreen().launch(context),
                          ),
                        _menuItem(
                          title: 'Sécurité',
                          subtitle: 'Code PIN, déconnexion et suppression du compte',
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
                        _menuItem(
                          title: 'Inviter un ami',
                          subtitle: "Partager le lien de l'application (WhatsApp, Facebook, SMS…)",
                          iconData: Icons.card_giftcard_rounded,
                          onTap: () async {
                            final message = await showMisonInviteFriendSheet(context);
                            if (message != null) TopToast.show(message: message, type: TopToastType.success);
                          },
                        ),
                      ]),
                    ],
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
                    // Conditions générales et confidentialité, sous la version.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => checkIfLink(context, appConfigurationStore.termConditions,
                              title: language.termsCondition),
                          child: Text("Conditions générales d'utilisation",
                              style: secondaryTextStyle(size: 13, decoration: TextDecoration.underline)),
                        ),
                        Text('·', style: secondaryTextStyle()),
                        TextButton(
                          onPressed: () => checkIfLink(context, appConfigurationStore.privacyPolicy,
                              title: language.privacyPolicy),
                          child: Text('Confidentialité',
                              style: secondaryTextStyle(size: 13, decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Observer(
                  builder: (context) =>
                      LoaderWidget(colors: const [kMisonDark, kMisonGold]).visible(appStore.isLoading)),
            ],
          );
        },
      ),
    );
  }
}
