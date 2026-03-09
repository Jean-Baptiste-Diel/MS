import 'dart:async';

import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/rest_apis.dart' as api;
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String email;
  final bool isFromSignUp;

  const OTPVerificationScreen({
    Key? key,
    required this.email,
    this.isFromSignUp = true,
  }) : super(key: key);

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  TextEditingController otpController = TextEditingController();

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
      toast(language.pleaseEnterValidOTP);
      return;
    }

    appStore.setLoading(true);

    Map<String, dynamic> request = {
      'email': widget.email,
      'otp_code': otpController.text.trim(),
    };

    await api.verifyAccountOtp(request).then((response) {
      appStore.setLoading(false);
      toast(response.message ?? language.accountVerifiedSuccessfully);

      const SignInScreen(allowHomeNavigation: true).launch(
        context,
        isNewTask: true,
        pageRouteAnimation: PageRouteAnimation.Fade,
      );
    }).catchError((e) {
      appStore.setLoading(false);
      toast(e.toString());
    });
  }

  Future<void> resendOtpCode() async {
    if (!_canResend) return;

    appStore.setLoading(true);

    Map<String, dynamic> request = {
      'email': widget.email,
    };

    await api.resendOtp(request, purpose: 'verification').then((response) {
      appStore.setLoading(false);
      toast(response.message ?? language.otpSentSuccessfully);
      startTimer();
    }).catchError((e) {
      appStore.setLoading(false);
      toast(e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: Observer(
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
                      color: primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.email_outlined,
                      size: 40,
                      color: primaryColor,
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
                          text: widget.email,
                          style: boldTextStyle(color: primaryColor),
                        ),
                      ],
                    ),
                  ),
                  40.height,
                  // OTP Input
                  PinCodeTextField(
                    appContext: context,
                    length: OTP_TEXT_FIELD_LENGTH,
                    controller: otpController,
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
                    onCompleted: (value) {
                      verifyOtp();
                    },
                    onChanged: (value) {},
                  ),
                  24.height,
                  // Verify Button
                  AppButton(
                    text: language.verify,
                    color: primaryColor,
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
                            style: boldTextStyle(color: primaryColor),
                          ),
                        )
                      else
                        Text(
                          '${language.resendIn} $_remainingSeconds s',
                          style: secondaryTextStyle(color: primaryColor),
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
                  child: CircularProgressIndicator(color: primaryColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
