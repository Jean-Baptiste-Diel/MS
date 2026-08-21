import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/base_scaffold_body.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/screens/auth/otp_login_screen.dart';
import 'package:booking_system_flutter/screens/auth/profile_selection_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../network/rest_apis.dart';
import '../../network/network_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

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
  FocusNode forgotNewPasswordFocus = FocusNode();
  FocusNode forgotConfirmPasswordFocus = FocusNode();

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

  /// Normalise l'identifiant avant envoi au back :
  /// - email ou numéro déjà préfixé '+' → envoi direct
  /// - numéro avec indicatif mais sans '+' (≥ 10 chiffres) → ajoute '+'
  /// - numéro sans indicatif (< 10 chiffres) → lève une exception
  String _normalizeIdentifier(String raw) {
    final trimmed = raw.trim();
    if (trimmed.contains('@')) return trimmed;
    if (trimmed.startsWith('+')) return trimmed;

    final digitsOnly = trimmed.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (RegExp(r'^\d+$').hasMatch(digitsOnly)) {
      if (digitsOnly.length >= 10) {
        return '+$digitsOnly';
      }
      throw Exception("L'indicatif téléphonique est requis (ex: +221XXXXXXXXX)");
    }
    return trimmed;
  }

  void _handleLoginUsers() async {
    hideKeyboard(context);

    String identifier;
    try {
      identifier = _normalizeIdentifier(emailCont.text);
    } catch (e) {
      TopToast.show(message: e.toString(), type: TopToastType.error);
      return;
    }

    Map<String, dynamic> request = {
      'identifier': identifier,
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
      final msg = e.toString();
      if (msg == kPendingApprovalError) {
        _showPendingApprovalSheet();
      } else {
        TopToast.show(message: msg);
      }
    }
  }

  void _showPendingApprovalSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
            ),
            24.height,
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 36),
            ),
            20.height,
            Text('Compte en attente', style: boldTextStyle(size: 18)),
            12.height,
            Text(
              'Votre compte ouvrier est en cours de vérification par notre équipe.\n\nVous recevrez une notification dès que votre compte sera approuvé.',
              style: secondaryTextStyle(size: 14),
              textAlign: TextAlign.center,
            ),
            28.height,
            AppButton(
              width: double.infinity,
              color: primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () => Navigator.pop(context),
              child: Text('Compris', style: boldTextStyle(color: Colors.white, size: 15)),
            ),
          ],
        ),
      ),
    );
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
        TopToast.show(message: e.toString(), type: TopToastType.error);
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
        TopToast.show(message: e.toString(), type: TopToastType.error);
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
      TopToast.show(message: "Your Account signed in successfully.", type: TopToastType.success);
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
      TopToast.show(message: res.message.validate());
    } catch (e) {
      appStore.setLoading(false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
    }
  }

  Future<void> _resetForgotPassword() async {
    hideKeyboard(context);
    if (forgotOtpCont.text.trim().length != OTP_TEXT_FIELD_LENGTH) {
      TopToast.show(message: language.pleaseEnterValidOTP.validate());
      return;
    }
    if (!forgotResetFormKey.currentState!.validate()) return;
    if (forgotNewPasswordCont.text != forgotConfirmPasswordCont.text) {
      TopToast.show(message: language.passwordNotMatch.validate());
      return;
    }
    if (!_isForgotPasswordStrong) {
      TopToast.show(message: 'Le mot de passe ne respecte pas les critères');
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
      TopToast.show(message: res.message.validate());
      if (!mounted) return;
      _recreateForgotControllers(initialEmail: forgotEmail);
      setState(() {
        isForgotPasswordMode = false;
        showForgotOtpStep = false;
      });
      emailCont.text = forgotEmail;
    } catch (e) {
      appStore.setLoading(false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
    }
  }

  Future<void> _resendForgotOtp() async {
    if (forgotEmail.isEmpty) return;
    appStore.setLoading(true);
    try {
      final res = await forgotPassword({'email': forgotEmail});
      appStore.setLoading(false);
      TopToast.show(message: res.message.validate().isNotEmpty
          ? res.message.validate()
          : language.otpSentSuccessfully, type: TopToastType.success);
    } catch (e) {
      appStore.setLoading(false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
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

  InputDecoration _fieldDecoration({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      labelStyle: TextStyle(color: appTextSecondaryColor, fontSize: 16),
      hintStyle: TextStyle(color: appTextSecondaryColor.withValues(alpha: 0.6), fontSize: 16),
      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  Widget _buildTopWidget() {
    return Column(
      children: [
        // Logo badge
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, primaryColor.withValues(alpha: 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.home_work_rounded, color: Colors.white, size: 34),
        ),
        22.height,
        // Brand name
        RichText(
          text: TextSpan(children: [
            TextSpan(
              text: 'Mi',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: appTextPrimaryColor,
                letterSpacing: -1,
              ),
            ),
            TextSpan(
              text: 'son',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: primaryColor,
                letterSpacing: -1,
              ),
            ),
          ]),
        ),
        10.height,
        // Tagline
        Text(
          'Les meilleurs ouvriers, à portée de main.',
          style: secondaryTextStyle(size: 15).copyWith(
            color: appTextSecondaryColor,
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
        ),
        36.height,
      ],
    );
  }

  // ── Forgot password helpers ───────────────────────────────────────────────

  int get _forgotPasswordStrength {
    int s = 0;
    if (_forgotHasMin12Chars) s++;
    if (_forgotHasDigit) s++;
    if (_forgotHasUppercase) s++;
    if (_forgotHasSpecialChar) s++;
    return s;
  }

  Color _forgotStrengthColor(int s) {
    switch (s) {
      case 1: return Colors.redAccent;
      case 2: return Colors.orange;
      case 3: return Colors.amber;
      case 4: return const Color(0xFF4CAF50);
      default: return Colors.transparent;
    }
  }

  Widget _buildForgotStrengthBar() {
    final s = _forgotPasswordStrength;
    final color = _forgotStrengthColor(s);
    final label = ['', 'Très faible', 'Faible', 'Moyen', 'Fort'][s];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          for (int i = 0; i < 4; i++)
            Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: i < s ? color : Colors.black.withValues(alpha: 0.08),
                ),
              ),
            ),
        ]),
        if (s > 0) ...[
          5.height,
          Text(label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ],
    );
  }

  Widget _forgotGradientButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: primaryColor,
          boxShadow: [
            BoxShadow(
                color: primaryColor.withValues(alpha: 0.38),
                blurRadius: 18,
                offset: const Offset(0, 7))
          ],
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.black, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  // ── Forgot password widgets ───────────────────────────────────────────────

  Widget _buildForgotTopWidget() {
    final int step = showForgotOtpStep ? 1 : 0;

    return Column(
      children: [
        // Step indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < 2; i++) ...[
              if (i > 0) 6.width,
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: step == i ? 28 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: step == i
                      ? primaryColor
                      : Colors.black.withValues(alpha: 0.12),
                ),
              ),
            ],
          ],
        ),
        20.height,
        // Lock icon with glow
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withValues(alpha: 0.12),
            border: Border.all(color: primaryColor.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: primaryColor.withValues(alpha: 0.22),
                  blurRadius: 22,
                  spreadRadius: 2)
            ],
          ),
          child: Icon(
            showForgotOtpStep ? Icons.lock_reset_rounded : Icons.lock_outline_rounded,
            color: primaryColor,
            size: 28,
          ),
        ),
        18.height,
        Text(
          showForgotOtpStep ? 'Nouveau mot de passe' : 'Mot de passe oublié',
          style: TextStyle(
              color: appTextPrimaryColor, fontSize: 22, fontWeight: FontWeight.w800),
        ).center(),
        8.height,
        Text(
          showForgotOtpStep
              ? 'Saisissez le code reçu puis définissez votre nouveau mot de passe.'
              : 'Entrez votre adresse email pour recevoir un code de vérification.',
          style: TextStyle(
              color: appTextSecondaryColor, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ).paddingSymmetric(horizontal: 12),
        24.height,
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
            textFieldType: TextFieldType.EMAIL_ENHANCED,
            controller: forgotEmailCont,
            errorThisFieldRequired: language.requiredText,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDecoration(
              label: 'Adresse email',
              hint: 'exemple@email.com',
            ),
            suffix: Icon(Icons.alternate_email_rounded, size: 18,
                    color: appTextSecondaryColor)
                .paddingAll(14),
            isValidationRequired: true,
            validator: (val) {
              if (val == null || val.trim().isEmpty) return language.requiredText;
              return null;
            },
          ),
          22.height,
          _forgotGradientButton(label: language.btnSendOtp, onTap: _sendForgotOtp),
          16.height,
          TextButton(
            onPressed: _backFromForgotFlow,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_new_rounded,
                    size: 14, color: appTextSecondaryColor),
                6.width,
                Text('Retour à la connexion',
                    style: TextStyle(
                        color: appTextSecondaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Email destination chip
          if (forgotEmail.isNotEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: primaryColor.withValues(alpha: 0.08),
                  border: Border.all(
                      color: primaryColor.withValues(alpha: 0.3), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mail_outline_rounded,
                        size: 14, color: primaryColor),
                    6.width,
                    Text(
                      forgotEmail.length > 28
                          ? '${forgotEmail.substring(0, 25)}...'
                          : forgotEmail,
                      style: TextStyle(
                          color: primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          if (forgotEmail.isNotEmpty) 18.height,

          // OTP boxes
          PinCodeTextField(
            appContext: context,
            length: OTP_TEXT_FIELD_LENGTH,
            controller: forgotOtpCont,
            autoDisposeControllers: false,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textStyle: TextStyle(
                color: appTextPrimaryColor, fontSize: 22, fontWeight: FontWeight.w700),
            cursorColor: primaryColor,
            pinTheme: PinTheme(
              shape: PinCodeFieldShape.box,
              borderRadius: BorderRadius.circular(14),
              fieldHeight: 58,
              fieldWidth: 52,
              activeFillColor: Colors.white,
              inactiveFillColor: Colors.white,
              selectedFillColor: Colors.white,
              activeColor: primaryColor,
              inactiveColor: borderColor,
              selectedColor: primaryColor,
            ),
            enableActiveFill: true,
            onChanged: (_) {},
          ),

          // Resend link
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resendForgotOtp,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Renvoyer le code',
                  style: TextStyle(
                      color: primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          16.height,

          // New password
          AppTextField(
            textFieldType: TextFieldType.PASSWORD,
            controller: forgotNewPasswordCont,
            focus: forgotNewPasswordFocus,
            nextFocus: forgotConfirmPasswordFocus,
            errorThisFieldRequired: language.requiredText,
            obscureText: true,
            suffixPasswordVisibleWidget: Icon(Icons.visibility_outlined,
                    size: 18, color: appTextSecondaryColor)
                .paddingAll(14),
            suffixPasswordInvisibleWidget: Icon(Icons.visibility_off_outlined,
                    size: 18, color: appTextSecondaryColor)
                .paddingAll(14),
            decoration: _fieldDecoration(label: language.hintNewPasswordTxt),
            onChanged: (_) => setState(() {}),
            isValidationRequired: true,
            validator: (val) {
              if (val == null || val.trim().isEmpty) return language.requiredText;
              if (!_isForgotPasswordStrong)
                return 'Le mot de passe ne respecte pas les critères';
              return null;
            },
          ),
          if (forgotNewPasswordCont.text.isNotEmpty) ...[
            10.height,
            _buildForgotStrengthBar(),
          ],
          14.height,

          // Confirm password
          AppTextField(
            textFieldType: TextFieldType.PASSWORD,
            controller: forgotConfirmPasswordCont,
            focus: forgotConfirmPasswordFocus,
            errorThisFieldRequired: language.requiredText,
            obscureText: true,
            suffixPasswordVisibleWidget: Icon(Icons.visibility_outlined,
                    size: 18, color: appTextSecondaryColor)
                .paddingAll(14),
            suffixPasswordInvisibleWidget: Icon(Icons.visibility_off_outlined,
                    size: 18, color: appTextSecondaryColor)
                .paddingAll(14),
            decoration: _fieldDecoration(label: 'Confirmer le mot de passe'),
            onChanged: (_) => setState(() {}),
            isValidationRequired: true,
            validator: (val) {
              if (val == null || val.trim().isEmpty) return language.requiredText;
              if (val != forgotNewPasswordCont.text) return language.passwordNotMatch;
              return null;
            },
          ),
          22.height,

          _forgotGradientButton(
              label: language.resetPassword, onTap: _resetForgotPassword),
          14.height,

          // Navigation links
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _backFromForgotFlow,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_ios_new_rounded,
                        size: 11, color: appTextSecondaryColor),
                    5.width,
                    Text('Retour',
                        style: TextStyle(
                            color: appTextSecondaryColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Container(
                  width: 1, height: 14,
                  color: borderColor,
                  margin: const EdgeInsets.symmetric(horizontal: 8)),
              TextButton(
                onPressed: () => setState(() {
                  isForgotPasswordMode = false;
                  showForgotOtpStep = false;
                }),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Connexion',
                    style: TextStyle(
                        color: primaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
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
        10.height,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            RoundedCheckBox(
              borderColor: context.primaryColor,
              checkedColor: context.primaryColor,
              isChecked: isRemember,
              text: language.rememberMe,
              textStyle: secondaryTextStyle(size: 15),
              size: 18,
              onTap: (value) async {
                await setValue(IS_REMEMBERED, isRemember);
                isRemember = !isRemember;
                setState(() {});
              },
            ),
            TextButton(
              onPressed: _openForgotPasswordFlow,
              child: Text(
                language.forgotPassword,
                style: secondaryTextStyle(size: 15, color: primaryColor),
              ),
            ).flexible(),
          ],
        ),
        22.height,
        // Sign In button
        GestureDetector(
          onTap: _handleLogin,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, primaryColor.withValues(alpha: 0.75)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.40),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              language.signIn,
              textAlign: TextAlign.center,
              style: boldTextStyle(color: Colors.white, size: 15),
            ),
          ),
        ),
        20.height,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(language.doNotHaveAccount, style: secondaryTextStyle(size: 15, color: appTextSecondaryColor)),
            TextButton(
              onPressed: () {
                hideKeyboard(context);
                ProfileSelectionScreen().launch(context);
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                language.signUp,
                style: boldTextStyle(size: 15, color: primaryColor),
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

  Widget _socialButton({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            12.width,
            Text(label, style: boldTextStyle(size: 15, color: appTextPrimaryColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialWidget() {
    if (appConfigurationStore.socialLoginStatus) {
      final hasSocial = appConfigurationStore.googleLoginStatus ||
          appConfigurationStore.otpLoginStatus ||
          (isIOS && appConfigurationStore.appleLoginStatus);
      if (!hasSocial) return const Offstage();

      return Column(
        children: [
          24.height,
          Row(
            children: [
              Divider(color: borderColor, thickness: 1).expand(),
              16.width,
              Text(language.lblOrContinueWith,
                  style: secondaryTextStyle(size: 14, color: appTextSecondaryColor)),
              16.width,
              Divider(color: borderColor, thickness: 1).expand(),
            ],
          ),
          20.height,
          if (appConfigurationStore.googleLoginStatus) ...[
            _socialButton(
              icon: const GoogleLogoWidget(size: 18),
              label: language.lblSignInWithGoogle,
              onTap: googleSignIn,
            ),
            12.height,
          ],
          if (appConfigurationStore.otpLoginStatus) ...[
            _socialButton(
              icon: Icon(Icons.phone_rounded, size: 18, color: primaryColor),
              label: language.lblSignInWithOTP,
              onTap: otpSignIn,
            ),
            12.height,
          ],
          if (isIOS && appConfigurationStore.appleLoginStatus) ...[
            _socialButton(
              icon: const Icon(Icons.apple, size: 20, color: appTextPrimaryColor),
              label: language.lblSignInWithApple,
              onTap: appleSign,
            ),
            12.height,
          ],
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
    forgotNewPasswordFocus.dispose();
    forgotConfirmPasswordFocus.dispose();

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
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.black, size: 24),
                  ),
                )
              : (Navigator.of(context).canPop()
                  ? Container(
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        shape: BoxShape.circle,
                      ),
                      child: BackWidget(iconColor: Colors.black))
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
        body: Stack(
          children: [
            // Subtle radial glow — top right
            Positioned(
              top: -80,
              right: -80,
              child: IgnorePointer(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Body(
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
                            decoration: _fieldDecoration(
                              label: 'Identifiant',
                              hint: 'Numéro ou email',
                            ),
                            suffix: Icon(Icons.alternate_email_rounded, size: 18, color: appTextSecondaryColor).paddingAll(14),
                            autoFillHints: [AutofillHints.username],
                            isValidationRequired: true,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return language.requiredText;
                              }
                              final trimmed = val.trim();
                              if (!trimmed.contains('@') &&
                                  !trimmed.startsWith('+')) {
                                final digitsOnly = trimmed.replaceAll(
                                    RegExp(r'[\s\-\(\)]'), '');
                                if (RegExp(r'^\d+$').hasMatch(digitsOnly) &&
                                    digitsOnly.length < 10) {
                                  return "L'indicatif téléphonique est requis (ex: +221...)";
                                }
                              }
                              return null;
                            },
                          ),
                          14.height,
                          AppTextField(
                            textFieldType: TextFieldType.PASSWORD,
                            controller: passwordCont,
                            focus: passwordFocus,
                            obscureText: true,
                            suffixPasswordVisibleWidget:
                                Icon(Icons.visibility_outlined, size: 18, color: appTextSecondaryColor).paddingAll(14),
                            suffixPasswordInvisibleWidget:
                                Icon(Icons.visibility_off_outlined, size: 18, color: appTextSecondaryColor).paddingAll(14),
                            decoration: _fieldDecoration(label: language.hintPasswordTxt),
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
          ],
        ),
      ),
    );
  }
}
