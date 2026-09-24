import 'dart:io';

import 'package:booking_system_flutter/component/animated_dropdown.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/user_data_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/auth/otp_verification_screen.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/services/deep_link_service.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/phone_utils.dart';
import 'package:booking_system_flutter/utils/pin_utils.dart';
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
import 'package:booking_system_flutter/utils/top_toast.dart';

class SignUpScreen extends StatefulWidget {
  final String? phoneNumber;
  final String? countryCode;
  final bool isOTPLogin;
  final String? uid;
  final int? tokenForOTPCredentials;
  final String? initialAccountType;

  SignUpScreen({
    Key? key,
    this.phoneNumber,
    this.isOTPLogin = false,
    this.countryCode,
    this.uid,
    this.tokenForOTPCredentials,
    this.initialAccountType,
  }) : super(key: key);

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // Mêmes couleurs que la page connexion
  static const Color _brandGold = Color(0xFFC49716);
  static const Color _brandDark = Color(0xFF3A3A3A);

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

  FocusNode fNameFocus = FocusNode();
  FocusNode lNameFocus = FocusNode();
  FocusNode emailFocus = FocusNode();
  FocusNode mobileFocus = FocusNode();
  FocusNode passwordFocus = FocusNode();
  FocusNode confirmPasswordFocus = FocusNode();
  FocusNode referralCodeFocus = FocusNode();
  FocusNode companyNameFocus = FocusNode();

  XFile? profileImageFile;
  Uint8List? profileImageBytes;

  String selectedAccountType = 'PARTICULIER';
  bool isAcceptedTc = false;
  bool showPromoCodeField = false;
  bool isFirstTimeValidation = true;
  bool _submitPressed = false;

  bool? isReferralValid;
  String? referralValidationMessage;

  /// True dès que la confirmation saisie ne peut plus correspondre au PIN.
  bool get _pinMismatch {
    final pin = passwordCont.text;
    final confirm = confirmPasswordCont.text;
    if (confirm.isEmpty) return false;
    return confirm.length >= pin.length ? confirm != pin : !pin.startsWith(confirm);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    selectedAccountType = widget.initialAccountType ?? 'PARTICULIER';
    referralCodeCont.addListener(() {
      if (isReferralValid != null || referralValidationMessage != null) {
        setState(() { isReferralValid = null; referralValidationMessage = null; });
      }
    });
    init();
  }

  @override
  void dispose() {
    fNameCont.dispose(); lNameCont.dispose(); emailCont.dispose();
    mobileCont.dispose(); passwordCont.dispose(); confirmPasswordCont.dispose();
    referralCodeCont.dispose(); companyNameCont.dispose();
    fNameFocus.dispose(); lNameFocus.dispose(); emailFocus.dispose();
    mobileFocus.dispose(); passwordFocus.dispose(); confirmPasswordFocus.dispose();
    referralCodeFocus.dispose(); companyNameFocus.dispose();
    super.dispose();
  }

  @override
  void setState(fn) { if (mounted) super.setState(fn); }

  // ── Logic (unchanged) ─────────────────────────────────────────────────────

  void init() async {
    if (widget.phoneNumber != null) {
      selectedCountry = Country.parse(
          widget.countryCode.validate(value: selectedCountry.countryCode));
      mobileCont.text = widget.phoneNumber.toString();
      passwordCont.text = widget.phoneNumber.toString();
    }
    final pendingCode = DeepLinkService().getPendingReferralCode();
    if (pendingCode != null && pendingCode.isNotEmpty) {
      referralCodeCont.text = pendingCode;
      setState(() { showPromoCodeField = true; });
      await _validateReferralCodeIfNeeded();
    }
  }

  String buildMobileNumber() {
    if (mobileCont.text.isEmpty) return '';
    return '+${mobileCont.text.trim().formatPhoneNumber(selectedCountry.phoneCode)}';
  }

  Future<void> registerWithOTP() async {
    hideKeyboard(context);
    if (appStore.isLoading) return;
    if (formKey.currentState!.validate()) {
      if (!await _validateReferralCodeIfNeeded()) return;
      if (selectedAccountType == 'ENTREPRISE' && companyNameCont.text.trim().isEmpty) {
        TopToast.show(message: language.requiredText.validate());
        companyNameFocus.requestFocus(); return;
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
          ..companyName = selectedAccountType == 'ENTREPRISE' ? companyNameCont.text.trim() : null;
        if (widget.tokenForOTPCredentials != null && emailCont.text.trim().isNotEmpty) {
          try {
            AuthCredential credential =
                PhoneAuthProvider.credentialFromToken(widget.tokenForOTPCredentials!);
            UserCredential userCredential =
                await FirebaseAuth.instance.signInWithCredential(credential);
            AuthCredential emailAuthCredential = EmailAuthProvider.credential(
                email: emailCont.text.trim(), password: DEFAULT_FIREBASE_PASSWORD);
            userCredential.user!.linkWithCredential(emailAuthCredential);
          } catch (e) { print(e); }
        }
        await createUsers(tempRegisterData: userResponse);
      }
    }
  }

  /// Tous les pays, Sénégal en premier (menu Indicatif).
  late final List<Country> _allCountries = () {
    final list = CountryService().getAll();
    final sn = list.where((c) => c.countryCode == 'SN').toList();
    return [...sn, ...list.where((c) => c.countryCode != 'SN')];
  }();

  String _countryName(Country c) => c.getTranslatedName(context) ?? c.name;

  void registerUser() async {
    hideKeyboard(context);
    if (appStore.isLoading) return;
    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();
      if (!await _validateReferralCodeIfNeeded()) return;
      if (selectedAccountType == 'ENTREPRISE' && companyNameCont.text.trim().isEmpty) {
        TopToast.show(message: language.requiredText.validate());
        companyNameFocus.requestFocus(); return;
      }
      if (isAcceptedTc) {
        appStore.setLoading(true);
        UserData tempRegisterData = UserData()
          ..contactNumber = buildMobileNumber()
          ..firstName = fNameCont.text.trim()
          ..lastName = lNameCont.text.trim()
          ..userType = USER_TYPE_USER
          ..email = emailCont.text.trim()
          ..password = passwordCont.text.trim()
          ..referral_code = referralCodeCont.text.trim()
          ..userAccountType = selectedAccountType
          ..companyName = selectedAccountType == 'ENTREPRISE' ? companyNameCont.text.trim() : null;
        createUsers(tempRegisterData: tempRegisterData);
      } else {
        TopToast.show(message: language.termsConditionsAccept.validate());
      }
    } else {
      isFirstTimeValidation = false;
      setState(() {});
    }
  }

  Future<bool> _validateReferralCodeIfNeeded() async {
    final code = referralCodeCont.text.trim();
    if (code.isEmpty) {
      setState(() { isReferralValid = null; referralValidationMessage = null; });
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
            : (isValid ? 'Code valide' : 'Code invalide');
      });
      if (!isValid) {
        referralCodeFocus.requestFocus();
        TopToast.show(message: referralValidationMessage ?? '');
      }
      return isValid;
    } catch (e) {
      log(e.toString());
      setState(() { isReferralValid = false; referralValidationMessage = e.toString(); });
      referralCodeFocus.requestFocus();
      TopToast.show(message: e.toString(), type: TopToastType.error);
      return false;
    } finally { appStore.setLoading(false); }
  }

  Future<void> createUsers({required UserData tempRegisterData}) async {
    File? profilePictureFile;
    if (!kIsWeb && profileImageFile != null) profilePictureFile = File(profileImageFile!.path);
    await createUser(
      tempRegisterData.toJson(),
      profilePicture: profilePictureFile,
      profilePictureBytes: profileImageBytes,
      profilePictureFileName: profileImageFile?.name,
    ).then((registerResponse) async {
      appStore.setLoading(false);
      TopToast.show(message: registerResponse.message.validate());
      OTPVerificationScreen(
        email: emailCont.text.trim().isNotEmpty ? emailCont.text.trim() : null,
        phone: emailCont.text.trim().isEmpty ? buildMobileNumber() : null,
        isFromSignUp: true,
      ).launch(context);
    }).catchError((e) {
      appStore.setLoading(false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
    });
  }

  Future<void> _handleImageSelection(XFile? image) async {
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() { profileImageFile = image; profileImageBytes = bytes; });
  }

  Future<void> pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Photo de profil',
                  style: TextStyle(
                      color: appTextPrimaryColor, fontSize: 17, fontWeight: FontWeight.w700)),
              6.height,
              Text('Choisissez une source',
                  style: TextStyle(color: appTextSecondaryColor, fontSize: 15)),
              20.height,
              _imageSourceTile(
                icon: Icons.photo_library_outlined,
                label: language.lblGallery,
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _handleImageSelection(
                        await _picker.pickImage(source: ImageSource.gallery));
                  } catch (_) { TopToast.show(message: 'Erreur lors de la sélection'); }
                },
              ),
              if (!kIsWeb) ...[
                12.height,
                _imageSourceTile(
                  icon: Icons.camera_alt_outlined,
                  label: language.camera,
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await _handleImageSelection(
                          await _picker.pickImage(source: ImageSource.camera));
                    } catch (_) { TopToast.show(message: 'Erreur lors de la prise de photo'); }
                  },
                ),
              ],
              16.height,
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageSourceTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cardColor,
          border: Border.all(color: borderColor),
        ),
        child: Row(children: [
          Icon(icon, color: _brandGold, size: 22),
          14.width,
          Text(label,
              style: TextStyle(color: appTextPrimaryColor, fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  // ── Design helpers ────────────────────────────────────────────────────────

  InputDecoration _fieldDecoration({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      labelStyle: TextStyle(color: appTextSecondaryColor, fontSize: 16),
      hintStyle: TextStyle(color: appTextSecondaryColor.withValues(alpha: 0.6), fontSize: 16),
      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 15),
      errorMaxLines: 3, // message affiché en entier
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _brandGold, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent)),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 3, height: 13,
          decoration: BoxDecoration(
              color: _brandGold, borderRadius: BorderRadius.circular(2)),
        ),
        8.width,
        Text(label,
            style: TextStyle(
                color: appTextSecondaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
      ]),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildPhotoSection() {
    final bool hasImage = profileImageBytes != null;
    return Column(children: [
      GestureDetector(
        onTap: pickImage,
        child: Stack(children: [
          // Outer glow ring
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                _brandGold.withValues(alpha: hasImage ? 0.3 : 0.12),
                Colors.transparent,
              ]),
              border: Border.all(
                color: hasImage
                    ? _brandGold.withValues(alpha: 0.6)
                    : borderColor,
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: hasImage
                  ? Image.memory(profileImageBytes!, fit: BoxFit.cover)
                  : Container(
                      color: cardColor,
                      child: Icon(Icons.person_rounded,
                          color: appTextSecondaryColor.withValues(alpha: 0.5), size: 42),
                    ),
            ),
          ),
          // Camera badge
          Positioned(
            right: 0, bottom: 0,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _brandGold,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
            ),
          ),
        ]),
      ),
      8.height,
      Text('Photo de profil',
          style: TextStyle(
              color: appTextSecondaryColor, fontSize: 14)),
      4.height,
      Text('Optionnel',
          style: TextStyle(
              color: _brandGold.withValues(alpha: 0.6), fontSize: 13)),
    ]);
  }

  /// Indicatif (liste animée qui se déplie sous la ligne) + numéro sur la même ligne.
  Widget _buildPhoneRow() {
    return AnimatedDropdown<String>(
      hint: 'Indicatif',
      value: selectedCountry.countryCode,
      options: _allCountries
          .map((c) => DropdownOption(
              c.countryCode, '${c.flagEmoji}  +${c.phoneCode}  ${_countryName(c)}'))
          .toList(),
      accentColor: _brandGold,
      searchable: true,
      searchHint: 'Rechercher un pays ou un indicatif',
      onChanged: (code) => setState(() {
        selectedCountry = CountryService().findByCode(code) ?? selectedCountry;
      }),
      triggerBuilder: (context, _, isOpen, toggle) => _buildPhoneFields(isOpen, toggle),
    );
  }

  Widget _buildPhoneFields(bool isOpen, VoidCallback toggle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: toggle,
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: isOpen ? _brandGold : borderColor,
                  width: isOpen ? 1.5 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${selectedCountry.flagEmoji} +${selectedCountry.phoneCode}',
                    style: TextStyle(
                        color: appTextPrimaryColor, fontSize: 14, fontWeight: FontWeight.w500)),
                2.width,
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more_rounded,
                      color: isOpen ? _brandGold : appTextSecondaryColor, size: 20),
                ),
              ],
            ),
          ),
        ),
        10.width,
        AppTextField(
          textFieldType: isAndroid ? TextFieldType.PHONE : TextFieldType.NAME,
          controller: mobileCont,
          focus: mobileFocus,
          errorThisFieldRequired: language.requiredText,
          nextFocus: selectedAccountType == 'ENTREPRISE'
              ? companyNameFocus
              : (widget.isOTPLogin
                  ? (showPromoCodeField ? referralCodeFocus : null)
                  : passwordFocus),
          decoration: _fieldDecoration(label: language.hintContactNumberTxt).copyWith(
            hintText: '${language.lblExample}: ${selectedCountry.example}',
            hintStyle: TextStyle(color: appTextSecondaryColor.withValues(alpha: 0.6), fontSize: 16),
          ),
          maxLength: selectedCountry.countryCode == 'SN' ? 9 : 15, // 9 chiffres au Sénégal
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          isValidationRequired: true,
          validator: (val) {
            if (val == null || val.trim().isEmpty) return language.requiredText;
            if (selectedCountry.countryCode == 'SN') {
              return validateSenegalPhone(val.trim());
            }
            return null;
          },
          suffix: Icon(Icons.phone_outlined, size: 18, color: appTextSecondaryColor)
              .paddingAll(14),
        ).expand(),
      ],
    );
  }

  Widget _buildPromoRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            showPromoCodeField = !showPromoCodeField;
            if (!showPromoCodeField) {
              referralCodeCont.clear();
              isReferralValid = null;
              referralValidationMessage = null;
            }
          }),
          child: Row(children: [
            Icon(
              showPromoCodeField ? Icons.expand_less_rounded : Icons.local_offer_outlined,
              color: _brandGold, size: 16,
            ),
            8.width,
            Text(
              showPromoCodeField ? 'Masquer le code promo' : 'J\'ai un code promo',
              style: TextStyle(
                  color: _brandGold,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 260),
          sizeCurve: Curves.easeOutCubic,
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              14.height,
              AppTextField(
                textFieldType: TextFieldType.NAME,
                controller: referralCodeCont,
                focus: referralCodeFocus,
                isValidationRequired: false,
                onChanged: (_) => _validateReferralCodeIfNeeded(),
                decoration: _fieldDecoration(label: 'Code promo').copyWith(
                  suffixIcon: isReferralValid == null
                      ? null
                      : Icon(
                          isReferralValid! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: isReferralValid! ? const Color(0xFF4CAF50) : Colors.redAccent,
                          size: 20,
                        ).paddingAll(14),
                ),
              ),
              if (referralValidationMessage != null) ...[
                6.height,
                Text(
                  referralValidationMessage!,
                  style: TextStyle(
                    color: isReferralValid == true
                        ? const Color(0xFF4CAF50)
                        : Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          crossFadeState:
              showPromoCodeField ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        ),
      ],
    );
  }

  Widget _buildTcAcceptWidget() {
    return GestureDetector(
      onTap: () => setState(() => isAcceptedTc = !isAcceptedTc),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 20, height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: isAcceptedTc ? _brandGold : Colors.transparent,
              border: Border.all(
                color: isAcceptedTc
                    ? _brandGold
                    : Colors.black.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: isAcceptedTc
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
                : null,
          ),
          12.width,
          RichTextWidget(
            list: [
              TextSpan(
                  text: "J'accepte les ",
                  style: TextStyle(
                      color: appTextSecondaryColor, fontSize: 15)),
              TextSpan(
                text: language.lblTermsOfService,
                style: TextStyle(
                    color: _brandGold,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => checkIfLink(context,
                      appConfigurationStore.termConditions,
                      title: language.termsCondition),
              ),
              TextSpan(
                  text: ' & ',
                  style: TextStyle(
                      color: appTextSecondaryColor, fontSize: 15)),
              TextSpan(
                text: language.privacyPolicy,
                style: TextStyle(
                    color: _brandGold,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => checkIfLink(
                      context, appConfigurationStore.privacyPolicy,
                      title: language.privacyPolicy),
              ),
            ],
          ).flexible(),
        ],
      ).paddingSymmetric(vertical: 16),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTapDown: (_) => setState(() => _submitPressed = true),
      onTapUp: (_) {
        setState(() => _submitPressed = false);
        if (widget.isOTPLogin) registerWithOTP(); else registerUser();
      },
      onTapCancel: () => setState(() => _submitPressed = false),
      child: AnimatedScale(
        scale: _submitPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _brandGold,
            boxShadow: [
              BoxShadow(
                  color: _brandGold.withValues(alpha: 0.38),
                  blurRadius: 18,
                  offset: const Offset(0, 7))
            ],
          ),
          child: Center(
            child: Text(
              language.signUp,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterWidget() {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 32),
      child: Center(
        child: GestureDetector(
          onTap: () => SignInScreen().launch(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: RichText(
              text: TextSpan(children: [
                TextSpan(
                    text: '${language.alreadyHaveAccountTxt} ',
                    style: TextStyle(
                        color: appTextSecondaryColor, fontSize: 16)),
                TextSpan(
                  text: language.signIn,
                  style: TextStyle(
                      color: _brandGold,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: formKey,
      autovalidateMode: AutovalidateMode.disabled, // erreurs affichées seulement au clic sur le bouton
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar ────────────────────────────────────────────────
            28.height,
            Center(child: _buildPhotoSection()),
            32.height,

            // ── Identité ──────────────────────────────────────────────
            _sectionLabel('VOTRE IDENTITÉ'),
            AppTextField(
              textFieldType: TextFieldType.NAME,
              controller: fNameCont,
              focus: fNameFocus,
              nextFocus: lNameFocus,
              errorThisFieldRequired: language.requiredText,
              decoration: _fieldDecoration(label: language.hintFirstNameTxt),
              suffix: Icon(Icons.person_outline_rounded, size: 18,
                      color: appTextSecondaryColor)
                  .paddingAll(14),
            ),
            14.height,
            AppTextField(
              textFieldType: TextFieldType.NAME,
              controller: lNameCont,
              focus: lNameFocus,
              nextFocus: emailFocus,
              errorThisFieldRequired: language.requiredText,
              decoration: _fieldDecoration(label: language.hintLastNameTxt),
              suffix: Icon(Icons.person_outline_rounded, size: 18,
                      color: appTextSecondaryColor)
                  .paddingAll(14),
            ),
            26.height,

            // ── Coordonnées ───────────────────────────────────────────
            _sectionLabel('COORDONNÉES'),
            AppTextField(
              textFieldType: TextFieldType.EMAIL_ENHANCED,
              controller: emailCont,
              focus: emailFocus,
              nextFocus: mobileFocus,
              isValidationRequired: false,
              decoration: _fieldDecoration(
                  label: '${language.hintEmailTxt} (optionnel)',
                  hint: 'exemple@email.com'),
              suffix: Icon(Icons.alternate_email_rounded, size: 18,
                      color: appTextSecondaryColor)
                  .paddingAll(14),
            ),
            14.height,
            _buildPhoneRow(),
            if (selectedAccountType == 'ENTREPRISE') ...[
              14.height,
              AppTextField(
                textFieldType: TextFieldType.NAME,
                controller: companyNameCont,
                focus: companyNameFocus,
                nextFocus: widget.isOTPLogin
                    ? (showPromoCodeField ? referralCodeFocus : null)
                    : passwordFocus,
                errorThisFieldRequired: language.requiredText,
                decoration: _fieldDecoration(label: "Nom de l'entreprise"),
                suffix: Icon(Icons.business_outlined, size: 18,
                        color: appTextSecondaryColor)
                    .paddingAll(14),
              ),
            ],
            26.height,

            // ── Sécurité ──────────────────────────────────────────────
            if (!widget.isOTPLogin) ...[
              _sectionLabel('SÉCURITÉ'),
              AppTextField(
                textFieldType: TextFieldType.PASSWORD,
                controller: passwordCont,
                focus: passwordFocus,
                nextFocus: confirmPasswordFocus,
                obscureText: true,
                keyboardType: pinKeyboardType,
                inputFormatters: pinInputFormatters,
                onChanged: (_) => setState(() {}),
                suffixPasswordVisibleWidget:
                    Icon(Icons.visibility_outlined, size: 18,
                            color: appTextSecondaryColor)
                        .paddingAll(14),
                suffixPasswordInvisibleWidget:
                    Icon(Icons.visibility_off_outlined, size: 18,
                            color: appTextSecondaryColor)
                        .paddingAll(14),
                errorThisFieldRequired: language.requiredText,
                decoration: _fieldDecoration(label: 'Code PIN (4 chiffres)'),
                isValidationRequired: true,
                validator: validatePin,
              ),
              14.height,
              AppTextField(
                textFieldType: TextFieldType.PASSWORD,
                controller: confirmPasswordCont,
                focus: confirmPasswordFocus,
                nextFocus: showPromoCodeField ? referralCodeFocus : null,
                obscureText: true,
                keyboardType: pinKeyboardType,
                inputFormatters: pinInputFormatters,
                onChanged: (_) => setState(() {}),
                suffixPasswordVisibleWidget:
                    Icon(Icons.visibility_outlined, size: 18,
                            color: appTextSecondaryColor)
                        .paddingAll(14),
                suffixPasswordInvisibleWidget:
                    Icon(Icons.visibility_off_outlined, size: 18,
                            color: appTextSecondaryColor)
                        .paddingAll(14),
                errorThisFieldRequired: language.requiredText,
                // Seule erreur affichée pendant la saisie : PIN différents
                decoration: _fieldDecoration(label: 'Confirmer le code PIN').copyWith(
                  errorText: _pinMismatch ? 'Les codes PIN ne correspondent pas' : null,
                ),
                isValidationRequired: true,
                validator: (val) =>
                    validatePinConfirmation(val, passwordCont.text),
              ),
              26.height,
            ],

            // ── Code promo ────────────────────────────────────────────
            _buildPromoRow(),
            20.height,

            // ── T&C + Submit ──────────────────────────────────────────
            _buildTcAcceptWidget(),
            4.height,
            _buildSubmitButton(),
            _buildFooterWidget(),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar() {
    final String title = selectedAccountType == 'ENTREPRISE'
        ? 'Compte Entreprise'
        : 'Créer un compte';

    return SliverAppBar(
      pinned: true,
      expandedHeight: 220,
      backgroundColor: const Color(0xFFF1F2F4),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        statusBarColor: Colors.transparent,
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded,
            color: Colors.black, size: 24),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: SizedBox(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 4, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand row
                  Row(children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(colors: [
                          _brandGold,
                          _brandGold.withValues(alpha: 0.65)
                        ]),
                        boxShadow: [
                          BoxShadow(
                              color: _brandGold.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: const Icon(Icons.home_work_rounded,
                          color: Colors.white, size: 18),
                    ),
                    12.width,
                    RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: 'Mi',
                          style: TextStyle(
                              color: _brandDark,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5),
                        ),
                        TextSpan(
                          text: 'son',
                          style: TextStyle(
                              color: _brandGold,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5),
                        ),
                      ]),
                    ),
                  ]),
                  18.height,
                  Text(
                    title,
                    style: TextStyle(
                        color: appTextPrimaryColor,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -0.4),
                  ),
                  8.height,
                  Text(
                    'Rejoignez le réseau Mison',
                    style: TextStyle(
                        color: appTextSecondaryColor,
                        fontSize: 14,
                        height: 1.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => hideKeyboard(context),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F2F4),
        extendBodyBehindAppBar: true,
        body: DotGridBackground(
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(child: _buildForm()),
                ],
              ),
              Observer(
                builder: (_) =>
                    LoaderWidget(colors: const [_brandDark, _brandGold]).center().visible(appStore.isLoading),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
