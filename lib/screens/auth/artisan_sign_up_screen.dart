import 'dart:io';
import 'dart:typed_data';

import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/auth/otp_verification_screen.dart';
import 'package:booking_system_flutter/services/location_service.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

class ArtisanSignUpScreen extends StatefulWidget {
  const ArtisanSignUpScreen({Key? key}) : super(key: key);

  @override
  State<ArtisanSignUpScreen> createState() => _ArtisanSignUpScreenState();
}

class _ArtisanSignUpScreenState extends State<ArtisanSignUpScreen>
    with TickerProviderStateMixin {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  Country selectedCountry = defaultCountry();

  late PageController _pageController;
  late AnimationController _progressAnimationController;
  final ScrollController _scrollController = ScrollController();

  TextEditingController fNameCont = TextEditingController();
  TextEditingController lNameCont = TextEditingController();
  TextEditingController emailCont = TextEditingController();
  TextEditingController mobileCont = TextEditingController();
  TextEditingController passwordCont = TextEditingController();
  TextEditingController professionCont = TextEditingController();
  TextEditingController bioCont = TextEditingController();
  TextEditingController addressCont = TextEditingController();

  FocusNode fNameFocus = FocusNode();
  FocusNode lNameFocus = FocusNode();
  FocusNode emailFocus = FocusNode();
  FocusNode mobileFocus = FocusNode();
  FocusNode passwordFocus = FocusNode();
  FocusNode bioFocus = FocusNode();

  XFile? profileImageFile;
  Uint8List? profileImageBytes;
  XFile? identityFile;
  Uint8List? identityBytes;
  XFile? professionProofFile;
  Uint8List? professionProofBytes;
  final ImagePicker _picker = ImagePicker();

  List<Map<String, String>> serviceOptions = [];
  bool isLoadingServices = false;
  String? selectedServiceId;

  int currentStep = 0;
  final int totalSteps = 3;

  bool isAcceptedTc = false;
  bool isFirstTimeValidation = true;
  bool _obscurePassword = true;

  double? addressLat;
  double? addressLon;
  bool isLoadingLocation = false;

  Map<String, String?> fieldErrors = {};

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    fetchServices();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    fNameCont.dispose();
    lNameCont.dispose();
    emailCont.dispose();
    mobileCont.dispose();
    passwordCont.dispose();
    professionCont.dispose();
    bioCont.dispose();
    addressCont.dispose();
    _pageController.dispose();
    _progressAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────────

  Future<void> _fetchCurrentLocation() async {
    if (kIsWeb) return;
    setState(() => isLoadingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => isLoadingLocation = false);
        return;
      }
      final Position position = await getUserLocationPosition();
      final String address = await buildFullAddressFromLatLong(
          position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          addressCont.text = address;
          addressLat = position.latitude;
          addressLon = position.longitude;
          isLoadingLocation = false;
        });
        toast('Localisation détectée automatiquement');
      }
    } catch (e) {
      log('Erreur localisation: $e');
      if (mounted) setState(() => isLoadingLocation = false);
    }
  }

  Future<void> fetchServices() async {
    setState(() => isLoadingServices = true);
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (appStore.token.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${appStore.token}';
      }
      final uri = Uri.parse('https://api.mison.app/api/services');
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final List<dynamic>? data = body['data'] as List<dynamic>?;
        serviceOptions = data
                ?.map((e) => {
                      'id': e['id']?.toString() ?? '',
                      'name': e['name']?.toString() ?? '',
                      'icon': e['icon']?.toString() ?? '',
                    })
                .toList() ??
            [];
      }
    } catch (e) {
      log('Error fetching services: $e');
    } finally {
      setState(() => isLoadingServices = false);
    }
  }

  String buildMobileNumber() {
    if (mobileCont.text.isEmpty) return '';
    return '+${selectedCountry.phoneCode}${mobileCont.text.trim().replaceAll(' ', '')}';
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
            borderSide:
                BorderSide(color: const Color(0xFF8C98A8).withValues(alpha: 0.2)),
          ),
        ),
      ),
      showPhoneCode: true,
      onSelect: (Country country) => setState(() => selectedCountry = country),
    );
  }

  // ── Image pickers ─────────────────────────────────────────────────────────

  Future<void> _handleImageSelection(XFile? image) async {
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        profileImageFile = image;
        profileImageBytes = bytes;
      });
    }
  }

  Future<void> _handleIdentitySelection(XFile? file) async {
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        identityFile = file;
        identityBytes = bytes;
      });
    }
  }

  Future<void> _handleProfessionProofSelection(XFile? file) async {
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        professionProofFile = file;
        professionProofBytes = bytes;
      });
    }
  }

  void _pickFromSheet(String title, Function(XFile?) onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet(
        title: title,
        onGallery: () async {
          Navigator.pop(context);
          final f = await _picker.pickImage(source: ImageSource.gallery);
          onSelect(f);
        },
        onCamera: kIsWeb
            ? null
            : () async {
                Navigator.pop(context);
                final f = await _picker.pickImage(source: ImageSource.camera);
                onSelect(f);
              },
      ),
    );
  }

  Future<void> pickImage() async =>
      _pickFromSheet('Photo de profil', _handleImageSelection);
  Future<void> pickIdentityDocument() async =>
      _pickFromSheet('Pièce d\'identité', _handleIdentitySelection);
  Future<void> pickProfessionProof() async =>
      _pickFromSheet('Preuve de profession', _handleProfessionProofSelection);

  // ── Validation ────────────────────────────────────────────────────────────

  bool validateStep(int step) {
    fieldErrors.clear();
    switch (step) {
      case 0:
        bool v = true;
        if (fNameCont.text.trim().isEmpty) {
          fieldErrors['firstName'] = 'Prénom requis';
          v = false;
        }
        if (lNameCont.text.trim().isEmpty) {
          fieldErrors['lastName'] = 'Nom requis';
          v = false;
        }
        if (emailCont.text.trim().isEmpty) {
          fieldErrors['email'] = 'Email requis';
          v = false;
        } else if (!emailCont.text.trim().validateEmail()) {
          fieldErrors['email'] = 'Email invalide';
          v = false;
        }
        if (passwordCont.text.trim().isEmpty) {
          fieldErrors['password'] = 'Mot de passe requis';
          v = false;
        } else if (passwordCont.text.length < 8) {
          fieldErrors['password'] = language.passwordLengthShouldBe;
          v = false;
        }
        if (mobileCont.text.trim().isEmpty) {
          fieldErrors['mobile'] = 'Téléphone requis';
          v = false;
        } else if (mobileCont.text.trim().length < 6) {
          fieldErrors['mobile'] = 'Numéro trop court';
          v = false;
        }
        setState(() {});
        return v;

      case 1:
        bool v = true;
        if (selectedServiceId == null || selectedServiceId!.isEmpty) {
          fieldErrors['service'] = 'Veuillez sélectionner un service';
          v = false;
        }
        if (bioCont.text.trim().isEmpty) {
          fieldErrors['bio'] = 'Bio requise';
          v = false;
        } else if (bioCont.text.length < 20) {
          fieldErrors['bio'] = 'Minimum 20 caractères';
          v = false;
        }
        if (addressCont.text.trim().isEmpty) {
          fieldErrors['address'] = 'Adresse requise';
          v = false;
        }
        setState(() {});
        return v;

      case 2:
        bool v = true;
        if (profileImageFile == null &&
            (profileImageBytes == null || profileImageBytes!.isEmpty)) {
          fieldErrors['profileImage'] = 'Photo de profil requise';
          v = false;
        }
        if (identityFile == null &&
            (identityBytes == null || identityBytes!.isEmpty)) {
          fieldErrors['identity'] = 'Pièce d\'identité requise';
          v = false;
        }
        if (!isAcceptedTc) {
          fieldErrors['terms'] = language.termsConditionsAccept;
          v = false;
        }
        setState(() {});
        return v;

      default:
        return false;
    }
  }

  void nextStep() {
    HapticFeedback.lightImpact();
    if (validateStep(currentStep)) {
      if (currentStep < totalSteps - 1) {
        setState(() => currentStep++);
        _pageController.animateToPage(currentStep,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic);
        _scrollToTop();
      } else {
        registerArtisan();
      }
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  void previousStep() {
    HapticFeedback.lightImpact();
    if (currentStep > 0) {
      setState(() => currentStep--);
      _pageController.animateToPage(currentStep,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic);
      _scrollToTop();
    }
  }

  void _scrollToTop() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _goToStep(int step) {
    if (step < currentStep || validateStep(currentStep)) {
      HapticFeedback.selectionClick();
      setState(() => currentStep = step);
      _pageController.animateToPage(step,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic);
      _scrollToTop();
    }
  }

  void registerArtisan() async {
    hideKeyboard(context);
    if (appStore.isLoading) return;
    if (!validateStep(2)) return;
    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();
      appStore.setLoading(true);
      Map<String, dynamic> request = {
        'email': emailCont.text.trim(),
        'password': passwordCont.text.trim(),
        'phone': buildMobileNumber(),
        'first_name': fNameCont.text.trim(),
        'last_name': lNameCont.text.trim(),
        'service': selectedServiceId != null && selectedServiceId!.isNotEmpty
            ? selectedServiceId!.trim()
            : professionCont.text.trim(),
        'bio': bioCont.text.trim(),
        'address': addressCont.text.trim(),
      };
      File? profilePictureFile;
      if (!kIsWeb && profileImageFile != null) {
        profilePictureFile = File(profileImageFile!.path);
      }
      File? identityDocumentFile;
      if (!kIsWeb && identityFile != null) {
        identityDocumentFile = File(identityFile!.path);
      }
      File? professionProofDocumentFile;
      if (!kIsWeb && professionProofFile != null) {
        professionProofDocumentFile = File(professionProofFile!.path);
      }
      await createArtisan(
        request,
        profilePicture: profilePictureFile,
        profilePictureBytes: profileImageBytes,
        profilePictureFileName: profileImageFile?.name,
        identityDocument: identityDocumentFile,
        identityDocumentBytes: identityBytes,
        identityDocumentFileName: identityFile?.name,
        professionProof: professionProofDocumentFile,
        professionProofBytes: professionProofBytes,
        professionProofFileName: professionProofFile?.name,
      ).then((response) async {
        appStore.setLoading(false);
        toast(response.message.validate());
        OTPVerificationScreen(
          email: emailCont.text.trim(),
          isFromSignUp: true,
        ).launch(context);
      }).catchError((e) {
        appStore.setLoading(false);
        toast(e.toString());
      });
    } else {
      isFirstTimeValidation = false;
      setState(() {});
    }
  }

  // ── Step titles ───────────────────────────────────────────────────────────

  String _getStepTitle(int index) {
    switch (index) {
      case 0: return 'Personnel';
      case 1: return 'Professionnel';
      case 2: return 'Documents';
      default: return '';
    }
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Widget _fieldError(String key) {
    final e = fieldErrors[key];
    if (e == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5, left: 2),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 13, color: Colors.red),
          4.width,
          Text(e, style: const TextStyle(color: Colors.red, fontSize: 11.5)),
        ],
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint, Widget? prefix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: secondaryTextStyle(size: 13),
      hintStyle: secondaryTextStyle(size: 13),
      prefixIcon: prefix,
      filled: true,
      fillColor: context.cardColor,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: Colors.grey.withValues(alpha: 0.15), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  // ── Step indicator ────────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Container(
      padding: EdgeInsets.only(
        left: 20, right: 20,
        top: MediaQuery.of(context).padding.top + 56,
        bottom: 20,
      ),
      decoration: BoxDecoration(
        color: context.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0.1, 0), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: Text(
              'Étape ${currentStep + 1}/$totalSteps · ${_getStepTitle(currentStep)}',
              key: ValueKey(currentStep),
              style: boldTextStyle(size: 15, color: primaryColor),
            ),
          ),
          14.height,
          Row(
            children: List.generate(totalSteps, (i) {
              final done = i < currentStep;
              final current = i == currentStep;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _goToStep(i),
                  child: Container(
                    margin: EdgeInsets.only(
                        left: i == 0 ? 0 : 4,
                        right: i == totalSteps - 1 ? 0 : 4),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: current ? 34 : 26,
                          height: current ? 34 : 26,
                          decoration: BoxDecoration(
                            color: done || current
                                ? primaryColor
                                : Colors.grey.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                            boxShadow: current
                                ? [BoxShadow(color: primaryColor.withValues(alpha: 0.35), blurRadius: 8)]
                                : null,
                          ),
                          child: Center(
                            child: done
                                ? const Icon(Icons.check, color: Colors.white, size: 14)
                                : Text('${i + 1}',
                                    style: boldTextStyle(
                                        size: current ? 13 : 11,
                                        color: done || current
                                            ? Colors.white
                                            : textSecondaryColorGlobal)),
                          ),
                        ),
                        6.height,
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          height: 3,
                          decoration: BoxDecoration(
                            color: done || current
                                ? primaryColor
                                : Colors.grey.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        4.height,
                        Text(_getStepTitle(i),
                            style: secondaryTextStyle(
                                size: 10,
                                color: done || current
                                    ? primaryColor
                                    : textSecondaryColorGlobal),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Personnel ─────────────────────────────────────────────────────

  Widget _buildPersonalInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Prénom + Nom
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: fNameCont,
                    focusNode: fNameFocus,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => lNameFocus.requestFocus(),
                    style: primaryTextStyle(),
                    decoration: _dec('Prénom *'),
                    onChanged: (_) => setState(() => fieldErrors.remove('firstName')),
                  ),
                  _fieldError('firstName'),
                ],
              ),
            ),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: lNameCont,
                    focusNode: lNameFocus,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => emailFocus.requestFocus(),
                    style: primaryTextStyle(),
                    decoration: _dec('Nom *'),
                    onChanged: (_) => setState(() => fieldErrors.remove('lastName')),
                  ),
                  _fieldError('lastName'),
                ],
              ),
            ),
          ],
        ),
        20.height,

        // Email
        TextField(
          controller: emailCont,
          focusNode: emailFocus,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => passwordFocus.requestFocus(),
          style: primaryTextStyle(),
          decoration: _dec('Adresse email *',
              prefix: Icon(Icons.mail_outline_rounded,
                  size: 20, color: textSecondaryColorGlobal)),
          onChanged: (_) => setState(() => fieldErrors.remove('email')),
        ),
        _fieldError('email'),
        20.height,

        // Mot de passe
        TextField(
          controller: passwordCont,
          focusNode: passwordFocus,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => mobileFocus.requestFocus(),
          style: primaryTextStyle(),
          decoration: _dec('Mot de passe *',
              prefix: Icon(Icons.lock_outline_rounded,
                  size: 20, color: textSecondaryColorGlobal)).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
                color: textSecondaryColorGlobal,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onChanged: (_) => setState(() => fieldErrors.remove('password')),
        ),
        _fieldError('password'),
        20.height,

        // Téléphone
        Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: fieldErrors['mobile'] != null
                  ? Colors.red
                  : Colors.grey.withValues(alpha: 0.15),
              width: fieldErrors['mobile'] != null ? 1 : 1,
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: changeCountry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Colors.grey.withValues(alpha: 0.18)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('+${selectedCountry.phoneCode}',
                          style: primaryTextStyle(size: 14)),
                      4.width,
                      Icon(Icons.arrow_drop_down,
                          size: 18, color: textSecondaryColorGlobal),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: mobileCont,
                  focusNode: mobileFocus,
                  keyboardType: TextInputType.phone,
                  style: primaryTextStyle(),
                  decoration: const InputDecoration(
                    hintText: 'Numéro de téléphone *',
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  ),
                  onChanged: (_) => setState(() => fieldErrors.remove('mobile')),
                ),
              ),
            ],
          ),
        ),
        _fieldError('mobile'),
      ],
    );
  }

  // ── Step 2: Professionnel ─────────────────────────────────────────────────

  Widget _buildProfessionalInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Service
        Text('Votre métier *', style: secondaryTextStyle(size: 13)),
        8.height,
        isLoadingServices
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2),
                ),
              )
            : Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: context.cardColor,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: fieldErrors['service'] != null
                          ? Colors.red
                          : primaryColor.withValues(alpha:
                              selectedServiceId != null ? 0.5 : 0),
                      width: selectedServiceId != null || fieldErrors['service'] != null
                          ? 1.5
                          : 0,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButton<String>(
                    value: selectedServiceId,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    style: primaryTextStyle(size: 14),
                    dropdownColor: context.cardColor,
                    iconEnabledColor: textSecondaryColorGlobal,
                    hint: Text('Sélectionner un service',
                        style: secondaryTextStyle(size: 14)),
                    items: serviceOptions.map((s) {
                      return DropdownMenuItem<String>(
                        value: s['id'],
                        child: Text(s['name'] ?? '',
                            style: primaryTextStyle(size: 14),
                            overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedServiceId = val;
                        fieldErrors.remove('service');
                        final sel = serviceOptions.firstWhere(
                            (e) => e['id'] == val,
                            orElse: () => {});
                        professionCont.text =
                            sel.isNotEmpty ? (sel['name'] ?? '') : '';
                      });
                    },
                  ),
                ),
              ),
        _fieldError('service'),
        20.height,

        // Bio
        Text('Décrivez votre activité *', style: secondaryTextStyle(size: 13)),
        8.height,
        TextField(
          controller: bioCont,
          focusNode: bioFocus,
          maxLines: 5,
          minLines: 4,
          style: primaryTextStyle(),
          keyboardType: TextInputType.multiline,
          decoration: _dec('Expérience, compétences, spécialités...',).copyWith(
            labelText: null,
            hintText: 'Décrivez votre expérience, vos compétences... (min. 20 caractères)',
            hintStyle: secondaryTextStyle(size: 13),
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() => fieldErrors.remove('bio')),
        ),
        _fieldError('bio'),
        20.height,

        // Adresse
        Row(
          children: [
            Text('Adresse *', style: secondaryTextStyle(size: 13)),
            const Spacer(),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _fetchCurrentLocation();
              },
              child: isLoadingLocation
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: primaryColor),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.my_location_rounded,
                            size: 15, color: primaryColor),
                        4.width,
                        Text('Ma position',
                            style: boldTextStyle(size: 12, color: primaryColor)),
                      ],
                    ),
            ),
          ],
        ),
        8.height,
        Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: fieldErrors['address'] != null
                  ? Colors.red
                  : addressCont.text.isNotEmpty
                      ? primaryColor.withValues(alpha: 0.4)
                      : Colors.grey.withValues(alpha: 0.15),
              width: fieldErrors['address'] != null || addressCont.text.isNotEmpty
                  ? 1.5
                  : 1,
            ),
          ),
          child: GooglePlaceAutoCompleteTextField(
            textEditingController: addressCont,
            googleAPIKey: GOOGLE_PLACES_API_KEY,
            inputDecoration: InputDecoration(
              hintText: isLoadingLocation
                  ? 'Récupération...'
                  : 'Rechercher une adresse...',
              hintStyle: secondaryTextStyle(size: 13),
              prefixIcon: Icon(Icons.location_on_outlined,
                  color: addressCont.text.isNotEmpty
                      ? primaryColor
                      : textSecondaryColorGlobal,
                  size: 20),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            debounceTime: 400,
            countries: const ['sn','ml','ci','bf','gn','ne','tg','bj','mr','gm'],
            isLatLngRequired: true,
            getPlaceDetailWithLatLng: (Prediction p) {
              setState(() {
                addressCont.text = p.description ?? '';
                addressLat = double.tryParse(p.lat ?? '');
                addressLon = double.tryParse(p.lng ?? '');
                fieldErrors.remove('address');
              });
            },
            itemClick: (Prediction p) {
              addressCont.text = p.description ?? '';
              addressCont.selection = TextSelection.fromPosition(
                  TextPosition(offset: p.description?.length ?? 0));
            },
            seperatedBuilder:
                Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
            containerHorizontalPadding: 0,
            itemBuilder: (_, __, Prediction p) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 18, color: textSecondaryColorGlobal),
                  12.width,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.structuredFormatting?.mainText ?? '',
                            style: primaryTextStyle(size: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        2.height,
                        Text(p.structuredFormatting?.secondaryText ?? '',
                            style: secondaryTextStyle(size: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (addressLat != null)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 2),
            child: Row(
              children: [
                Icon(Icons.gps_fixed_rounded, size: 12, color: Colors.green.shade600),
                4.width,
                Text(
                  '${addressLat!.toStringAsFixed(4)}, ${addressLon!.toStringAsFixed(4)}',
                  style: secondaryTextStyle(size: 11, color: Colors.green.shade600),
                ),
              ],
            ),
          ),
        _fieldError('address'),
      ],
    );
  }

  // ── Step 3: Documents ─────────────────────────────────────────────────────

  Widget _buildDocumentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _docUploadZone(
          label: 'Photo de profil',
          required: true,
          errorKey: 'profileImage',
          isUploaded: profileImageFile != null,
          previewBytes: profileImageBytes,
          isCircle: true,
          accentColor: primaryColor,
          icon: Icons.person_rounded,
          onTap: () {
            pickImage();
            setState(() => fieldErrors.remove('profileImage'));
          },
          onRemove: profileImageFile != null
              ? () => setState(() {
                    profileImageFile = null;
                    profileImageBytes = null;
                  })
              : null,
        ),
        _fieldError('profileImage'),
        16.height,

        _docUploadZone(
          label: 'Pièce d\'identité',
          required: true,
          errorKey: 'identity',
          isUploaded: identityFile != null,
          previewBytes: identityBytes,
          isCircle: false,
          accentColor: const Color(0xFF3B82F6),
          icon: Icons.badge_outlined,
          hint: 'CNI · Passeport · Permis',
          onTap: () {
            pickIdentityDocument();
            setState(() => fieldErrors.remove('identity'));
          },
          onRemove: identityFile != null
              ? () => setState(() {
                    identityFile = null;
                    identityBytes = null;
                  })
              : null,
        ),
        _fieldError('identity'),
        16.height,

        _docUploadZone(
          label: 'Preuve de profession',
          required: false,
          errorKey: null,
          isUploaded: professionProofFile != null,
          previewBytes: professionProofBytes,
          isCircle: false,
          accentColor: const Color(0xFFF59E0B),
          icon: Icons.workspace_premium_outlined,
          hint: 'Diplôme · Certificat · Recommandation',
          onTap: pickProfessionProof,
          onRemove: professionProofFile != null
              ? () => setState(() {
                    professionProofFile = null;
                    professionProofBytes = null;
                  })
              : null,
        ),
        24.height,

        // CGU
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              isAcceptedTc = !isAcceptedTc;
              if (isAcceptedTc) fieldErrors.remove('terms');
            });
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: fieldErrors['terms'] != null
                    ? Colors.red
                    : isAcceptedTc
                        ? Colors.green.withValues(alpha: 0.4)
                        : Colors.grey.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isAcceptedTc ? Colors.green : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isAcceptedTc
                          ? Colors.green
                          : Colors.grey.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: isAcceptedTc
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 16)
                      : null,
                ),
                14.width,
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: secondaryTextStyle(size: 13),
                      children: [
                        TextSpan(text: '${language.lblAgree} '),
                        TextSpan(
                          text: language.lblTermsOfService,
                          style: boldTextStyle(color: primaryColor, size: 13),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => checkIfLink(
                                context, appConfigurationStore.termConditions,
                                title: language.termsCondition),
                        ),
                        const TextSpan(text: ' & '),
                        TextSpan(
                          text: language.privacyPolicy,
                          style: boldTextStyle(color: primaryColor, size: 13),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => checkIfLink(
                                context, appConfigurationStore.privacyPolicy,
                                title: language.privacyPolicy),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _fieldError('terms'),
      ],
    );
  }

  Widget _docUploadZone({
    required String label,
    required bool required,
    required String? errorKey,
    required bool isUploaded,
    required Uint8List? previewBytes,
    required bool isCircle,
    required Color accentColor,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onRemove,
    String? hint,
  }) {
    final hasError = errorKey != null && fieldErrors[errorKey] != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasError
                ? Colors.red
                : isUploaded
                    ? accentColor.withValues(alpha: 0.45)
                    : Colors.grey.withValues(alpha: 0.18),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Preview or icon
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isUploaded && previewBytes != null
                  ? ClipRRect(
                      key: const ValueKey('img'),
                      borderRadius:
                          BorderRadius.circular(isCircle ? 40 : 10),
                      child: Image.memory(previewBytes,
                          width: 56, height: 56, fit: BoxFit.cover),
                    )
                  : Container(
                      key: const ValueKey('ico'),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(isCircle ? 28 : 12),
                      ),
                      child: Icon(icon, color: accentColor, size: 24),
                    ),
            ),
            16.width,
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(label,
                            style: boldTextStyle(size: 14),
                            overflow: TextOverflow.ellipsis),
                      ),
                      6.width,
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: required
                              ? accentColor.withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          required ? 'Requis' : 'Optionnel',
                          style: boldTextStyle(
                              size: 9,
                              color: required
                                  ? accentColor
                                  : textSecondaryColorGlobal),
                        ),
                      ),
                    ],
                  ),
                  if (hint != null || isUploaded) ...[
                    4.height,
                    Text(
                      isUploaded ? 'Fichier sélectionné ✓' : hint!,
                      style: secondaryTextStyle(
                          size: 12,
                          color: isUploaded
                              ? Colors.green.shade600
                              : textSecondaryColorGlobal),
                    ),
                  ],
                ],
              ),
            ),
            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isUploaded ? Icons.edit_rounded : Icons.add_rounded,
                    color: accentColor,
                    size: 18,
                  ),
                ),
                if (isUploaded && onRemove != null) ...[
                  6.height,
                  GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.red, size: 16),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Navigation buttons ────────────────────────────────────────────────────

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: context.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (currentStep > 0)
              Expanded(
                child: GestureDetector(
                  onTap: previousStep,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_back_ios_rounded,
                            size: 15, color: textPrimaryColorGlobal),
                        6.width,
                        Text('Précédent', style: boldTextStyle(size: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            if (currentStep > 0) 12.width,
            Expanded(
              child: GestureDetector(
                onTap: nextStep,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        currentStep == totalSteps - 1 ? "S'inscrire" : 'Suivant',
                        style: boldTextStyle(size: 14, color: Colors.white),
                      ),
                      8.width,
                      Icon(
                        currentStep == totalSteps - 1
                            ? Icons.check_circle_outline_rounded
                            : Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: secondaryTextStyle(),
          children: [
            TextSpan(text: '${language.alreadyHaveAccountTxt} '),
            TextSpan(
              text: language.signIn,
              style: boldTextStyle(color: primaryColor, size: 14),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  HapticFeedback.selectionClick();
                  finish(context);
                },
            ),
          ],
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
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          leading: Container(
            margin: const EdgeInsets.only(left: 8, top: 4),
            decoration: BoxDecoration(
              color: context.cardColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: BackWidget(iconColor: context.iconColor),
          ),
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarIconBrightness:
                appStore.isDarkMode ? Brightness.light : Brightness.dark,
            statusBarColor: Colors.transparent,
          ),
        ),
        body: Stack(
          children: [
            Form(
              key: formKey,
              autovalidateMode: isFirstTimeValidation
                  ? AutovalidateMode.disabled
                  : AutovalidateMode.onUserInteraction,
              child: Column(
                children: [
                  _buildStepIndicator(),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (i) => setState(() => currentStep = i),
                      children: [
                        SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          physics: const BouncingScrollPhysics(),
                          child: _buildPersonalInfoStep(),
                        ),
                        SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          physics: const BouncingScrollPhysics(),
                          child: _buildProfessionalInfoStep(),
                        ),
                        SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          physics: const BouncingScrollPhysics(),
                          child: _buildDocumentsStep(),
                        ),
                      ],
                    ),
                  ),
                  _buildNavigationButtons(),
                  _buildFooterWidget(),
                ],
              ),
            ),
            // Loader
            Observer(
              builder: (_) => appStore.isLoading
                  ? Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 24),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LoaderWidget(),
                              14.height,
                              Text('Inscription en cours...',
                                  style: secondaryTextStyle()),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom sheet picker ───────────────────────────────────────────────────────

class _PickerSheet extends StatelessWidget {
  final String title;
  final VoidCallback onGallery;
  final VoidCallback? onCamera;

  const _PickerSheet({
    required this.title,
    required this.onGallery,
    this.onCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          16.height,
          Text(title, style: boldTextStyle(size: 16)),
          4.height,
          Text('Choisissez une source', style: secondaryTextStyle(size: 13)),
          20.height,
          _SheetOption(
            icon: Icons.photo_library_outlined,
            label: 'Galerie',
            onTap: onGallery,
          ),
          if (onCamera != null) ...[
            12.height,
            _SheetOption(
              icon: Icons.camera_alt_outlined,
              label: 'Caméra',
              onTap: onCamera!,
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SheetOption(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: primaryColor),
            14.width,
            Text(label, style: boldTextStyle(size: 14)),
          ],
        ),
      ),
    );
  }
}
