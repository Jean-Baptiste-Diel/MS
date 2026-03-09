import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/base_scaffold_body.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/screens/auth/otp_login_screen.dart';
import 'package:booking_system_flutter/screens/auth/profile_selection_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../network/rest_apis.dart';

class SignInScreen extends StatefulWidget {
  final bool? isFromDashboard;
  final bool? isFromServiceBooking;
  final bool returnExpected;
  final bool allowHomeNavigation;

  const SignInScreen({
    this.isFromDashboard,
    this.isFromServiceBooking,
    this.returnExpected = false,
    this.allowHomeNavigation = false,
  });

  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> forgotFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> forgotResetFormKey = GlobalKey<FormState>();

  TextEditingController emailCont = TextEditingController();
  TextEditingController passwordCont = TextEditingController();
  TextEditingController forgotEmailCont = TextEditingController();
  TextEditingController forgotOtpCont = TextEditingController();
  TextEditingController forgotNewPasswordCont = TextEditingController();
  TextEditingController forgotConfirmPasswordCont = TextEditingController();

  FocusNode emailFocus = FocusNode();
  FocusNode passwordFocus = FocusNode();

  bool isRemember = true;
  bool isForgotPasswordMode = false;
  bool showForgotOtpStep = false;
  String forgotEmail = '';

  @override
  void initState() {
    super.initState();
    init();
    _recreateForgotControllers();
  }

  void init() {
    isRemember = getBoolAsync(IS_REMEMBERED);
    if (isRemember) {
      emailCont.text = getStringAsync(USER_EMAIL);
      passwordCont.text = getStringAsync(USER_PASSWORD);
    } else {
      emailCont.clear();
      passwordCont.clear();
    }
  }

  void _recreateForgotControllers({String initialEmail = ''}) {
    _safeDisposeController(forgotEmailCont);
    _safeDisposeController(forgotOtpCont);
    _safeDisposeController(forgotNewPasswordCont);
    _safeDisposeController(forgotConfirmPasswordCont);

    forgotEmailCont = TextEditingController(text: initialEmail);
    forgotOtpCont = TextEditingController();
    forgotNewPasswordCont = TextEditingController();
    forgotConfirmPasswordCont = TextEditingController();
  }

  void _safeDisposeController(TextEditingController controller) {
    try {
      controller.dispose();
    } catch (_) {}
  }

  //region Methods

  void _handleLogin() {
    hideKeyboard(context);
    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();
      _handleLoginUsers();
    }
  }

  void _handleLoginUsers() async {
    hideKeyboard(context);
    Map<String, dynamic> request = {
      'identifier': emailCont.text.trim(),
      'password': passwordCont.text.trim(),
    };

    appStore.setLoading(true);
    try {
      final loginResponse = await loginUser(request, isSocialLogin: false);

      await saveUserData(loginResponse.userData!,
          refreshToken: loginResponse.refreshToken);

      await setValue(USER_PASSWORD, passwordCont.text);
      await setValue(IS_REMEMBERED, isRemember);
      await appStore.setLoginType(LOGIN_TYPE_USER);

      authService.verifyFirebaseUser();
      TextInput.finishAutofillContext();

      onLoginSuccessRedirection();
    } catch (e) {
      appStore.setLoading(false);
      toast(e.toString());
    }
  }

  void googleSignIn() async {
    if (!appStore.isLoading) {
      appStore.setLoading(true);
      await authService.signInWithGoogle(context).then((googleUser) async {
        String firstName = '';
        String lastName = '';
        if (googleUser.displayName.validate().split(' ').length >= 1)
          firstName = googleUser.displayName.splitBefore(' ');
        if (googleUser.displayName.validate().split(' ').length >= 2)
          lastName = googleUser.displayName.splitAfter(' ');

        Map<String, dynamic> request = {
          'first_name': firstName,
          'last_name': lastName,
          'email': googleUser.email,
          'username': googleUser.email
              .splitBefore('@')
              .replaceAll('.', '')
              .toLowerCase(),
          // 'password': passwordCont.text.trim(),
          'social_image': googleUser.photoURL,
          'login_type': LOGIN_TYPE_GOOGLE,
        };
        var loginResponse = await loginUser(request, isSocialLogin: true);

        loginResponse.userData!.profileImage = googleUser.photoURL.validate();

        await saveUserData(loginResponse.userData!,
            refreshToken: loginResponse.refreshToken);
        appStore.setLoginType(LOGIN_TYPE_GOOGLE);

        authService.verifyFirebaseUser();

        onLoginSuccessRedirection();
        appStore.setLoading(false);
      }).catchError((e) {
        appStore.setLoading(false);
        log(e.toString());
        toast(e.toString());
      });
    }
  }

  void appleSign() async {
    if (!appStore.isLoading) {
      appStore.setLoading(true);

      await authService.appleSignIn().then((req) async {
        // Ensure first_name and last_name are not empty or null
        String email = req['email'] ??
            'unknown_${DateTime.now().millisecondsSinceEpoch}@apple.com';
        String firstName = req['first_name']?.toString().trim() ?? '';
        String lastName = req['last_name']?.toString().trim() ?? '';

        // Fallback if names are not available
        if (firstName.isEmpty || lastName.isEmpty) {
          final parts = email.split('@').first.split('.');
          firstName = parts.first.capitalizeFirstLetter();
          lastName =
              parts.length > 1 ? parts[1].capitalizeFirstLetter() : 'User';
        }

        req['first_name'] = firstName;
        req['last_name'] = lastName;

        await loginUser(req, isSocialLogin: true).then((value) async {
          await saveUserData(value.userData!, refreshToken: value.refreshToken);
          appStore.setLoginType(LOGIN_TYPE_APPLE);

          appStore.setLoading(false);
          authService.verifyFirebaseUser();

          onLoginSuccessRedirection();
        }).catchError((e) {
          appStore.setLoading(false);
          log(e.toString());
          throw e;
        });
      }).catchError((e) {
        appStore.setLoading(false);
        toast(e.toString());
      });
    }
  }

  void otpSignIn() async {
    hideKeyboard(context);

    const OTPLoginScreen().launch(context);
  }

  void onLoginSuccessRedirection() {
    afterBuildCreated(() {
      appStore.setLoading(false);
      toast("Your Account signed in successfully.");
      if (widget.isFromServiceBooking.validate() ||
          widget.isFromDashboard.validate() ||
          widget.returnExpected.validate()) {
        if (widget.isFromDashboard.validate()) {
          push(DashboardScreen(redirectToBooking: true),
              isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
        } else {
          finish(context, true);
        }
      } else {
        DashboardScreen().launch(context,
            isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
      }
    });
  }

  void _goToHome() {
    hideKeyboard(context);
    DashboardScreen().launch(
      context,
      isNewTask: true,
      pageRouteAnimation: PageRouteAnimation.Fade,
    );
  }

  void _openForgotPasswordFlow() {
    hideKeyboard(context);
    _recreateForgotControllers(initialEmail: emailCont.text.trim());
    setState(() {
      isForgotPasswordMode = true;
      showForgotOtpStep = false;
    });
  }

  void _backFromForgotFlow() {
    hideKeyboard(context);
    setState(() {
      if (showForgotOtpStep) {
        showForgotOtpStep = false;
      } else {
        isForgotPasswordMode = false;
      }
    });
  }

  Future<void> _sendForgotOtp() async {
    hideKeyboard(context);
    if (!forgotFormKey.currentState!.validate()) return;

    appStore.setLoading(true);
    final email = forgotEmailCont.text.trim();
    try {
      final res = await forgotPassword({'email': email});
      appStore.setLoading(false);
      if (!mounted) return;
      setState(() {
        forgotEmail = email;
        showForgotOtpStep = true;
      });
      toast(res.message.validate());
    } catch (e) {
      appStore.setLoading(false);
      toast(e.toString());
    }
  }

  Future<void> _resetForgotPassword() async {
    hideKeyboard(context);
    if (forgotOtpCont.text.trim().length != OTP_TEXT_FIELD_LENGTH) {
      toast(language.pleaseEnterValidOTP);
      return;
    }
    if (!forgotResetFormKey.currentState!.validate()) return;
    if (forgotNewPasswordCont.text != forgotConfirmPasswordCont.text) {
      toast(language.passwordNotMatch);
      return;
    }
    if (!_isForgotPasswordStrong) {
      toast('Le mot de passe ne respecte pas les critères');
      return;
    }

    appStore.setLoading(true);
    try {
      final res = await resetPassword({
        'email': forgotEmail,
        'otp_code': forgotOtpCont.text.trim(),
        'new_password': forgotNewPasswordCont.text.trim(),
      });
      appStore.setLoading(false);
      toast(res.message.validate());
      if (!mounted) return;
      _recreateForgotControllers(initialEmail: forgotEmail);
      setState(() {
        isForgotPasswordMode = false;
        showForgotOtpStep = false;
      });
      emailCont.text = forgotEmail;
    } catch (e) {
      appStore.setLoading(false);
      toast(e.toString());
    }
  }

  Future<void> _resendForgotOtp() async {
    if (forgotEmail.isEmpty) return;
    appStore.setLoading(true);
    try {
      final res = await forgotPassword({'email': forgotEmail});
      appStore.setLoading(false);
      toast(res.message.validate().isNotEmpty
          ? res.message.validate()
          : language.otpSentSuccessfully);
    } catch (e) {
      appStore.setLoading(false);
      toast(e.toString());
    }
  }

  bool get _forgotHasMin12Chars =>
      forgotNewPasswordCont.text.trim().length >= 12;

  bool get _forgotHasSpecialChar =>
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\\/\[\]`~+=;]')
          .hasMatch(forgotNewPasswordCont.text);

  bool get _forgotHasDigit =>
      RegExp(r'\d').hasMatch(forgotNewPasswordCont.text);

  bool get _forgotHasUppercase =>
      RegExp(r'[A-Z]').hasMatch(forgotNewPasswordCont.text);

  bool get _isForgotPasswordStrong =>
      _forgotHasMin12Chars &&
      _forgotHasSpecialChar &&
      _forgotHasDigit &&
      _forgotHasUppercase;

//endregion

//region Widgets
  Widget _buildTopWidget() {
    return Container(
      child: Column(
        children: [
          Text("Bienvenu sur Mison", style: boldTextStyle(size: 24)).center(),
          16.height,
          Text("Content de vous revoir",
                  style: primaryTextStyle(size: 16),
                  textAlign: TextAlign.center)
              .center()
              .paddingSymmetric(horizontal: 32),
          32.height,
        ],
      ),
    );
  }

  Widget _buildForgotTopWidget() {
    final String title = showForgotOtpStep
        ? 'Réinitialiser le mot de passe'
        : 'Mot de passe oublié';
    final String subtitle = showForgotOtpStep
        ? 'Saisissez le code reçu puis votre nouveau mot de passe.'
        : 'Entrez votre email pour recevoir un code OTP.';

    return Column(
      children: [
        Text(title, style: boldTextStyle(size: 24)).center(),
        12.height,
        Text(
          subtitle,
          style: primaryTextStyle(size: 14),
          textAlign: TextAlign.center,
        ).center().paddingSymmetric(horizontal: 20),
        24.height,
      ],
    );
  }

  Widget _buildForgotPasswordRule({
    required String label,
    required bool isValid,
  }) {
    final bool hasInput = forgotNewPasswordCont.text.isNotEmpty;
    final Color inactiveColor =
        hasInput ? Colors.red : textSecondaryColorGlobal;

    return Row(
      children: [
        Icon(
          isValid ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: isValid ? Colors.green : inactiveColor,
        ),
        6.width,
        Text(
          label,
          style: secondaryTextStyle(
            size: 12,
            color: isValid ? Colors.green : inactiveColor,
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordRules() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildForgotPasswordRule(
          label: '12 caractères minimum',
          isValid: _forgotHasMin12Chars,
        ),
        4.height,
        _buildForgotPasswordRule(
          label: '1 caractère spécial',
          isValid: _forgotHasSpecialChar,
        ),
        4.height,
        _buildForgotPasswordRule(
          label: '1 chiffre',
          isValid: _forgotHasDigit,
        ),
        4.height,
        _buildForgotPasswordRule(
          label: '1 lettre majuscule',
          isValid: _forgotHasUppercase,
        ),
      ],
    );
  }

  Widget _buildForgotEmailForm() {
    return Form(
      key: forgotFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          AppTextField(
            textFieldType: TextFieldType.NAME,
            controller: forgotEmailCont,
            errorThisFieldRequired: language.requiredText,
            keyboardType: TextInputType.emailAddress,
            decoration: inputDecoration(
              context,
              labelText: language.hintEmailTxt,
              hintText: language.hintEmailAddressTxt,
            ),
            suffix: ic_message.iconImage(size: 10).paddingAll(14),
            isValidationRequired: true,
            validator: (val) {
              if (val == null || val.trim().isEmpty)
                return language.requiredText;
              return null;
            },
          ),
          20.height,
          AppButton(
            text: language.btnSendOtp,
            color: primaryColor,
            textColor: Colors.white,
            width: context.width() - context.navigationBarHeight,
            onTap: _sendForgotOtp,
          ),
          12.height,
          TextButton(
            onPressed: _backFromForgotFlow,
            child: Text(
              'Retour à la connexion',
              style: boldTextStyle(color: primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForgotResetForm() {
    return Form(
      key: forgotResetFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          PinCodeTextField(
            appContext: context,
            length: OTP_TEXT_FIELD_LENGTH,
            controller: forgotOtpCont,
            autoDisposeControllers: false,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textStyle: boldTextStyle(size: 20),
            cursorColor: primaryColor,
            pinTheme: PinTheme(
              shape: PinCodeFieldShape.box,
              borderRadius: BorderRadius.circular(12),
              fieldHeight: 55,
              fieldWidth: 50,
              activeFillColor: context.cardColor,
              inactiveFillColor: context.cardColor,
              selectedFillColor: context.cardColor,
              activeColor: primaryColor,
              inactiveColor: borderColor,
              selectedColor: primaryColor,
            ),
            enableActiveFill: true,
            onChanged: (value) {},
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resendForgotOtp,
              child: Text(
                'Renvoyer le code',
                style: boldTextStyle(color: primaryColor),
              ),
            ),
          ),
          8.height,
          AppTextField(
            textFieldType: TextFieldType.PASSWORD,
            controller: forgotNewPasswordCont,
            errorThisFieldRequired: language.requiredText,
            decoration: inputDecoration(context,
                labelText: language.hintNewPasswordTxt),
            onChanged: (_) {
              setState(() {});
            },
            isValidationRequired: true,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return language.requiredText;
              }
              if (!_isForgotPasswordStrong) {
                return 'Le mot de passe ne respecte pas les critères';
              }
              return null;
            },
          ),
          8.height,
          _buildForgotPasswordRules(),
          16.height,
          AppTextField(
            textFieldType: TextFieldType.PASSWORD,
            controller: forgotConfirmPasswordCont,
            errorThisFieldRequired: language.requiredText,
            decoration: inputDecoration(
              context,
              labelText: language.hintReenterPasswordTxt,
            ),
            onChanged: (_) {
              setState(() {});
            },
            isValidationRequired: true,
            validator: (val) {
              if (val == null || val.trim().isEmpty)
                return language.requiredText;
              if (val != forgotNewPasswordCont.text)
                return language.passwordNotMatch;
              return null;
            },
          ),
          20.height,
          AppButton(
            text: language.resetPassword,
            color: primaryColor,
            textColor: Colors.white,
            width: context.width() - context.navigationBarHeight,
            onTap: _resetForgotPassword,
          ),
          12.height,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _backFromForgotFlow,
                child: Text(
                  'Retour',
                  style: boldTextStyle(color: primaryColor),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    isForgotPasswordMode = false;
                    showForgotOtpStep = false;
                  });
                },
                child: Text(
                  'Connexion',
                  style: boldTextStyle(color: primaryColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRememberWidget() {
    return Column(
      children: [
        8.height,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            RoundedCheckBox(
              borderColor: context.primaryColor,
              checkedColor: context.primaryColor,
              isChecked: isRemember,
              text: language.rememberMe,
              textStyle: secondaryTextStyle(),
              size: 20,
              onTap: (value) async {
                await setValue(IS_REMEMBERED, isRemember);
                isRemember = !isRemember;
                setState(() {});
              },
            ),
            TextButton(
              onPressed: () {
                _openForgotPasswordFlow();
              },
              child: Text(
                language.forgotPassword,
                style: boldTextStyle(
                    color: primaryColor, fontStyle: FontStyle.italic),
                textAlign: TextAlign.right,
              ),
            ).flexible(),
          ],
        ),
        24.height,
        AppButton(
          text: language.signIn,
          color: primaryColor,
          textColor: Colors.white,
          width: context.width() - context.navigationBarHeight,
          onTap: () {
            _handleLogin();
          },
        ),
        16.height,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(language.doNotHaveAccount, style: secondaryTextStyle()),
            TextButton(
              onPressed: () {
                hideKeyboard(context);

                ProfileSelectionScreen().launch(context);
              },
              child: Text(
                language.signUp,
                style: boldTextStyle(
                  color: primaryColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ) /* ,
        TextButton(
          onPressed: () {
            if (isAndroid) {
              if (getStringAsync(PROVIDER_PLAY_STORE_URL).isNotEmpty) {
                launchUrl(Uri.parse(getStringAsync(PROVIDER_PLAY_STORE_URL)), mode: LaunchMode.externalApplication);
              } else {
                launchUrl(Uri.parse('${getSocialMediaLink(LinkProvider.PLAY_STORE)}$PROVIDER_PACKAGE_NAME'), mode: LaunchMode.externalApplication);
              }
            } else if (isIOS) {
              if (getStringAsync(PROVIDER_APPSTORE_URL).isNotEmpty) {
                commonLaunchUrl(getStringAsync(PROVIDER_APPSTORE_URL));
              } else {
                commonLaunchUrl(IOS_LINK_FOR_PARTNER);
              }
            }
          },
          child: Text(language.lblRegisterAsPartner, style: boldTextStyle(color: primaryColor)),
        ) */
      ],
    );
  }

  Widget _buildSocialWidget() {
    if (appConfigurationStore.socialLoginStatus) {
      return Column(
        children: [
          20.height,
          if ((appConfigurationStore.googleLoginStatus ||
                  appConfigurationStore.otpLoginStatus) ||
              (isIOS && appConfigurationStore.appleLoginStatus))
            Row(
              children: [
                Divider(color: context.dividerColor, thickness: 2).expand(),
                16.width,
                Text(language.lblOrContinueWith, style: secondaryTextStyle()),
                16.width,
                Divider(color: context.dividerColor, thickness: 2).expand(),
              ],
            ),
          24.height,
          if (appConfigurationStore.googleLoginStatus)
            AppButton(
              text: '',
              color: context.cardColor,
              padding: const EdgeInsets.all(8),
              textStyle: boldTextStyle(),
              width: context.width() - context.navigationBarHeight,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: boxDecorationWithRoundedCorners(
                      backgroundColor: primaryColor.withValues(alpha: 0.1),
                      boxShape: BoxShape.circle,
                    ),
                    child: const GoogleLogoWidget(size: 16),
                  ),
                  Text(language.lblSignInWithGoogle,
                          style: boldTextStyle(size: 12),
                          textAlign: TextAlign.center)
                      .expand(),
                ],
              ),
              onTap: googleSignIn,
            ),
          if (appConfigurationStore.googleLoginStatus) 16.height,
          if (appConfigurationStore.otpLoginStatus)
            AppButton(
              text: '',
              color: context.cardColor,
              padding: const EdgeInsets.all(8),
              textStyle: boldTextStyle(),
              width: context.width() - context.navigationBarHeight,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: boxDecorationWithRoundedCorners(
                      backgroundColor: primaryColor.withValues(alpha: 0.1),
                      boxShape: BoxShape.circle,
                    ),
                    child: ic_calling
                        .iconImage(size: 18, color: primaryColor)
                        .paddingAll(4),
                  ),
                  Text(language.lblSignInWithOTP,
                          style: boldTextStyle(size: 12),
                          textAlign: TextAlign.center)
                      .expand(),
                ],
              ),
              onTap: otpSignIn,
            ),
          if (appConfigurationStore.otpLoginStatus) 16.height,
          if (isIOS)
            if (appConfigurationStore.appleLoginStatus)
              AppButton(
                text: '',
                color: context.cardColor,
                padding: const EdgeInsets.all(8),
                textStyle: boldTextStyle(),
                width: context.width() - context.navigationBarHeight,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: boxDecorationWithRoundedCorners(
                        backgroundColor: primaryColor.withValues(alpha: 0.1),
                        boxShape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.apple),
                    ),
                    Text(language.lblSignInWithApple,
                            style: boldTextStyle(size: 12),
                            textAlign: TextAlign.center)
                        .expand(),
                  ],
                ),
                onTap: appleSign,
              ),
        ],
      );
    } else {
      return const Offstage();
    }
  }

//endregion

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  @override
  void dispose() {
    _safeDisposeController(emailCont);
    _safeDisposeController(passwordCont);
    _safeDisposeController(forgotEmailCont);
    _safeDisposeController(forgotOtpCont);
    _safeDisposeController(forgotNewPasswordCont);
    _safeDisposeController(forgotConfirmPasswordCont);
    emailFocus.dispose();
    passwordFocus.dispose();

    if (widget.isFromServiceBooking.validate()) {
      setStatusBarColor(Colors.transparent,
          statusBarIconBrightness: Brightness.dark);
    } else if (widget.isFromDashboard.validate()) {
      setStatusBarColor(Colors.transparent,
          statusBarIconBrightness: Brightness.light);
    } else {
      setStatusBarColor(primaryColor,
          statusBarIconBrightness: Brightness.light);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => hideKeyboard(context),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          leading: isForgotPasswordMode
              ? Container(
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _backFromForgotFlow,
                    icon: Icon(Icons.arrow_back, color: context.iconColor),
                  ),
                )
              : (Navigator.of(context).canPop()
                  ? Container(
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        shape: BoxShape.circle,
                      ),
                      child: BackWidget(iconColor: context.iconColor))
                  : null),
          actions: [
            if (!isForgotPasswordMode &&
                widget.allowHomeNavigation &&
                !Navigator.of(context).canPop())
              IconButton(
                onPressed: _goToHome,
                icon: Icon(Icons.home_rounded, color: context.iconColor),
                tooltip: language.home,
              ),
          ],
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
              statusBarIconBrightness:
                  appStore.isDarkMode ? Brightness.light : Brightness.dark,
              statusBarColor: context.scaffoldBackgroundColor),
        ),
        body: Body(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Observer(builder: (context) {
              if (isForgotPasswordMode) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    (context.height() * 0.12).toInt().height,
                    _buildForgotTopWidget(),
                    if (showForgotOtpStep)
                      _buildForgotResetForm()
                    else
                      _buildForgotEmailForm(),
                    30.height,
                  ],
                );
              }

              return Form(
                key: formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    (context.height() * 0.12).toInt().height,
                    _buildTopWidget(),
                    AutofillGroup(
                      child: Column(
                        children: [
                          AppTextField(
                            textFieldType: TextFieldType.NAME,
                            controller: emailCont,
                            focus: emailFocus,
                            nextFocus: passwordFocus,
                            errorThisFieldRequired: language.requiredText,
                            keyboardType: TextInputType.text,
                            decoration: inputDecoration(
                              context,
                              labelText: 'Identifiant',
                              hintText: 'Entrez votre numéro ou email',
                            ),
                            suffix:
                                ic_message.iconImage(size: 10).paddingAll(14),
                            autoFillHints: [AutofillHints.username],
                            isValidationRequired: true,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return language.requiredText;
                              }
                              return null;
                            },
                          ),
                          16.height,
                          AppTextField(
                            textFieldType: TextFieldType.PASSWORD,
                            controller: passwordCont,
                            focus: passwordFocus,
                            obscureText: true,
                            suffixPasswordVisibleWidget:
                                ic_show.iconImage(size: 10).paddingAll(14),
                            suffixPasswordInvisibleWidget:
                                ic_hide.iconImage(size: 10).paddingAll(14),
                            decoration: inputDecoration(context,
                                labelText: language.hintPasswordTxt),
                            autoFillHints: [AutofillHints.password],
                            isValidationRequired: true,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return language.requiredText;
                              }
                              return null;
                            },
                            onFieldSubmitted: (s) {
                              _handleLogin();
                            },
                          ),
                        ],
                      ),
                    ),
                    _buildRememberWidget(),
                    if (!getBoolAsync(HAS_IN_REVIEW)) _buildSocialWidget(),
                    30.height,
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
