import 'dart:io';

import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/selected_item_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/user_data_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/auth/otp_verification_screen.dart';
import 'package:booking_system_flutter/services/deep_link_service.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nb_utils/nb_utils.dart';

class SignUpScreen extends StatefulWidget {
  final String? phoneNumber;
  final String? countryCode;
  final bool isOTPLogin;
  final String? uid;
  final int? tokenForOTPCredentials;
  final String? initialAccountType; // 'PARTICULIER' or 'ENTREPRISE'

  SignUpScreen(
      {Key? key,
      this.phoneNumber,
      this.isOTPLogin = false,
      this.countryCode,
      this.uid,
      this.tokenForOTPCredentials,
      this.initialAccountType})
      : super(key: key);

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  Country selectedCountry = defaultCountry();
  final ImagePicker _picker = ImagePicker();

  TextEditingController fNameCont = TextEditingController();
  TextEditingController lNameCont = TextEditingController();
  TextEditingController emailCont = TextEditingController();
  TextEditingController mobileCont = TextEditingController();
  TextEditingController passwordCont = TextEditingController();
  TextEditingController confirmPasswordCont = TextEditingController();
  TextEditingController referralCodeCont = TextEditingController();
  TextEditingController companyNameCont = TextEditingController();

  XFile? profileImageFile;
  Uint8List? profileImageBytes;

  @override
  void dispose() {
    fNameCont.dispose();
    lNameCont.dispose();
    emailCont.dispose();
    mobileCont.dispose();
    passwordCont.dispose();
    confirmPasswordCont.dispose();
    referralCodeCont.dispose();
    companyNameCont.dispose();
    fNameFocus.dispose();
    lNameFocus.dispose();
    emailFocus.dispose();
    mobileFocus.dispose();
    passwordFocus.dispose();
    confirmPasswordFocus.dispose();
    referralCodeFocus.dispose();
    companyNameFocus.dispose();
    super.dispose();
  }

  FocusNode fNameFocus = FocusNode();
  FocusNode lNameFocus = FocusNode();
  FocusNode emailFocus = FocusNode();
  FocusNode mobileFocus = FocusNode();
  FocusNode passwordFocus = FocusNode();
  FocusNode confirmPasswordFocus = FocusNode();
  FocusNode referralCodeFocus = FocusNode();
  FocusNode companyNameFocus = FocusNode();

  // Type de compte: PARTICULIER ou ENTREPRISE
  String selectedAccountType = 'PARTICULIER';

  bool isAcceptedTc = false;
  bool showPromoCodeField = false;

  bool isFirstTimeValidation = true;
  ValueNotifier _valueNotifier = ValueNotifier(true);

  bool? isReferralValid;
  String? referralValidationMessage;

  @override
  void initState() {
    super.initState();
    selectedAccountType = widget.initialAccountType ?? 'PARTICULIER';
    referralCodeCont.addListener(() {
      if (isReferralValid != null || referralValidationMessage != null) {
        setState(() {
          isReferralValid = null;
          referralValidationMessage = null;
        });
      }
    });
    init();
  }

  void init() async {
    if (widget.phoneNumber != null) {
      selectedCountry = Country.parse(
          widget.countryCode.validate(value: selectedCountry.countryCode));

      mobileCont.text =
          widget.phoneNumber != null ? widget.phoneNumber.toString() : "";
      passwordCont.text =
          widget.phoneNumber != null ? widget.phoneNumber.toString() : "";
    }

    // Check for pending referral code from deep link
    final pendingCode = DeepLinkService().getPendingReferralCode();
    if (pendingCode != null && pendingCode.isNotEmpty) {
      referralCodeCont.text = pendingCode;
      setState(() {
        showPromoCodeField = true;
      });
      await _validateReferralCodeIfNeeded();
    }
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  //region Logic
  String buildMobileNumber() {
    if (mobileCont.text.isEmpty) {
      return '';
    } else {
      return '+${mobileCont.text.trim().formatPhoneNumber(selectedCountry.phoneCode)}';
    }
  }

  bool get _hasMin12Chars => passwordCont.text.trim().length >= 12;

  bool get _hasSpecialChar => RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\\/\[\]`~+=;]')
      .hasMatch(passwordCont.text);

  bool get _hasDigit => RegExp(r'\d').hasMatch(passwordCont.text);

  bool get _hasUppercase => RegExp(r'[A-Z]').hasMatch(passwordCont.text);

  bool get _isPasswordStrong =>
      _hasMin12Chars && _hasSpecialChar && _hasDigit && _hasUppercase;

  Future<void> registerWithOTP() async {
    hideKeyboard(context);

    if (appStore.isLoading) return;

    if (formKey.currentState!.validate()) {
      if (!await _validateReferralCodeIfNeeded()) {
        return;
      }

      // Validation: company_name requis si type = ENTREPRISE
      if (selectedAccountType == 'ENTREPRISE' &&
          companyNameCont.text.trim().isEmpty) {
        toast(language.requiredText);
        companyNameFocus.requestFocus();
        return;
      }

      if (isAcceptedTc) {
        formKey.currentState!.save();
        appStore.setLoading(true);

        UserData userResponse = UserData()
          ..username = widget.phoneNumber.validate().trim()
          ..loginType = LOGIN_TYPE_OTP
          ..contactNumber = buildMobileNumber()
          ..email = emailCont.text.trim()
          ..firstName = fNameCont.text.trim()
          ..lastName = lNameCont.text.trim()
          ..userType = USER_TYPE_USER
          ..uid = widget.uid.validate()
          ..password = widget.phoneNumber.validate().trim()
          ..userAccountType = selectedAccountType
          ..companyName = selectedAccountType == 'ENTREPRISE'
              ? companyNameCont.text.trim()
              : null;

        /// Link OTP login with Email Auth
        if (widget.tokenForOTPCredentials != null) {
          try {
            AuthCredential credential = PhoneAuthProvider.credentialFromToken(
                widget.tokenForOTPCredentials!);
            UserCredential userCredential =
                await FirebaseAuth.instance.signInWithCredential(credential);

            AuthCredential emailAuthCredential = EmailAuthProvider.credential(
                email: emailCont.text.trim(),
                password: DEFAULT_FIREBASE_PASSWORD);
            userCredential.user!.linkWithCredential(emailAuthCredential);
          } catch (e) {
            print(e);
          }
        }

        await createUsers(tempRegisterData: userResponse);
      }
    }
  }

  Future<void> changeCountry() async {
    showCountryPicker(
      context: context,
      countryListTheme: CountryListThemeData(
        textStyle: secondaryTextStyle(color: textSecondaryColorGlobal),
        searchTextStyle: primaryTextStyle(),
        inputDecoration: InputDecoration(
          labelText: language.search,
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderSide: BorderSide(
              color: const Color(0xFF8C98A8).withValues(alpha: 0.2),
            ),
          ),
        ),
      ),

      showPhoneCode:
          true, // optional. Shows phone code before the country name.
      onSelect: (Country country) {
        selectedCountry = country;
        setState(() {});
      },
    );
  }

  void registerUser() async {
    hideKeyboard(context);

    if (appStore.isLoading) return;

    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();
      if (!await _validateReferralCodeIfNeeded()) {
        return;
      }

      // Validation: company_name requis si type = ENTREPRISE
      if (selectedAccountType == 'ENTREPRISE' &&
          companyNameCont.text.trim().isEmpty) {
        toast(language.requiredText);
        companyNameFocus.requestFocus();
        return;
      }

      /// If Terms and condition is Accepted then only the user will be registered
      if (isAcceptedTc) {
        appStore.setLoading(true);

        /// Create a temporary request to send
        UserData tempRegisterData = UserData()
          ..contactNumber = buildMobileNumber()
          ..firstName = fNameCont.text.trim()
          ..lastName = lNameCont.text.trim()
          ..userType = USER_TYPE_USER
          ..email = emailCont.text.trim()
          ..password = passwordCont.text.trim()
          ..referral_code = referralCodeCont.text.trim()
          ..userAccountType = selectedAccountType
          ..companyName = selectedAccountType == 'ENTREPRISE'
              ? companyNameCont.text.trim()
              : null;

        createUsers(tempRegisterData: tempRegisterData);
      } else {
        toast(language.termsConditionsAccept);
      }
    } else {
      isFirstTimeValidation = false;
      setState(() {});
    }
  }

  Future<bool> _validateReferralCodeIfNeeded() async {
    final code = referralCodeCont.text.trim();
    if (code.isEmpty) {
      setState(() {
        isReferralValid = null;
        referralValidationMessage = null;
      });
      return true;
    }

    try {
      appStore.setLoading(true);
      final response = await checkReferralCode(code);
      final bool isValid = response.status == true;
      setState(() {
        isReferralValid = isValid;
        referralValidationMessage = response.message.validate().isNotEmpty
            ? response.message
            : (isValid ? 'Referral code is valid' : 'Invalid referral code');
      });
      if (!isValid) {
        referralCodeFocus.requestFocus();
        toast(referralValidationMessage);
      }
      return isValid;
    } catch (e) {
      log(e.toString());
      setState(() {
        isReferralValid = false;
        referralValidationMessage = e.toString();
      });
      referralCodeFocus.requestFocus();
      toast(e.toString());
      return false;
    } finally {
      appStore.setLoading(false);
    }
  }

  Future<void> createUsers({required UserData tempRegisterData}) async {
    File? profilePictureFile;
    if (!kIsWeb && profileImageFile != null) {
      profilePictureFile = File(profileImageFile!.path);
    }

    await createUser(
      tempRegisterData.toJson(),
      profilePicture: profilePictureFile,
      profilePictureBytes: profileImageBytes,
      profilePictureFileName: profileImageFile?.name,
    ).then((registerResponse) async {
      appStore.setLoading(false);
      toast(registerResponse.message.validate());

      // Rediriger vers l'écran de vérification OTP
      OTPVerificationScreen(
        email: emailCont.text.trim(),
        isFromSignUp: true,
      ).launch(context);
    }).catchError((e) {
      appStore.setLoading(false);
      toast(e.toString());
    });
  }

  //endregion

  //region Widget
  String get _headerTitle {
    return selectedAccountType == 'ENTREPRISE'
        ? 'Création de votre compte entreprise'
        : 'Création de votre compte client';
  }

  Future<void> _handleImageSelection(XFile? image) async {
    if (image == null) return;

    final bytes = await image.readAsBytes();
    setState(() {
      profileImageFile = image;
      profileImageBytes = bytes;
    });
  }

  Future<void> pickImage() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Photo de profil', style: boldTextStyle(size: 18)),
                    8.height,
                    Text('Choisissez une source', style: secondaryTextStyle()),
                    16.height,
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: boxDecorationWithRoundedCorners(
                          backgroundColor: primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.photo_library, color: primaryColor),
                      ),
                      title: Text(language.lblGallery),
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          final XFile? image = await _picker.pickImage(
                              source: ImageSource.gallery);
                          await _handleImageSelection(image);
                        } catch (e) {
                          toast('Erreur lors de la sélection');
                        }
                      },
                    ),
                    if (!kIsWeb)
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: boxDecorationWithRoundedCorners(
                            backgroundColor:
                                primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.camera_alt, color: primaryColor),
                        ),
                        title: Text(language.camera),
                        onTap: () async {
                          Navigator.pop(context);
                          try {
                            final XFile? image = await _picker.pickImage(
                                source: ImageSource.camera);
                            await _handleImageSelection(image);
                          } catch (e) {
                            toast('Erreur lors de la prise de photo');
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfilePhotoPicker() {
    final bool hasImage = profileImageBytes != null;

    return Stack(
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withValues(alpha: 0.1),
            border: Border.all(
              color: hasImage ? primaryColor : context.dividerColor,
              width: 1.2,
            ),
          ),
          child: hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(56),
                  child: Image.memory(
                    profileImageBytes!,
                    fit: BoxFit.cover,
                  ),
                )
              : Icon(Icons.person, color: primaryColor, size: 48),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
          ),
        ),
      ],
    ).onTap(pickImage);
  }

  Widget _buildPasswordRule({required String label, required bool isValid}) {
    final bool hasInput = passwordCont.text.isNotEmpty;
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

  Widget _buildPasswordRules() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPasswordRule(
            label: '12 caractères minimum', isValid: _hasMin12Chars),
        4.height,
        _buildPasswordRule(
            label: '1 caractère spécial', isValid: _hasSpecialChar),
        4.height,
        _buildPasswordRule(label: '1 chiffre', isValid: _hasDigit),
        4.height,
        _buildPasswordRule(label: '1 lettre majuscule', isValid: _hasUppercase),
      ],
    );
  }

  Widget _buildTopWidget() {
    return Column(
      children: [
        (context.height() * 0.12).toInt().height,
        Text(_headerTitle,
                style: boldTextStyle(size: 22), textAlign: TextAlign.center)
            .center(),
        16.height,
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildProfilePhotoPicker(),
            14.width,
            Expanded(
              child: Text(
                'Photo claire et récente pour faciliter la vérification.\nTaille conseillée: 512x512 (max 2 Mo).',
                style: secondaryTextStyle(size: 13),
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ).paddingSymmetric(horizontal: 4),
      ],
    );
  }

  Widget _buildFormWidget() {
    return Column(
      children: [
        32.height,
        AppTextField(
          textFieldType: TextFieldType.NAME,
          controller: fNameCont,
          focus: fNameFocus,
          nextFocus: lNameFocus,
          errorThisFieldRequired: language.requiredText,
          decoration:
              inputDecoration(context, labelText: language.hintFirstNameTxt),
          suffix: ic_profile2.iconImage(size: 10).paddingAll(14),
        ),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.NAME,
          controller: lNameCont,
          focus: lNameFocus,
          nextFocus: emailFocus,
          errorThisFieldRequired: language.requiredText,
          decoration:
              inputDecoration(context, labelText: language.hintLastNameTxt),
          suffix: ic_profile2.iconImage(size: 10).paddingAll(14),
        ),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.EMAIL_ENHANCED,
          controller: emailCont,
          focus: emailFocus,
          errorThisFieldRequired: language.requiredText,
          nextFocus: mobileFocus,
          decoration:
              inputDecoration(context, labelText: language.hintEmailTxt),
          suffix: ic_message.iconImage(size: 10).paddingAll(14),
        ),
        16.height,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Country code ...
            Container(
              height: 48.0,
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Center(
                child: ValueListenableBuilder(
                  valueListenable: _valueNotifier,
                  builder: (context, value, child) => Row(
                    children: [
                      Text(
                        "+${selectedCountry.phoneCode}",
                        style: primaryTextStyle(size: 12),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: textSecondaryColorGlobal,
                      )
                    ],
                  ).paddingOnly(left: 8),
                ),
              ),
            ).onTap(() => changeCountry()),
            10.width,
            // Mobile number text field...
            AppTextField(
              textFieldType:
                  isAndroid ? TextFieldType.PHONE : TextFieldType.NAME,
              controller: mobileCont,
              focus: mobileFocus,
              errorThisFieldRequired: language.requiredText,
              nextFocus: selectedAccountType == 'ENTREPRISE'
                  ? companyNameFocus
                  : (widget.isOTPLogin
                      ? (showPromoCodeField ? referralCodeFocus : null)
                      : passwordFocus),
              decoration: inputDecoration(context,
                      labelText: "${language.hintContactNumberTxt}")
                  .copyWith(
                hintText: '${language.lblExample}: ${selectedCountry.example}',
                hintStyle: secondaryTextStyle(),
              ),
              maxLength: 15,
              suffix: ic_calling.iconImage(size: 10).paddingAll(14),
            ).expand(),
          ],
        ),
        16.height,
        // Nom de l'entreprise (visible uniquement si ENTREPRISE)
        if (selectedAccountType == 'ENTREPRISE') ...[
          16.height,
          AppTextField(
            textFieldType: TextFieldType.NAME,
            controller: companyNameCont,
            focus: companyNameFocus,
            nextFocus: widget.isOTPLogin
                ? (showPromoCodeField ? referralCodeFocus : null)
                : passwordFocus,
            errorThisFieldRequired: language.requiredText,
            decoration:
                inputDecoration(context, labelText: "Nom de l'entreprise *"),
            suffix: Icon(Icons.business,
                    size: 18,
                    color: appStore.isDarkMode ? Colors.white : Colors.grey)
                .paddingAll(14),
          ),
        ],
        if (!widget.isOTPLogin) ...[
          16.height,
          AppTextField(
            textFieldType: TextFieldType.PASSWORD,
            controller: passwordCont,
            focus: passwordFocus,
            nextFocus: confirmPasswordFocus,
            obscureText: true,
            onChanged: (_) {
              setState(() {});
            },
            suffixPasswordVisibleWidget:
                ic_show.iconImage(size: 10).paddingAll(14),
            suffixPasswordInvisibleWidget:
                ic_hide.iconImage(size: 10).paddingAll(14),
            errorThisFieldRequired: language.requiredText,
            decoration:
                inputDecoration(context, labelText: language.hintPasswordTxt),
            isValidationRequired: true,
            validator: (val) {
              if (val == null || val.isEmpty) {
                return language.requiredText;
              } else if (!_isPasswordStrong) {
                return 'Le mot de passe ne respecte pas les critères';
              }
              return null;
            },
          ),
          8.height,
          _buildPasswordRules(),
          16.height,
          AppTextField(
            textFieldType: TextFieldType.PASSWORD,
            controller: confirmPasswordCont,
            focus: confirmPasswordFocus,
            nextFocus: showPromoCodeField ? referralCodeFocus : null,
            obscureText: true,
            onChanged: (_) {
              setState(() {});
            },
            suffixPasswordVisibleWidget:
                ic_show.iconImage(size: 10).paddingAll(14),
            suffixPasswordInvisibleWidget:
                ic_hide.iconImage(size: 10).paddingAll(14),
            errorThisFieldRequired: language.requiredText,
            decoration: inputDecoration(context,
                labelText: 'Confirmer le mot de passe'),
            isValidationRequired: true,
            validator: (val) {
              if (val == null || val.isEmpty) return language.requiredText;
              if (val != passwordCont.text) {
                return 'Les mots de passe ne correspondent pas';
              }
              return null;
            },
          ),
        ],
        8.height,
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text("J'ai un code promo", style: primaryTextStyle()),
            8.width,
            Switch(
              value: showPromoCodeField,
              activeThumbColor: primaryColor,
              onChanged: (value) {
                setState(() {
                  showPromoCodeField = value;
                  if (!showPromoCodeField) {
                    referralCodeCont.clear();
                    isReferralValid = null;
                    referralValidationMessage = null;
                  }
                });
              },
            ),
            if (showPromoCodeField) ...[
              8.width,
              Expanded(
                child: AppTextField(
                  textFieldType: TextFieldType.NAME,
                  controller: referralCodeCont,
                  focus: referralCodeFocus,
                  isValidationRequired: false,
                  onChanged: (_) {
                    _validateReferralCodeIfNeeded();
                  },
                  decoration: inputDecoration(
                    context,
                    labelText: "Code promo",
                  ).copyWith(
                    hintText: 'Code promo',
                    hintStyle: secondaryTextStyle(),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (showPromoCodeField &&
            referralValidationMessage.validate().isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              referralValidationMessage!,
              style: primaryTextStyle(
                color: isReferralValid == true ? Colors.green : Colors.red,
                size: 12,
              ),
            ),
          ).paddingTop(4),
        _buildTcAcceptWidget(),
        8.height,
        AppButton(
          text: language.signUp,
          color: primaryColor,
          textColor: Colors.white,
          width: context.width() - context.navigationBarHeight,
          onTap: () {
            if (widget.isOTPLogin) {
              registerWithOTP();
            } else {
              registerUser();
            }
          },
        ),
      ],
    );
  }

  Widget _buildTcAcceptWidget() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SelectedItemWidget(isSelected: isAcceptedTc).onTap(() async {
          isAcceptedTc = !isAcceptedTc;
          setState(() {});
        }),
        16.width,
        RichTextWidget(
          list: [
            TextSpan(
                text: '${language.lblAgree} ', style: secondaryTextStyle()),
            TextSpan(
              text: language.lblTermsOfService,
              style: boldTextStyle(color: primaryColor, size: 14),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  checkIfLink(context, appConfigurationStore.termConditions,
                      title: language.termsCondition);
                },
            ),
            TextSpan(text: ' & ', style: secondaryTextStyle()),
            TextSpan(
              text: language.privacyPolicy,
              style: boldTextStyle(color: primaryColor, size: 14),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  checkIfLink(context, appConfigurationStore.privacyPolicy,
                      title: language.privacyPolicy);
                },
            ),
          ],
        ).flexible(flex: 2),
      ],
    ).paddingSymmetric(vertical: 16);
  }

  Widget _buildFooterWidget() {
    return Column(
      children: [
        16.height,
        RichTextWidget(
          list: [
            TextSpan(
                text: "${language.alreadyHaveAccountTxt} ",
                style: secondaryTextStyle()),
            TextSpan(
              text: language.signIn,
              style: boldTextStyle(color: primaryColor, size: 14),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  finish(context);
                },
            ),
          ],
        ),
        30.height,
      ],
    );
  }

  //endregion

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => hideKeyboard(context),
      child: SafeArea(
        top: false,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: transparentColor,
            leading: Container(
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: BackWidget(iconColor: context.iconColor)),
            scrolledUnderElevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle(
                statusBarIconBrightness:
                    appStore.isDarkMode ? Brightness.light : Brightness.dark,
                statusBarColor: context.scaffoldBackgroundColor),
          ),
          body: Stack(
            alignment: AlignmentDirectional.center,
            children: [
              Form(
                key: formKey,
                autovalidateMode: isFirstTimeValidation
                    ? AutovalidateMode.disabled
                    : AutovalidateMode.onUserInteraction,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildTopWidget(),
                      _buildFormWidget(),
                      8.height,
                      _buildFooterWidget(),
                    ],
                  ),
                ),
              ),
              Observer(
                  builder: (_) =>
                      LoaderWidget().center().visible(appStore.isLoading)),
            ],
          ),
        ),
      ),
    );
  }
}
