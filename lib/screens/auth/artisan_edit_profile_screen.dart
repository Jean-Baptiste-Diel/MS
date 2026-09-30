import 'package:booking_system_flutter/utils/image_pick_sizes.dart';
import 'dart:convert';
import 'dart:io';

import 'package:booking_system_flutter/component/mison_country_code_dropdown.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/nominatim_address_field.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:country_picker/country_picker.dart';
import 'package:booking_system_flutter/component/mison_page_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class ArtisanEditProfileScreen extends StatefulWidget {
  const ArtisanEditProfileScreen({Key? key}) : super(key: key);

  @override
  State<ArtisanEditProfileScreen> createState() => _ArtisanEditProfileScreenState();
}

class _ArtisanEditProfileScreenState extends State<ArtisanEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final fNameCont       = TextEditingController();
  final lNameCont       = TextEditingController();
  final mobileCont      = TextEditingController();
  final bioCont         = TextEditingController();
  final experienceCont  = TextEditingController();
  final addressCont     = TextEditingController();

  final fNameFocus  = FocusNode();
  final lNameFocus  = FocusNode();
  final mobileFocus = FocusNode();
  final bioFocus    = FocusNode();

  Country selectedCountry = defaultCountry();
  ValueNotifier phoneNotifier = ValueNotifier(true);

  File? profileImageFile;
  double? addressLat;
  double? addressLon;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    fNameCont.dispose(); lNameCont.dispose();
    mobileCont.dispose(); bioCont.dispose(); experienceCont.dispose(); addressCont.dispose();
    fNameFocus.dispose(); lNameFocus.dispose();
    mobileFocus.dispose(); bioFocus.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    fNameCont.text = appStore.userFirstName;
    lNameCont.text = appStore.userLastName;
    _parsePhone(appStore.userContactNumber);

    try {
      final res = await buildHttpResponse('auth/me', method: HttpMethodType.GET);
      if (!mounted || res.statusCode != 200) return;

      final body = _parseBody(res.body);
      fNameCont.text = body['first_name']?.toString() ?? fNameCont.text;
      lNameCont.text = body['last_name']?.toString() ?? lNameCont.text;
      _parsePhone(body['phone']?.toString() ?? appStore.userContactNumber);

      final artisan = body['artisan'] as Map<String, dynamic>?;
      if (artisan != null) {
        bioCont.text        = artisan['profession_name']?.toString() ?? '';
        addressCont.text    = artisan['address']?.toString() ?? '';
        experienceCont.text = artisan['experience_years']?.toString() ?? '';
      }
      setState(() {});
    } catch (e) {
      log('ArtisanEditProfile load error: $e');
    }
  }

  Map<String, dynamic> _parseBody(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return (decoded['data'] as Map<String, dynamic>?) ?? decoded;
      }
    } catch (_) {}
    return {};
  }

  void _parsePhone(String raw) {
    if (raw.startsWith('+')) {
      final m = RegExp(r'^\+(\d{1,3})\s*(.*)$').firstMatch(raw);
      if (m != null) {
        selectedCountry = Country(
          phoneCode: m.group(1) ?? '221', countryCode: '', e164Sc: 0,
          geographic: true, level: 1, name: '', example: '', displayName: '',
          displayNameNoCountryCode: '', e164Key: '', fullExampleWithPlusSign: '',
        );
        mobileCont.text = (m.group(2) ?? '').replaceAll(RegExp(r'[^\d]'), '');
        phoneNotifier.value = !phoneNotifier.value;
        return;
      }
    }
    mobileCont.text = raw.replaceAll(RegExp(r'[^\d]'), '');
  }

  String get _fullPhone =>
      mobileCont.text.isEmpty ? '' : '+${selectedCountry.phoneCode}${mobileCont.text.trim()}';

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: kProfilePhotoMaxSide,
        maxHeight: kProfilePhotoMaxSide,
        imageQuality: kProfilePhotoQuality);
    if (picked != null) setState(() => profileImageFile = File(picked.path));
  }

  void _showPickDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            4.height,
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: radius(2))),
            16.height,
            ListTile(leading: const Icon(Icons.camera_alt_rounded), title: Text('Caméra', style: primaryTextStyle()),
                onTap: () { finish(context); _pickImage(ImageSource.camera); }),
            ListTile(leading: const Icon(Icons.photo_library_rounded), title: Text('Galerie', style: primaryTextStyle()),
                onTap: () { finish(context); _pickImage(ImageSource.gallery); }),
            16.height,
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    hideKeyboard(context);
    appStore.setLoading(true);

    try {
      final body = await _patchProfile();
      appStore.setLoading(false);

      if (body != null) {
        await setValue(FIRST_NAME, fNameCont.text.trim());
        await setValue(LAST_NAME, lNameCont.text.trim());
        await setValue(CONTACT_NUMBER, _fullPhone);
        appStore.setFirstName(fNameCont.text.trim());
        appStore.setLastName(lNameCont.text.trim());
        appStore.setContactNumber(_fullPhone);

        final photo = body['profile_picture_url']?.toString() ?? body['profile_picture']?.toString() ?? '';
        if (photo.isNotEmpty) await appStore.setUserProfile(photo);

        TopToast.show(message: language.success.validate(), type: TopToastType.success);
        finish(context);
      }
    } catch (e) {
      appStore.setLoading(false);
      TopToast.show(message: e.toString(), type: TopToastType.error);
    }
  }

  Future<Map<String, dynamic>?> _patchProfile({bool retry = false}) async {
    final headers = Map<String, String>.from(buildHeaderTokens())
      ..remove(HttpHeaders.contentTypeHeader);

    final request = http.MultipartRequest('PATCH', buildBaseUrl('auth/me'))
      ..headers.addAll(headers)
      ..fields['first_name'] = fNameCont.text.trim()
      ..fields['last_name']  = lNameCont.text.trim()
      ..fields['phone']      = _fullPhone
      ..fields['profession_name'] = bioCont.text.trim()
      ..fields['address']    = addressCont.text.trim();

    if (experienceCont.text.trim().isNotEmpty)
      request.fields['experience_years'] = experienceCont.text.trim();
    if (addressLat != null) request.fields['latitude']  = addressLat.toString();
    if (addressLon != null) request.fields['longitude'] = addressLon.toString();
    if (profileImageFile != null)
      request.files.add(await http.MultipartFile.fromPath('profile_picture', profileImageFile!.path));

    log('── PATCH auth/me ──────────────────────────');
    log('URL     : ${request.url}');
    log('Headers : ${jsonEncode(request.headers)}');
    log('Fields  : ${jsonEncode(request.fields)}');
    log('Files   : ${request.files.map((f) => f.filename).toList()}');

    final response = await http.Response.fromStream(await request.send());

    log('Status  : ${response.statusCode}');
    log('Body    : ${response.body}');
    log('────────────────────────────────────────────');

    if (response.statusCode == 401 && !retry) {
      log('401 reçu — tentative de refresh token…');
      final refreshed = await refreshToken();
      if (refreshed) return _patchProfile(retry: true);
      return null;
    }

    if (response.statusCode == 200) return _parseBody(response.body);

    TopToast.show(message: 'Erreur ${response.statusCode}');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Logo centré + fond de la page, comme les autres pages
      appBar: MisonAppBar(
        title: 'Modifier mon profil',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kMisonDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: DotGridBackground(
        child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _showPickDialog,
                          child: Container(
                            width: 100, height: 100,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kMisonGold, width: 3)),
                            child: ClipOval(
                              child: profileImageFile != null
                                  ? Image.file(profileImageFile!, fit: BoxFit.cover, width: 100, height: 100)
                                  : CachedImageWidget(url: appStore.userProfileImage, height: 100, width: 100, fit: BoxFit.cover, circle: true),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 2, right: 2,
                          child: GestureDetector(
                            onTap: _showPickDialog,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(shape: BoxShape.circle, color: kMisonGold, border: Border.all(color: Colors.white, width: 2)),
                              child: const Icon(AntDesign.camera, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  28.height,

                  // Prénom
                  AppTextField(
                    textFieldType: TextFieldType.NAME,
                    controller: fNameCont,
                    focus: fNameFocus,
                    nextFocus: lNameFocus,
                    errorThisFieldRequired: language.requiredText,
                    decoration: inputDecoration(context, labelText: language.hintFirstNameTxt),
                  ),
                  16.height,

                  // Nom
                  AppTextField(
                    textFieldType: TextFieldType.NAME,
                    controller: lNameCont,
                    focus: lNameFocus,
                    nextFocus: mobileFocus,
                    errorThisFieldRequired: language.requiredText,
                    decoration: inputDecoration(context, labelText: language.hintLastNameTxt),
                  ),
                  16.height,

                  // Téléphone
                  // Indicatif : liste animée des pays, comme à l'inscription
                  MisonCountryCodeDropdown(
                    selected: selectedCountry,
                    onChanged: (country) => setState(() => selectedCountry = country),
                    fieldBuilder: (context, isOpen, toggle) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MisonCountryCodeButton(
                        country: selectedCountry,
                        isOpen: isOpen,
                        onTap: toggle,
                      ),
                      10.width,
                      Expanded(
                        child: AppTextField(
                          textFieldType: TextFieldType.PHONE,
                          controller: mobileCont,
                          focus: mobileFocus,
                          nextFocus: bioFocus,
                          isValidationRequired: false,
                          maxLength: selectedCountry.phoneCode == '221' ? 9 : 15, // 9 chiffres au Sénégal
                          decoration: inputDecoration(context, hintText: language.hintContactNumberTxt),
                        ),
                      ),
                    ],
                    ),
                  ),
                  16.height,

                  // Bio
                  AppTextField(
                    textFieldType: TextFieldType.MULTILINE,
                    controller: bioCont,
                    focus: bioFocus,
                    isValidationRequired: false,
                    minLines: 3,
                    maxLines: 6,
                    decoration: inputDecoration(context, labelText: 'Bio / Présentation'),
                  ),
                  16.height,

                  // Années d'expérience
                  AppTextField(
                    textFieldType: TextFieldType.PHONE,
                    controller: experienceCont,
                    isValidationRequired: false,
                    decoration: inputDecoration(context, labelText: "Années d'expérience"),
                  ),
                  16.height,

                  // Adresse
                  Text('Adresse', style: secondaryTextStyle(size: 16)),
                  8.height,
                  Container(
                    decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(12)),
                    child: NominatimAddressField(
                      controller: addressCont,
                      hintText: 'Votre adresse...',
                      // Prestataires : adresse dans la région de Dakar (Sénégal).
                      countryCodes: const ['sn'],
                      bbox: kDakarRegionBbox,
                      onSelected: (s) => setState(() { addressLat = s.lat; addressLon = s.lon; }),
                    ),
                  ),
                  if (addressLat != null) ...[
                    6.height,
                    Row(
                      children: [
                        Icon(Icons.gps_fixed_rounded, size: 12, color: Colors.green.shade600),
                        4.width,
                        Text('${addressLat!.toStringAsFixed(4)}, ${addressLon!.toStringAsFixed(4)}',
                            style: secondaryTextStyle(size: 13, color: Colors.green.shade600)),
                      ],
                    ),
                  ],
                  32.height,

                  // Save
                  AppButton(
                    text: 'Enregistrer',
                    color: kMisonGold,
                    textColor: Colors.white,
                    width: context.width(),
                    shapeBorder: RoundedRectangleBorder(borderRadius: radius(12)),
                    onTap: _save,
                  ),
                  24.height,
                ],
              ),
            ),
          ),
          if (appStore.isLoading)
            const Positioned.fill(child: AbsorbPointer(child: MisonPageLoader())),
        ],
        ),
      ),
    );
  }
}
