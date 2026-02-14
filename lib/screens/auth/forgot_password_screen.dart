import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/model_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../main.dart';

class ForgotPasswordScreen extends StatefulWidget {
  @override
  ForgotPasswordScreenState createState() => ForgotPasswordScreenState();
}

class ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  TextEditingController emailCont = TextEditingController();
  TextEditingController otpCont = TextEditingController();
  TextEditingController newPasswordCont = TextEditingController();
  TextEditingController confirmPasswordCont = TextEditingController();
  
  GlobalKey<FormState> formKey = GlobalKey<FormState>();
  GlobalKey<FormState> resetFormKey = GlobalKey<FormState>();
  
  bool _showOtpStep = false;
  String _email = '';

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    //
  }

  /// Step 1: Send OTP to email
  Future<void> sendOtp() async {
    hideKeyboard(context);

    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();
      appStore.setLoading(true);

      Map req = {
        UserKeys.email: emailCont.text.validate(),
      };

      forgotPassword(req).then((res) {
        appStore.setLoading(false);
        if (mounted) {
          _email = emailCont.text.validate();
          setState(() {
            _showOtpStep = true;
          });
          toast(res.message.validate());
        }
      }).catchError((e) {
        toast(e.toString(), print: true);
      }).whenComplete(() {
        if (mounted) appStore.setLoading(false);
      });
    }
  }

  /// Step 2: Reset password with OTP
  Future<void> resetPwd() async {
    hideKeyboard(context);

    // Validation manuelle du code OTP
    if (otpCont.text.length != 6) {
      toast(language.pleaseEnterValidOTP);
      return;
    }

    if (resetFormKey.currentState!.validate()) {
      if (newPasswordCont.text != confirmPasswordCont.text) {
        toast(language.passwordNotMatch);
        return;
      }
      
      resetFormKey.currentState!.save();
      appStore.setLoading(true);

      Map req = {
        'email': _email,
        'otp_code': otpCont.text.validate(),
        'new_password': newPasswordCont.text.validate(),
      };

      resetPassword(req).then((res) {
        appStore.setLoading(false);
        if (mounted) {
          finish(context);
          toast(res.message.validate());
        }
      }).catchError((e) {
        toast(e.toString(), print: true);
      }).whenComplete(() {
        if (mounted) appStore.setLoading(false);
      });
    }
  }

  /// Resend OTP
  Future<void> resendOtpCode() async {
    appStore.setLoading(true);

    Map req = {
      UserKeys.email: _email,
    };

    forgotPassword(req).then((res) {
      appStore.setLoading(false);
      toast(language.otpSentSuccessfully);
    }).catchError((e) {
      toast(e.toString(), print: true);
    }).whenComplete(() => appStore.setLoading(false));
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  @override
  void dispose() {
    emailCont.dispose();
    otpCont.dispose();
    newPasswordCont.dispose();
    confirmPasswordCont.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _showOtpStep ? _buildOtpResetStep() : _buildEmailStep();
  }

  /// Step 1: Email input
  Widget _buildEmailStep() {
    return Form(
      autovalidateMode: AutovalidateMode.onUserInteraction,
      key: formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              width: context.width(),
              decoration: boxDecorationDefault(
                color: context.primaryColor,
                borderRadius: radiusOnly(topRight: defaultRadius, topLeft: defaultRadius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(language.forgotPassword, style: boldTextStyle(color: Colors.white)),
                  IconButton(
                    onPressed: () {
                      finish(context);
                    },
                    icon: Icon(Icons.clear, color: Colors.white, size: 20),
                  )
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${language.hintEmailAddressTxt}", style: boldTextStyle()),
                6.height,
                Text(language.lblForgotPwdSubtitle, style: secondaryTextStyle()),
                24.height,
                Observer(
                  builder: (_) => AppTextField(
                    textFieldType: TextFieldType.EMAIL_ENHANCED,
                    controller: emailCont,
                    autoFocus: true,
                    errorThisFieldRequired: language.requiredText,
                    decoration: inputDecoration(context, labelText: language.hintEmailTxt),
                  ).visible(!appStore.isLoading, defaultWidget: Loader()),
                ),
                16.height,
                AppButton(
                  text: language.btnSendOtp,
                  color: primaryColor,
                  textColor: Colors.white,
                  width: context.width() - context.navigationBarHeight,
                  onTap: () {
                    sendOtp();
                  },
                ),
              ],
            ).paddingAll(16),
          ],
        ),
      ),
    );
  }

  /// Step 2: OTP + New Password input
  Widget _buildOtpResetStep() {
    return Form(
      autovalidateMode: AutovalidateMode.onUserInteraction,
      key: resetFormKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              width: context.width(),
              decoration: boxDecorationDefault(
                color: context.primaryColor,
                borderRadius: radiusOnly(topRight: defaultRadius, topLeft: defaultRadius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _showOtpStep = false;
                          });
                        },
                        icon: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                      Text(language.resetPassword, style: boldTextStyle(color: Colors.white)),
                    ],
                  ),
                  IconButton(
                    onPressed: () {
                      finish(context);
                    },
                    icon: Icon(Icons.clear, color: Colors.white, size: 20),
                  )
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${language.enterTheCodeSentTo} $_email', style: secondaryTextStyle()),
                24.height,
                
                // OTP Input
                Observer(
                  builder: (_) => PinCodeTextField(
                    appContext: context,
                    length: 6,
                    controller: otpCont,
                    keyboardType: TextInputType.number,
                    animationType: AnimationType.fade,
                    pinTheme: PinTheme(
                      shape: PinCodeFieldShape.box,
                      borderRadius: BorderRadius.circular(8),
                      fieldHeight: 50,
                      fieldWidth: 45,
                      activeFillColor: context.cardColor,
                      inactiveFillColor: context.cardColor,
                      selectedFillColor: context.cardColor,
                      activeColor: primaryColor,
                      inactiveColor: context.dividerColor,
                      selectedColor: primaryColor,
                    ),
                    enableActiveFill: true,
                    onChanged: (value) {},
                  ).visible(!appStore.isLoading, defaultWidget: Loader()),
                ),
                
                // Resend OTP
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(language.didNotReceiveCode, style: secondaryTextStyle()),
                    TextButton(
                      onPressed: () => resendOtpCode(),
                      child: Text(language.resendOTP, style: boldTextStyle(color: primaryColor)),
                    ),
                  ],
                ),
                
                16.height,
                
                // New Password
                Text(language.hintNewPasswordTxt, style: boldTextStyle()),
                8.height,
                Observer(
                  builder: (_) => AppTextField(
                    textFieldType: TextFieldType.PASSWORD,
                    controller: newPasswordCont,
                    errorThisFieldRequired: language.requiredText,
                    decoration: inputDecoration(context, labelText: language.hintNewPasswordTxt),
                  ).visible(!appStore.isLoading, defaultWidget: SizedBox()),
                ),
                
                16.height,
                
                // Confirm Password
                Text(language.hintReenterPasswordTxt, style: boldTextStyle()),
                8.height,
                Observer(
                  builder: (_) => AppTextField(
                    textFieldType: TextFieldType.PASSWORD,
                    controller: confirmPasswordCont,
                    errorThisFieldRequired: language.requiredText,
                    decoration: inputDecoration(context, labelText: language.hintReenterPasswordTxt),
                    validator: (value) {
                      if (value != newPasswordCont.text) {
                        return language.passwordNotMatch;
                      }
                      return null;
                    },
                  ).visible(!appStore.isLoading, defaultWidget: SizedBox()),
                ),
                
                24.height,
                
                AppButton(
                  text: language.resetPassword,
                  color: primaryColor,
                  textColor: Colors.white,
                  width: context.width() - context.navigationBarHeight,
                  onTap: () {
                    resetPwd();
                  },
                ),
              ],
            ).paddingAll(16),
          ],
        ),
      ),
    );
  }
}

