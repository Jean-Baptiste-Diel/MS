import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/model_keys.dart';
import 'package:booking_system_flutter/utils/pin_utils.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../main.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class ForgotPasswordScreen extends StatefulWidget {
  @override
  ForgotPasswordScreenState createState() => ForgotPasswordScreenState();
}

class ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  TextEditingController emailCont = TextEditingController();
  TextEditingController mobileCont = TextEditingController();
  TextEditingController otpCont = TextEditingController();
  TextEditingController newPasswordCont = TextEditingController();
  TextEditingController confirmPasswordCont = TextEditingController();

  FocusNode newPasswordFocus = FocusNode();
  FocusNode confirmPasswordFocus = FocusNode();

  GlobalKey<FormState> formKey = GlobalKey<FormState>();
  GlobalKey<FormState> resetFormKey = GlobalKey<FormState>();

  // Choix du canal de réception du code : email ou téléphone (SMS)
  bool _useEmail = true;
  Country selectedCountry = defaultCountry();

  bool _showOtpStep = false;
  String _identity = '';

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    //
  }

  /// Construit +indicatif+numéro, ex: +221771234567
  String buildMobileNumber() {
    if (mobileCont.text.isEmpty) return '';
    return '+${mobileCont.text.trim().formatPhoneNumber(selectedCountry.phoneCode)}';
  }

  /// Step 1: Send OTP by email or phone (SMS)
  Future<void> sendOtp() async {
    hideKeyboard(context);

    if (!_useEmail && mobileCont.text.trim().isEmpty) {
      TopToast.show(message: language.requiredText.validate());
      return;
    }

    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();
      appStore.setLoading(true);

      // Capture l'identité (email ou numéro) avant l'appel asynchrone
      final identity = _useEmail ? emailCont.text.validate() : buildMobileNumber();

      Map req = _useEmail
          ? {UserKeys.email: identity}
          : {UserKeys.phone: identity};

      try {
        final res = await forgotPassword(req);
        appStore.setLoading(false);
        if (mounted) {
          _identity = identity;
          setState(() {
            _showOtpStep = true;
          });
          TopToast.show(message: res.message.validate());
        }
      } catch (e) {
        TopToast.show(message: e.toString(), type: TopToastType.error);
        if (mounted) appStore.setLoading(false);
      }
    }
  }

  /// Step 2: Reset password with OTP
  Future<void> resetPwd() async {
    hideKeyboard(context);

    // Validation manuelle du code OTP
    if (!mounted) return;
    if (otpCont.text.length != 6) {
      TopToast.show(message: language.pleaseEnterValidOTP.validate());
      return;
    }

    if (resetFormKey.currentState!.validate()) {
      if (!mounted) return;
      if (newPasswordCont.text != confirmPasswordCont.text) {
        TopToast.show(message: language.passwordNotMatch.validate());
        return;
      }
      
      resetFormKey.currentState!.save();
      appStore.setLoading(true);

      // Capture values before async operation
      final otpCode = otpCont.text.validate();
      final newPassword = newPasswordCont.text.validate();

      Map req = {
        (_useEmail ? UserKeys.email : UserKeys.phone): _identity,
        'otp_code': otpCode,
        'new_password': newPassword,
      };

      try {
        final res = await resetPassword(req);
        appStore.setLoading(false);
        TopToast.show(message: res.message.validate());
        if (mounted) {
          finish(context);
        }
      } catch (e) {
        TopToast.show(message: e.toString(), type: TopToastType.error);
        if (mounted) appStore.setLoading(false);
      }
    }
  }

  /// Resend OTP
  Future<void> resendOtpCode() async {
    appStore.setLoading(true);

    Map req = {
      (_useEmail ? UserKeys.email : UserKeys.phone): _identity,
    };

    try {
      await forgotPassword(req);
      if (mounted) appStore.setLoading(false);
      TopToast.show(message: language.otpSentSuccessfully.validate(), type: TopToastType.success);
    } catch (e) {
      TopToast.show(message: e.toString(), type: TopToastType.error);
      if (mounted) appStore.setLoading(false);
    }
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  @override
  void dispose() {
    emailCont.dispose();
    mobileCont.dispose();
    otpCont.dispose();
    newPasswordCont.dispose();
    confirmPasswordCont.dispose();
    newPasswordFocus.dispose();
    confirmPasswordFocus.dispose();
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
                16.height,

                // Choix du canal : email ou téléphone (SMS)
                Row(
                  children: [
                    Expanded(
                      child: _ChannelToggleButton(
                        label: language.hintEmailTxt,
                        icon: Icons.alternate_email_rounded,
                        isSelected: _useEmail,
                        onTap: () => setState(() => _useEmail = true),
                      ),
                    ),
                    10.width,
                    Expanded(
                      child: _ChannelToggleButton(
                        label: language.hintContactNumberTxt,
                        icon: Icons.phone_outlined,
                        isSelected: !_useEmail,
                        onTap: () => setState(() => _useEmail = false),
                      ),
                    ),
                  ],
                ),
                24.height,

                if (_useEmail)
                  Observer(
                    builder: (_) => AppTextField(
                      textFieldType: TextFieldType.EMAIL_ENHANCED,
                      controller: emailCont,
                      autoFocus: true,
                      errorThisFieldRequired: language.requiredText,
                      decoration: inputDecoration(context, labelText: language.hintEmailTxt),
                    ).visible(!appStore.isLoading, defaultWidget: Loader()),
                  )
                else
                  Observer(
                    builder: (_) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => showCountryPicker(
                            context: context,
                            showPhoneCode: true,
                            onSelect: (Country country) => setState(() => selectedCountry = country),
                          ),
                          child: Container(
                            height: 58,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: context.cardColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: context.dividerColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('+${selectedCountry.phoneCode}', style: primaryTextStyle(size: 16)),
                                const Icon(Icons.expand_more_rounded, size: 18),
                              ],
                            ),
                          ),
                        ),
                        10.width,
                        Expanded(
                          child: AppTextField(
                            textFieldType: isAndroid ? TextFieldType.PHONE : TextFieldType.NAME,
                            controller: mobileCont,
                            maxLength: 15,
                            decoration: inputDecoration(context, labelText: language.hintContactNumberTxt),
                          ),
                        ),
                      ],
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
                Text('${language.enterTheCodeSentTo} $_identity', style: secondaryTextStyle()),
                24.height,
                
                // OTP Input
                Observer(
                  builder: (_) => PinCodeTextField(
                    appContext: context,
                    length: 6,
                    controller: otpCont,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
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
                Text('Nouveau code PIN (4 chiffres)', style: boldTextStyle()),
                8.height,
                Observer(
                  builder: (_) => AppTextField(
                    textFieldType: TextFieldType.PASSWORD,
                    controller: newPasswordCont,
                    focus: newPasswordFocus,
                    nextFocus: confirmPasswordFocus,
                    errorThisFieldRequired: language.requiredText,
                    keyboardType: pinKeyboardType,
                    inputFormatters: pinInputFormatters,
                    decoration: inputDecoration(context, labelText: 'Nouveau code PIN'),
                    validator: validatePin,
                  ).visible(!appStore.isLoading, defaultWidget: SizedBox()),
                ),

                16.height,

                // Confirm Password
                Text('Confirmer le code PIN', style: boldTextStyle()),
                8.height,
                Observer(
                  builder: (_) => AppTextField(
                    textFieldType: TextFieldType.PASSWORD,
                    controller: confirmPasswordCont,
                    focus: confirmPasswordFocus,
                    errorThisFieldRequired: language.requiredText,
                    keyboardType: pinKeyboardType,
                    inputFormatters: pinInputFormatters,
                    decoration: inputDecoration(context, labelText: 'Confirmer le code PIN'),
                    validator: (value) =>
                        validatePinConfirmation(value, newPasswordCont.text),
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

/// Bouton de bascule email / téléphone
class _ChannelToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChannelToggleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : context.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? primaryColor : context.dividerColor,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : primaryColor),
            6.width,
            Flexible(
              child: Text(
                label,
                style: boldTextStyle(color: isSelected ? Colors.white : null, size: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

