import 'package:booking_system_flutter/component/loader_widget.dart';
import 'dart:async';

import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/rest_apis.dart' as api;
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/screens/dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:booking_system_flutter/utils/phone_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String? email;
  final String? phone;
  final bool isFromSignUp;

  /// Code secret choisi à l'inscription : gardé comme après une connexion
  /// (changement de code secret, « se souvenir de moi »).
  final String? password;

  const OTPVerificationScreen({
    Key? key,
    this.email,
    this.phone,
    this.isFromSignUp = true,
    this.password,
  })  : assert(email != null || phone != null,
            'email ou phone doit être fourni'),
        super(key: key);

  /// Identifiant utilisé pour envoyer/vérifier l'OTP : email si disponible,
  /// sinon téléphone (inscription sans email).
  bool get _usesEmail => email != null && email!.trim().isNotEmpty;

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  // Mêmes couleurs que les pages connexion / inscription
  static const Color _brandGold = Color(0xFFC49716);

  TextEditingController otpController = TextEditingController();

  /// Numéro de l'inscription : modifiable ici si la personne s'est trompée.
  late String _phone = (widget.phone ?? '').trim();

  String get _target => widget._usesEmail ? widget.email!.trim() : _phone;

  /// Correction du numéro : inscription par téléphone.
  bool get _canChangePhone => widget.isFromSignUp && !widget._usesEmail && _phone.isNotEmpty;

  Timer? _timer;
  int _remainingSeconds = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    otpController.dispose();
    super.dispose();
  }

  void startTimer() {
    _remainingSeconds = 60;
    _canResend = false;
    setState(() {});

    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      }
    });
  }

  Future<void> verifyOtp() async {
    if (otpController.text.length != OTP_TEXT_FIELD_LENGTH) {
      TopToast.show(message: language.pleaseEnterValidOTP.validate());
      return;
    }

    appStore.setLoading(true);

    Map<String, dynamic> request = {
      (widget._usesEmail ? 'email' : 'phone'): _target,
      'otp_code': otpController.text.trim(),
    };

    await api.verifyAccountOtp(request).then((response) async {
      // Client : connecté directement, on arrive sur l'accueil.
      if (response.userData != null && (response.accessToken ?? '').isNotEmpty) {
        await api.saveUserData(response.userData!, refreshToken: response.refreshToken);
        if ((widget.password ?? '').isNotEmpty) await setValue(USER_PASSWORD, widget.password);
        await appStore.setLoginType(LOGIN_TYPE_USER);
        authService.verifyFirebaseUser();
        appStore.setLoading(false);
        TopToast.show(message: response.message ?? language.accountVerifiedSuccessfully, type: TopToastType.success);
        if (!mounted) return;
        DashboardScreen().launch(context, isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
        return;
      }

      // Prestataire : compte à valider par l'équipe MISON avant de se connecter.
      appStore.setLoading(false);
      TopToast.show(message: response.message ?? language.accountVerifiedSuccessfully, type: TopToastType.success);
      if (!mounted) return;
      const SignInScreen(allowHomeNavigation: true).launch(
        context,
        isNewTask: true,
        pageRouteAnimation: PageRouteAnimation.Fade,
      );
    }).catchError((e) {
      appStore.setLoading(false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
    });
  }

  Future<void> resendOtpCode() async {
    if (!_canResend) return;

    appStore.setLoading(true);

    Map<String, dynamic> request = {
      (widget._usesEmail ? 'email' : 'phone'): _target,
    };

    await api.resendOtp(request, purpose: 'verification').then((response) {
      appStore.setLoading(false);
      TopToast.show(message: response.message ?? language.otpSentSuccessfully, type: TopToastType.success);
      startTimer();
    }).catchError((e) {
      appStore.setLoading(false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
    });
  }

  /// « Ce n'est pas le bon numéro ? » : saisie du bon numéro, puis nouveau
  /// code envoyé dessus (le compte de l'inscription est gardé).
  Future<void> _changePhone() async {
    final isSenegal = _phone.startsWith('+221');
    final controller = TextEditingController(text: isSenegal ? _phone.substring(4) : _phone);
    String? error;

    final newPhone = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void submit() {
            final input = controller.text.trim();
            final String? err = isSenegal
                ? validateSenegalPhone(input)
                : (input.startsWith('+') && input.length > 7
                    ? null
                    : "Saisissez le numéro avec l'indicatif (ex : +33 6 12 34 56 78)");
            if (err != null) {
              setSheetState(() => error = err);
              return;
            }
            final phone = isSenegal
                ? buildInternationalPhone(input, phoneCode: '221')
                : '+${input.replaceAll(RegExp(r'[^0-9]'), '')}';
            Navigator.of(sheetContext).pop(phone);
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Modifier le numéro', style: boldTextStyle(size: 18)),
                6.height,
                Text(
                  'Saisissez le bon numéro : un nouveau code vous sera envoyé par SMS.',
                  style: secondaryTextStyle(),
                ),
                16.height,
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  decoration: InputDecoration(
                    prefixText: isSenegal ? '+221 ' : null,
                    hintText: isSenegal ? '77 123 45 67' : '+33 6 12 34 56 78',
                    errorText: error,
                    errorMaxLines: 3,
                    filled: true,
                    fillColor: context.cardColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _brandGold),
                    ),
                  ),
                  onChanged: (_) {
                    if (error != null) setSheetState(() => error = null);
                  },
                  onSubmitted: (_) => submit(),
                ),
                20.height,
                AppButton(
                  text: 'Envoyer le code à ce numéro',
                  color: _brandGold,
                  textColor: Colors.white,
                  width: double.infinity,
                  onTap: submit,
                ),
              ],
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (newPhone == null || newPhone == _phone || !mounted) return;

    appStore.setLoading(true);
    try {
      final saved = await api.changeSignupPhone(
        phone: _phone,
        newPhone: newPhone,
      );
      appStore.setLoading(false);
      if (!mounted) return;
      _timer?.cancel();
      otpController.clear();
      setState(() => _phone = saved);
      startTimer();
      TopToast.show(message: 'Numéro modifié : un nouveau code a été envoyé au $saved', type: TopToastType.success);
    } catch (e) {
      appStore.setLoading(false);
      TopToast.show(
        message: friendlyPhoneError(e.toString(), phoneCode: isSenegal ? '221' : ''),
        type: TopToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: context.scaffoldBackgroundColor,
        leading: BackWidget(),
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness:
              appStore.isDarkMode ? Brightness.light : Brightness.dark,
          statusBarColor: context.scaffoldBackgroundColor,
        ),
      ),
      body: DotGridBackground(
        child: Observer(
        builder: (_) => Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  32.height,
                  // Icon
                  Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      color: _brandGold.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sms_outlined, // code toujours envoyé par SMS
                      size: 40,
                      color: _brandGold,
                    ),
                  ),
                  24.height,
                  // Title
                  Text(
                    language.verifyOTP,
                    style: boldTextStyle(size: 24),
                  ),
                  16.height,
                  // Subtitle
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: secondaryTextStyle(),
                      children: [
                        TextSpan(text: language.enterTheCodeSentTo),
                        TextSpan(text: '\n'),
                        TextSpan(
                          text: widget._usesEmail ? 'votre numéro de téléphone' : _target,
                          style: boldTextStyle(color: _brandGold),
                        ),
                      ],
                    ),
                  ),
                  if (_canChangePhone)
                    TextButton.icon(
                      onPressed: appStore.isLoading ? null : _changePhone,
                      icon: const Icon(Icons.edit_outlined, size: 16, color: _brandGold),
                      label: Text(
                        "Ce n'est pas le bon numéro ? Modifier",
                        style: primaryTextStyle(size: 14, color: _brandGold),
                      ),
                    ),
                  40.height,
                  // OTP Input
                  PinCodeTextField(
                    appContext: context,
                    length: OTP_TEXT_FIELD_LENGTH,
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textStyle: boldTextStyle(size: 20),
                    cursorColor: _brandGold,
                    pinTheme: PinTheme(
                      shape: PinCodeFieldShape.box,
                      borderRadius: BorderRadius.circular(12),
                      fieldHeight: 55,
                      fieldWidth: 50,
                      activeFillColor: context.cardColor,
                      inactiveFillColor: context.cardColor,
                      selectedFillColor: context.cardColor,
                      activeColor: _brandGold,
                      inactiveColor: borderColor,
                      selectedColor: _brandGold,
                    ),
                    enableActiveFill: true,
                    onCompleted: (value) {
                      verifyOtp();
                    },
                    onChanged: (value) {},
                  ),
                  24.height,
                  // Verify Button
                  AppButton(
                    text: language.verify,
                    color: _brandGold,
                    textColor: Colors.white,
                    width: context.width(),
                    onTap: verifyOtp,
                  ),
                  24.height,
                  // Resend OTP
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        language.didNotReceiveCode,
                        style: secondaryTextStyle(),
                      ),
                      8.width,
                      if (_canResend)
                        TextButton(
                          onPressed: () => resendOtpCode(),
                          child: Text(
                            language.resendOTP,
                            style: boldTextStyle(color: _brandGold),
                          ),
                        )
                      else
                        Text(
                          '${language.resendIn} $_remainingSeconds s',
                          style: secondaryTextStyle(color: _brandGold),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (appStore.isLoading)
              Container(
                color: Colors.black26,
                child: Center(
                  child: LoaderWidget(colors: const [Color(0xFF3A3A3A), _brandGold]),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}
