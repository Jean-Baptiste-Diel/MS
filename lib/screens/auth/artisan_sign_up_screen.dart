import 'dart:io';
import 'dart:typed_data';

import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/selected_item_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/auth/otp_verification_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nb_utils/nb_utils.dart';

class ArtisanSignUpScreen extends StatefulWidget {
  const ArtisanSignUpScreen({Key? key}) : super(key: key);

  @override
  State<ArtisanSignUpScreen> createState() => _ArtisanSignUpScreenState();
}

class _ArtisanSignUpScreenState extends State<ArtisanSignUpScreen> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  Country selectedCountry = defaultCountry();

  // Controllers - Champs requis
  TextEditingController fNameCont = TextEditingController();
  TextEditingController lNameCont = TextEditingController();
  TextEditingController emailCont = TextEditingController();
  TextEditingController mobileCont = TextEditingController();
  TextEditingController passwordCont = TextEditingController();

  // Controllers - Champs artisan
  TextEditingController professionCont = TextEditingController();
  TextEditingController experienceYearsCont = TextEditingController();
  TextEditingController hourlyRateCont = TextEditingController();
  TextEditingController dailyRateCont = TextEditingController();
  TextEditingController bioCont = TextEditingController();
  TextEditingController addressCont = TextEditingController();
  TextEditingController cityCont = TextEditingController();

  // Focus nodes
  FocusNode fNameFocus = FocusNode();
  FocusNode lNameFocus = FocusNode();
  FocusNode emailFocus = FocusNode();
  FocusNode mobileFocus = FocusNode();
  FocusNode passwordFocus = FocusNode();
  FocusNode professionFocus = FocusNode();
  FocusNode experienceYearsFocus = FocusNode();
  FocusNode hourlyRateFocus = FocusNode();
  FocusNode dailyRateFocus = FocusNode();
  FocusNode bioFocus = FocusNode();
  FocusNode addressFocus = FocusNode();
  FocusNode cityFocus = FocusNode();

  // Image
  XFile? profileImageFile;
  Uint8List? profileImageBytes;
  final ImagePicker _picker = ImagePicker();

  bool isAcceptedTc = false;
  bool isFirstTimeValidation = true;
  ValueNotifier _valueNotifier = ValueNotifier(true);

  @override
  void initState() {
    super.initState();
    experienceYearsCont.text = '0';
  }

  @override
  void dispose() {
    fNameCont.dispose();
    lNameCont.dispose();
    emailCont.dispose();
    mobileCont.dispose();
    passwordCont.dispose();
    professionCont.dispose();
    experienceYearsCont.dispose();
    hourlyRateCont.dispose();
    dailyRateCont.dispose();
    bioCont.dispose();
    addressCont.dispose();
    cityCont.dispose();
    super.dispose();
  }

  String buildMobileNumber() {
    if (mobileCont.text.isEmpty) {
      return '';
    } else {
      return '+${mobileCont.text.trim().formatPhoneNumber(selectedCountry.phoneCode)}';
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
      showPhoneCode: true,
      onSelect: (Country country) {
        selectedCountry = country;
        setState(() {});
      },
    );
  }

  Future<void> _handleImageSelection(XFile? image) async {
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        profileImageFile = image;
        profileImageBytes = bytes;
      });
    }
  }

  Future<void> pickImage() async {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(language.lblGallery),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                    await _handleImageSelection(image);
                  } catch (e) {
                    log('Error picking image: $e');
                    toast('Erreur lors de la sélection de l\'image');
                  }
                },
              ),
              if (!kIsWeb) // Camera not supported on web
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: Text(language.camera),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
                      await _handleImageSelection(image);
                    } catch (e) {
                      log('Error taking photo: $e');
                      toast('Erreur lors de la prise de photo');
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void registerArtisan() async {
    hideKeyboard(context);

    if (appStore.isLoading) return;

    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();

      if (isAcceptedTc) {
        appStore.setLoading(true);

        Map<String, dynamic> request = {
          'email': emailCont.text.trim(),
          'password': passwordCont.text.trim(),
          'contact_number': buildMobileNumber(),
          'first_name': fNameCont.text.trim(),
          'last_name': lNameCont.text.trim(),
          'profession': professionCont.text.trim(),
          'experience_years': experienceYearsCont.text.trim(),
          'hourly_rate': hourlyRateCont.text.trim(),
          'daily_rate': dailyRateCont.text.trim(),
          'bio': bioCont.text.trim(),
          'address': addressCont.text.trim(),
          'city': cityCont.text.trim(),
        };

        // Préparer le fichier image si sélectionné (pour mobile seulement)
        File? imageFile;
        if (!kIsWeb && profileImageFile != null) {
          imageFile = File(profileImageFile!.path);
        }

        await createArtisan(
          request, 
          profilePicture: imageFile,
          profilePictureBytes: profileImageBytes,
          profilePictureFileName: profileImageFile?.name,
        ).then((response) async {
          appStore.setLoading(false);
          toast(response.message.validate());

          // Rediriger vers l'écran de vérification OTP
          OTPVerificationScreen(
            email: emailCont.text.trim(),
            isFromSignUp: true,
          ).launch(context);
        }).catchError((e) {
          appStore.setLoading(false);
          toast(e.toString());
        });
      } else {
        toast(language.termsConditionsAccept);
      }
    } else {
      isFirstTimeValidation = false;
      setState(() {});
    }
  }

  Widget _buildTopWidget() {
    return Column(
      children: [
        (context.height() * 0.08).toInt().height,
        // Profile picture picker
        GestureDetector(
          onTap: pickImage,
          child: Stack(
            children: [
              Container(
                height: 100,
                width: 100,
                decoration: boxDecorationDefault(
                  shape: BoxShape.circle,
                  color: primaryColor.withValues(alpha: 0.1),
                ),
                child: profileImageBytes != null
                    ? ClipOval(
                        child: Image.memory(
                          profileImageBytes!,
                          fit: BoxFit.cover,
                          width: 100,
                          height: 100,
                        ),
                      )
                    : Icon(
                        Icons.person,
                        size: 50,
                        color: primaryColor,
                      ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: boxDecorationDefault(
                    shape: BoxShape.circle,
                    color: primaryColor,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        16.height,
        Text(language.registerAsArtisan, style: boldTextStyle(size: 22)).center(),
        8.height,
        Text(
          'Créez votre profil artisan pour proposer vos services',
          style: secondaryTextStyle(size: 14),
          textAlign: TextAlign.center,
        ).center().paddingSymmetric(horizontal: 32),
      ],
    );
  }

  Widget _buildFormWidget() {
    return Column(
      children: [
        24.height,
        // Section: Informations personnelles
        _buildSectionTitle('Informations personnelles'),
        16.height,
        Row(
          children: [
            Expanded(
              child: AppTextField(
                textFieldType: TextFieldType.NAME,
                controller: fNameCont,
                focus: fNameFocus,
                nextFocus: lNameFocus,
                errorThisFieldRequired: language.requiredText,
                decoration: inputDecoration(context, labelText: language.hintFirstNameTxt),
                suffix: ic_profile2.iconImage(size: 10).paddingAll(14),
              ),
            ),
            16.width,
            Expanded(
              child: AppTextField(
                textFieldType: TextFieldType.NAME,
                controller: lNameCont,
                focus: lNameFocus,
                nextFocus: emailFocus,
                errorThisFieldRequired: language.requiredText,
                decoration: inputDecoration(context, labelText: language.hintLastNameTxt),
                suffix: ic_profile2.iconImage(size: 10).paddingAll(14),
              ),
            ),
          ],
        ),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.EMAIL_ENHANCED,
          controller: emailCont,
          focus: emailFocus,
          nextFocus: passwordFocus,
          errorThisFieldRequired: language.requiredText,
          decoration: inputDecoration(context, labelText: language.hintEmailTxt),
          suffix: ic_message.iconImage(size: 10).paddingAll(14),
        ),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.PASSWORD,
          controller: passwordCont,
          focus: passwordFocus,
          nextFocus: mobileFocus,
          obscureText: true,
          suffixPasswordVisibleWidget: ic_show.iconImage(size: 10).paddingAll(14),
          suffixPasswordInvisibleWidget: ic_hide.iconImage(size: 10).paddingAll(14),
          errorThisFieldRequired: language.requiredText,
          decoration: inputDecoration(context, labelText: language.hintPasswordTxt),
          validator: (val) {
            if (val == null || val.isEmpty) {
              return language.requiredText;
            } else if (val.length < 8 || val.length > 12) {
              return language.passwordLengthShouldBe;
            }
            return null;
          },
        ),
        16.height,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            AppTextField(
              textFieldType: isAndroid ? TextFieldType.PHONE : TextFieldType.NAME,
              controller: mobileCont,
              focus: mobileFocus,
              nextFocus: professionFocus,
              errorThisFieldRequired: language.requiredText,
              decoration: inputDecoration(context, labelText: language.hintContactNumberTxt).copyWith(
                hintText: '${language.lblExample}: ${selectedCountry.example}',
                hintStyle: secondaryTextStyle(),
              ),
              maxLength: 15,
              suffix: ic_calling.iconImage(size: 10).paddingAll(14),
            ).expand(),
          ],
        ),

        24.height,
        // Section: Informations professionnelles
        _buildSectionTitle('Informations professionnelles'),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.NAME,
          controller: professionCont,
          focus: professionFocus,
          nextFocus: experienceYearsFocus,
          errorThisFieldRequired: language.requiredText,
          decoration: inputDecoration(context, labelText: language.profession),
          suffix: Icon(Icons.work_outline, size: 18, color: appStore.isDarkMode ? Colors.white54 : Colors.grey).paddingAll(14),
        ),
        16.height,
        Row(
          children: [
            Expanded(
              child: AppTextField(
                textFieldType: TextFieldType.PHONE,
                controller: experienceYearsCont,
                focus: experienceYearsFocus,
                nextFocus: hourlyRateFocus,
                isValidationRequired: false,
                decoration: inputDecoration(context, labelText: language.experienceYears),
                suffix: Icon(Icons.timeline, size: 18, color: appStore.isDarkMode ? Colors.white54 : Colors.grey).paddingAll(14),
              ),
            ),
            16.width,
            Expanded(
              child: AppTextField(
                textFieldType: TextFieldType.PHONE,
                controller: hourlyRateCont,
                focus: hourlyRateFocus,
                nextFocus: dailyRateFocus,
                isValidationRequired: false,
                decoration: inputDecoration(context, labelText: '${language.hourlyRate} (FCFA)'),
                suffix: Icon(Icons.attach_money, size: 18, color: appStore.isDarkMode ? Colors.white54 : Colors.grey).paddingAll(14),
              ),
            ),
          ],
        ),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.PHONE,
          controller: dailyRateCont,
          focus: dailyRateFocus,
          nextFocus: bioFocus,
          isValidationRequired: false,
          decoration: inputDecoration(context, labelText: '${language.dailyRate} (FCFA)'),
          suffix: Icon(Icons.attach_money, size: 18, color: appStore.isDarkMode ? Colors.white54 : Colors.grey).paddingAll(14),
        ),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.MULTILINE,
          controller: bioCont,
          focus: bioFocus,
          nextFocus: addressFocus,
          isValidationRequired: false,
          minLines: 3,
          maxLines: 5,
          decoration: inputDecoration(context, labelText: language.bio),
        ),

        24.height,
        // Section: Adresse
        _buildSectionTitle('Adresse'),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.NAME,
          controller: addressCont,
          focus: addressFocus,
          nextFocus: cityFocus,
          isValidationRequired: false,
          decoration: inputDecoration(context, labelText: language.hintAddress),
          suffix: Icon(Icons.location_on_outlined, size: 18, color: appStore.isDarkMode ? Colors.white54 : Colors.grey).paddingAll(14),
        ),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.NAME,
          controller: cityCont,
          focus: cityFocus,
          isValidationRequired: false,
          decoration: inputDecoration(context, labelText: language.city),
          suffix: Icon(Icons.location_city, size: 18, color: appStore.isDarkMode ? Colors.white54 : Colors.grey).paddingAll(14),
        ),

        _buildTcAcceptWidget(),
        8.height,
        AppButton(
          text: language.signUp,
          color: primaryColor,
          textColor: Colors.white,
          width: context.width() - context.navigationBarHeight,
          onTap: registerArtisan,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: primaryColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        8.width,
        Text(title, style: boldTextStyle(size: 16)),
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
            TextSpan(text: '${language.lblAgree} ', style: secondaryTextStyle()),
            TextSpan(
              text: language.lblTermsOfService,
              style: boldTextStyle(color: primaryColor, size: 14),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  checkIfLink(context, appConfigurationStore.termConditions, title: language.termsCondition);
                },
            ),
            TextSpan(text: ' & ', style: secondaryTextStyle()),
            TextSpan(
              text: language.privacyPolicy,
              style: boldTextStyle(color: primaryColor, size: 14),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  checkIfLink(context, appConfigurationStore.privacyPolicy, title: language.privacyPolicy);
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
            TextSpan(text: "${language.alreadyHaveAccountTxt} ", style: secondaryTextStyle()),
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
              child: BackWidget(iconColor: context.iconColor),
            ),
            scrolledUnderElevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarIconBrightness: appStore.isDarkMode ? Brightness.light : Brightness.dark,
              statusBarColor: context.scaffoldBackgroundColor,
            ),
          ),
          body: Stack(
            alignment: AlignmentDirectional.center,
            children: [
              Form(
                key: formKey,
                autovalidateMode: isFirstTimeValidation ? AutovalidateMode.disabled : AutovalidateMode.onUserInteraction,
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
              Observer(builder: (_) => LoaderWidget().center().visible(appStore.isLoading)),
            ],
          ),
        ),
      ),
    );
  }
}
