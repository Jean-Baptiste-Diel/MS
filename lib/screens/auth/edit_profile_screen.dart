import 'dart:convert';
import 'dart:io';

import 'package:booking_system_flutter/component/base_scaffold_widget.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:booking_system_flutter/component/custom_image_picker.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:nb_utils/nb_utils.dart';

class EditProfileScreen extends StatefulWidget {
  @override
  EditProfileScreenState createState() => EditProfileScreenState();
}

class EditProfileScreenState extends State<EditProfileScreen> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  File? imageFile;
  XFile? pickedFile;

  TextEditingController fNameCont = TextEditingController();
  TextEditingController lNameCont = TextEditingController();
  TextEditingController mobileCont = TextEditingController();
  TextEditingController companyNameCont = TextEditingController();

  FocusNode fNameFocus = FocusNode();
  FocusNode lNameFocus = FocusNode();
  FocusNode mobileFocus = FocusNode();
  FocusNode companyNameFocus = FocusNode();

  bool get isEntreprise => getStringAsync(ACCOUNT_TYPE) == 'ENTREPRISE';

  ValueNotifier valueNotifier = ValueNotifier(true);

  Country selectedCountryCode = defaultCountry();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    // Pré-remplissage immédiat depuis le cache
    fNameCont.text = appStore.userFirstName;
    lNameCont.text = appStore.userLastName;
    companyNameCont.text = getStringAsync(COMPANY_NAME);

    // Charger les données fraîches depuis GET /api/auth/me
    try {
      final uri = Uri.parse('$DOMAIN_URL/api/auth/me');
      final response = await http.get(uri, headers: {'Authorization': 'Bearer ${appStore.token}'});
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (!mounted) return;
        fNameCont.text = body['first_name']?.toString() ?? fNameCont.text;
        lNameCont.text = body['last_name']?.toString() ?? lNameCont.text;

        // company_name et type sont dans body['client']
        final client = body['client'] as Map<String, dynamic>?;
        if (client != null) {
          final accountType = client['type']?.toString() ?? '';
          await setValue(ACCOUNT_TYPE, accountType);
          final company = client['company_name']?.toString() ?? '';
          if (company.isNotEmpty) {
            await setValue(COMPANY_NAME, company);
            companyNameCont.text = company;
          }
          setState(() {}); // rafraîchir isEntreprise
        }

        _parsePhone(body['phone']?.toString() ?? '');
      }
    } catch (e) {
      log('EditProfile init error: $e');
      // Fallback : utiliser le numéro du cache
      _parsePhone(appStore.userContactNumber.trim());
    }
  }

  void _parsePhone(String raw) {
    if (raw.startsWith('+')) {
      final re = RegExp(r'^\+(\d{1,3})\s*(.*)$');
      final m = re.firstMatch(raw);
      if (m != null) {
        final callingCode = m.group(1) ?? '';
        final local = (m.group(2) ?? '').replaceAll(RegExp(r'[^\d]'), '');
        selectedCountryCode = Country(
          phoneCode: callingCode,
          countryCode: '',
          e164Sc: 0,
          geographic: true,
          level: 1,
          name: '',
          example: '',
          displayName: '',
          displayNameNoCountryCode: '',
          e164Key: '',
          fullExampleWithPlusSign: '',
        );
        mobileCont.text = local.isNotEmpty ? local : raw.replaceAll(RegExp(r'[^\d]'), '');
        valueNotifier.value = !valueNotifier.value;
        setState(() {});
        return;
      }
    }
    mobileCont.text = raw.replaceAll(RegExp(r'[^\d]'), '');
    setState(() {});
  }

  String buildMobileNumber() {
    if (mobileCont.text.isEmpty) return '';
    return '+${selectedCountryCode.phoneCode}${mobileCont.text.trim()}';
  }

  Future<void> update() async {
    if (!formKey.currentState!.validate()) return;
    hideKeyboard(context);
    appStore.setLoading(true);

    try {
      final uri = Uri.parse('$DOMAIN_URL/api/auth/me');
      final request = http.MultipartRequest('PATCH', uri)
        ..headers['Authorization'] = 'Bearer ${appStore.token}'
        ..fields['first_name'] = fNameCont.text.trim()
        ..fields['last_name'] = lNameCont.text.trim()
        ..fields['phone'] = buildMobileNumber();

      if (isEntreprise && companyNameCont.text.trim().isNotEmpty) {
        request.fields['company_name'] = companyNameCont.text.trim();
      }

      if (imageFile != null) {
        request.files.add(await http.MultipartFile.fromPath('profile_picture', imageFile!.path));
      }

      log('update() → PATCH $uri');
      log('update() → fields: ${request.fields}');
      log('update() → files: ${request.files.map((f) => f.filename).toList()}');

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      appStore.setLoading(false);

      log('update() ← status: ${response.statusCode}');
      log('update() ← body: ${response.body}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;

        // Mettre à jour les valeurs locales
        await setValue(FIRST_NAME, fNameCont.text.trim());
        await setValue(LAST_NAME, lNameCont.text.trim());
        await setValue(CONTACT_NUMBER, buildMobileNumber());
        if (isEntreprise) await setValue(COMPANY_NAME, companyNameCont.text.trim());

        appStore.setFirstName(fNameCont.text.trim());
        appStore.setLastName(lNameCont.text.trim());
        appStore.setContactNumber(buildMobileNumber());

        // Mettre à jour la photo de profil si retournée par le back
        final newPhoto = body['profile_picture']?.toString() ?? body['profile_image']?.toString() ?? '';
        if (newPhoto.isNotEmpty) {
          await appStore.setUserProfile(newPhoto);
          log('update() ← nouvelle photo: $newPhoto');
        }

        toast(language.success);
        finish(context);
      } else {
        log('update() ${response.statusCode}: ${response.body}');
        toast('Erreur ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      appStore.setLoading(false);
      log('update() exception: $e');
      toast(e.toString(), print: true);
    }
  }

  void _getFromGallery() async {
    pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1800, maxHeight: 1800);
    if (pickedFile != null) {
      imageFile = File(pickedFile!.path);
      setState(() {});
    }
  }

  void _getFromCamera() async {
    pickedFile = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1800, maxHeight: 1800);
    if (pickedFile != null) {
      imageFile = File(pickedFile!.path);
      setState(() {});
    }
  }

  void _showImgPickDialog(BuildContext context) {
    showInDialog(
      context,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      title: Text(language.chooseAction, style: boldTextStyle()),
      builder: (p0) => const FilePickerDialog(isSelected: false),
    ).then((file) {
      if (file == GalleryFileTypes.CAMERA) _getFromCamera();
      else if (file == GalleryFileTypes.GALLERY) _getFromGallery();
    });
  }

  void _changeCountryCode() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      countryListTheme: CountryListThemeData(
        textStyle: secondaryTextStyle(color: textSecondaryColorGlobal),
        searchTextStyle: primaryTextStyle(),
        inputDecoration: InputDecoration(
          labelText: language.search,
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
        ),
      ),
      onSelect: (Country country) {
        selectedCountryCode = country;
        valueNotifier.value = !valueNotifier.value;
        setState(() {});
      },
    );
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showLoader: false,
      appBarTitle: language.editProfile,
      child: Observer(
        builder: (_) => Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar
                      Stack(
                        children: [
                          Container(
                            decoration: boxDecorationDefault(
                              border: Border.all(
                                  color: context.scaffoldBackgroundColor,
                                  width: 4),
                              shape: BoxShape.circle,
                            ),
                            child: imageFile != null
                                ? Image.file(imageFile!,
                                        width: 85,
                                        height: 85,
                                        fit: BoxFit.cover)
                                    .cornerRadiusWithClipRRect(40)
                                : Observer(
                                    builder: (_) => CachedImageWidget(
                                      url: appStore.userProfileImage,
                                      height: 85,
                                      width: 85,
                                      fit: BoxFit.cover,
                                      radius: 43,
                                    ),
                                  ),
                          ),
                          Positioned(
                            bottom: 4,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: boxDecorationWithRoundedCorners(
                                boxShape: BoxShape.circle,
                                backgroundColor: primaryColor,
                                border: Border.all(color: Colors.white),
                              ),
                              child: const Icon(AntDesign.camera,
                                  color: Colors.white, size: 12),
                            ).onTap(() => _showImgPickDialog(context)),
                          ),
                        ],
                      ),
                      24.height,
                      // Prénom
                      AppTextField(
                        textFieldType: TextFieldType.NAME,
                        controller: fNameCont,
                        focus: fNameFocus,
                        nextFocus: lNameFocus,
                        errorThisFieldRequired: language.requiredText,
                        decoration: inputDecoration(context,
                            labelText: language.hintFirstNameTxt),
                        suffix:
                            ic_profile2.iconImage(size: 10).paddingAll(14),
                      ),
                      16.height,
                      // Nom
                      AppTextField(
                        textFieldType: TextFieldType.NAME,
                        controller: lNameCont,
                        focus: lNameFocus,
                        nextFocus: mobileFocus,
                        errorThisFieldRequired: language.requiredText,
                        decoration: inputDecoration(context,
                            labelText: language.hintLastNameTxt),
                        suffix:
                            ic_profile2.iconImage(size: 10).paddingAll(14),
                      ),
                      16.height,
                      // Téléphone
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            height: 48,
                            margin: EdgeInsets.only(
                                bottom: context.height() * 0.032),
                            decoration: BoxDecoration(
                              color: context.cardColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ValueListenableBuilder(
                              valueListenable: valueNotifier,
                              builder: (_, __, ___) => Row(
                                children: [
                                  Text(
                                      '+${selectedCountryCode.phoneCode}',
                                      style: primaryTextStyle(size: 12)),
                                  const Icon(Icons.arrow_drop_down),
                                ],
                              ).paddingOnly(left: 8),
                            ),
                          ).onTap(_changeCountryCode),
                          10.width,
                          Expanded(
                            child: AppTextField(
                              textFieldType: isAndroid
                                  ? TextFieldType.PHONE
                                  : TextFieldType.NAME,
                              controller: mobileCont,
                              focus: mobileFocus,
                              isValidationRequired: false,
                              maxLength: 15,
                              decoration: inputDecoration(context,
                                      hintText:
                                          language.hintContactNumberTxt)
                                  .copyWith(
                                      hintStyle: secondaryTextStyle()),
                              suffix: ic_calling
                                  .iconImage(size: 10)
                                  .paddingAll(14),
                            ),
                          ),
                        ],
                      ),
                      if (isEntreprise) ...[
                        16.height,
                        AppTextField(
                          textFieldType: TextFieldType.NAME,
                          controller: companyNameCont,
                          focus: companyNameFocus,
                          isValidationRequired: false,
                          decoration: inputDecoration(context,
                              labelText: 'Nom de l\'entreprise'),
                          suffix: const Icon(Icons.business_outlined,
                                  size: 18)
                              .paddingAll(14),
                        ),
                      ],
                      40.height,
                      AppButton(
                        text: language.save,
                        color: primaryColor,
                        textColor: white,
                        width: context.width() - context.navigationBarHeight,
                        onTap: () => ifNotTester(() => update()),
                      ),
                      24.height,
                    ],
                  ),
                ),
              ),
            ),
            if (appStore.isLoading)
              const Positioned.fill(
                child: AbsorbPointer(
                  absorbing: true,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
