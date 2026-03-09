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
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
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

  // Animation controllers
  late PageController _pageController;
  late AnimationController _progressAnimationController;
  final ScrollController _scrollController = ScrollController();

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

  // Fichiers pour le backend
  XFile? profileImageFile;
  Uint8List? profileImageBytes;
  XFile? identityFile;
  Uint8List? identityBytes;
  XFile? professionProofFile;
  Uint8List? professionProofBytes;
  final ImagePicker _picker = ImagePicker();

  // Services fetched from backend
  List<Map<String, String>> serviceOptions = [];
  bool isLoadingServices = false;
  String? selectedServiceId;

  // Multi-step
  int currentStep = 0;
  final int totalSteps = 3;

  bool isAcceptedTc = false;
  bool isFirstTimeValidation = true;

  // Coordonnées de l'adresse sélectionnée
  double? addressLat;
  double? addressLon;

  // État de chargement de la localisation
  bool isLoadingLocation = false;

  // Erreurs de validation par champ
  Map<String, String?> fieldErrors = {};

  @override
  void initState() {
    super.initState();
    experienceYearsCont.text = '0';

    // Initialiser le PageController
    _pageController = PageController(initialPage: 0);

    // Initialiser l'animation de progression
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    fetchServices();

    // Récupérer automatiquement la localisation actuelle
    _fetchCurrentLocation();
  }

  /// Récupère la localisation actuelle et pré-remplit l'adresse
  Future<void> _fetchCurrentLocation() async {
    if (kIsWeb) return; // Skip on web

    setState(() => isLoadingLocation = true);

    try {
      // Vérifier les permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => isLoadingLocation = false);
        return;
      }

      // Obtenir la position actuelle
      final Position position = await getUserLocationPosition();

      // Obtenir l'adresse à partir des coordonnées
      final String address = await buildFullAddressFromLatLong(
        position.latitude,
        position.longitude,
      );

      if (mounted) {
        setState(() {
          addressCont.text = address;
          addressLat = position.latitude;
          addressLon = position.longitude;
          isLoadingLocation = false;
        });

        // Afficher un message de confirmation
        toast('Localisation détectée automatiquement');
      }
    } catch (e) {
      log('Erreur localisation: $e');
      if (mounted) {
        setState(() => isLoadingLocation = false);
      }
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
      toast('Erreur de chargement des services');
    } finally {
      setState(() => isLoadingServices = false);
    }
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
    _pageController.dispose();
    _progressAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  // Gestionnaires de fichiers
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

  Future<void> pickIdentityDocument() async {
    _showDocumentPicker('Pièce d\'identité', _handleIdentitySelection);
  }

  Future<void> pickProfessionProof() async {
    _showDocumentPicker(
        'Preuve de profession', _handleProfessionProofSelection);
  }

  Future<void> _showDocumentPicker(
      String title, Function(XFile?) onSelect) async {
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
                    Text(title, style: boldTextStyle(size: 18)),
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
                          final XFile? file = await _picker.pickImage(
                              source: ImageSource.gallery);
                          onSelect(file);
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
                            final XFile? file = await _picker.pickImage(
                                source: ImageSource.camera);
                            onSelect(file);
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

  bool validateStep(int step) {
    // Réinitialiser les erreurs
    fieldErrors.clear();

    switch (step) {
      case 0: // Étape 1 - Informations personnelles
        bool isValid = true;

        if (fNameCont.text.trim().isEmpty) {
          fieldErrors['firstName'] = 'Veuillez saisir votre prénom';
          isValid = false;
        }
        if (lNameCont.text.trim().isEmpty) {
          fieldErrors['lastName'] = 'Veuillez saisir votre nom';
          isValid = false;
        }
        if (emailCont.text.trim().isEmpty) {
          fieldErrors['email'] = 'Veuillez saisir votre email';
          isValid = false;
        } else if (!emailCont.text.trim().validateEmail()) {
          fieldErrors['email'] = 'Email invalide';
          isValid = false;
        }
        if (passwordCont.text.trim().isEmpty) {
          fieldErrors['password'] = 'Veuillez saisir votre mot de passe';
          isValid = false;
        } else if (passwordCont.text.length < 8 ||
            passwordCont.text.length > 12) {
          fieldErrors['password'] = language.passwordLengthShouldBe;
          isValid = false;
        }
        if (mobileCont.text.trim().isEmpty) {
          fieldErrors['mobile'] = 'Veuillez saisir votre numéro de téléphone';
          isValid = false;
        } else if (mobileCont.text.trim().length < 6) {
          fieldErrors['mobile'] = 'Numéro de téléphone trop court';
          isValid = false;
        }

        setState(() {});
        return isValid;

      case 1: // Étape 2 - Informations professionnelles
        bool isValid = true;

        if ((selectedServiceId == null || selectedServiceId!.isEmpty) &&
            professionCont.text.trim().isEmpty) {
          fieldErrors['service'] = 'Veuillez sélectionner un service';
          isValid = false;
        }
        if (experienceYearsCont.text.trim().isEmpty) {
          fieldErrors['experience'] = "Veuillez saisir vos années d'expérience";
          isValid = false;
        }
        if (hourlyRateCont.text.trim().isEmpty) {
          fieldErrors['hourlyRate'] = 'Veuillez saisir votre taux horaire';
          isValid = false;
        }
        if (dailyRateCont.text.trim().isEmpty) {
          fieldErrors['dailyRate'] = 'Veuillez saisir votre taux journalier';
          isValid = false;
        }
        if (bioCont.text.trim().isEmpty) {
          fieldErrors['bio'] = 'Veuillez saisir votre bio';
          isValid = false;
        } else if (bioCont.text.length < 20) {
          fieldErrors['bio'] = 'La bio doit contenir au moins 20 caractères';
          isValid = false;
        }
        if (addressCont.text.trim().isEmpty) {
          fieldErrors['address'] =
              'Veuillez sélectionner votre adresse sur la carte';
          isValid = false;
        }

        setState(() {});
        return isValid;

      case 2: // Étape 3 - Justificatifs
        bool isValid = true;

        if (profileImageFile == null &&
            (profileImageBytes == null || profileImageBytes!.isEmpty)) {
          fieldErrors['profileImage'] = 'La photo de profil est requise';
          isValid = false;
        }
        if (identityFile == null &&
            (identityBytes == null || identityBytes!.isEmpty)) {
          fieldErrors['identity'] = 'La pièce d\'identité est requise';
          isValid = false;
        }
        if (!isAcceptedTc) {
          fieldErrors['terms'] = language.termsConditionsAccept;
          isValid = false;
        }

        setState(() {});
        return isValid;

      default:
        return false;
    }
  }

  /// Widget pour afficher une erreur sous un champ
  Widget _buildFieldError(String fieldKey) {
    final error = fieldErrors[fieldKey];
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        error,
        style: const TextStyle(
          color: Colors.red,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void nextStep() {
    // Feedback haptique
    HapticFeedback.lightImpact();

    if (validateStep(currentStep)) {
      if (currentStep < totalSteps - 1) {
        setState(() => currentStep++);
        // Animation fluide vers la page suivante
        _pageController.animateToPage(
          currentStep,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
        );
        // Scroll vers le haut
        _scrollToTop();
      } else {
        registerArtisan();
      }
    } else {
      // Feedback haptique pour erreur
      HapticFeedback.heavyImpact();
    }
  }

  void previousStep() {
    HapticFeedback.lightImpact();
    if (currentStep > 0) {
      setState(() => currentStep--);
      _pageController.animateToPage(
        currentStep,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
      _scrollToTop();
    }
  }

  void _scrollToTop() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _goToStep(int step) {
    if (step < currentStep || validateStep(currentStep)) {
      HapticFeedback.selectionClick();
      setState(() => currentStep = step);
      _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
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
        'experience_years': experienceYearsCont.text.trim(),
        'hourly_rate': hourlyRateCont.text.trim(),
        'daily_rate': dailyRateCont.text.trim(),
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

  Widget _buildStepIndicator() {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: MediaQuery.of(context).padding.top + 56,
        bottom: 20,
      ),
      decoration: BoxDecoration(
        color: context.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Titre de l'étape actuelle
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.1, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              'Étape ${currentStep + 1}/$totalSteps: ${_getStepTitle(currentStep)}',
              key: ValueKey(currentStep),
              style: boldTextStyle(size: 16, color: primaryColor),
            ),
          ),
          16.height,
          // Barre de progression animée
          Row(
            children: List.generate(totalSteps, (index) {
              final isCompleted = index < currentStep;
              final isCurrent = index == currentStep;

              return Expanded(
                child: GestureDetector(
                  onTap: () => _goToStep(index),
                  child: Container(
                    margin: EdgeInsets.only(
                      left: index == 0 ? 0 : 4,
                      right: index == totalSteps - 1 ? 0 : 4,
                    ),
                    child: Column(
                      children: [
                        // Indicateur de numéro d'étape
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: isCurrent ? 36 : 28,
                          height: isCurrent ? 36 : 28,
                          decoration: BoxDecoration(
                            color: isCompleted || isCurrent
                                ? primaryColor
                                : Colors.grey.withOpacity(0.2),
                            shape: BoxShape.circle,
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: primaryColor.withOpacity(0.4),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: isCompleted
                                ? Icon(Icons.check, color: white, size: 16)
                                : Text(
                                    '${index + 1}',
                                    style: boldTextStyle(
                                      size: isCurrent ? 14 : 12,
                                      color: isCompleted || isCurrent
                                          ? white
                                          : textSecondaryColorGlobal,
                                    ),
                                  ),
                          ),
                        ),
                        8.height,
                        // Barre de progression sous l'indicateur
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isCompleted || isCurrent
                                ? primaryColor
                                : Colors.grey.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        6.height,
                        // Titre de l'étape
                        Text(
                          _getStepTitle(index),
                          style: secondaryTextStyle(
                            size: 10,
                            color: isCompleted || isCurrent
                                ? primaryColor
                                : textSecondaryColorGlobal,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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

  String _getStepTitle(int index) {
    switch (index) {
      case 0:
        return 'Personnel';
      case 1:
        return 'Professionnel';
      case 2:
        return 'Justificatifs';
      default:
        return '';
    }
  }

  Widget _buildPersonalInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.person_outline,
          title: 'Informations personnelles',
          subtitle: 'Vos informations de base pour créer votre compte',
        ),
        24.height,
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    textFieldType: TextFieldType.NAME,
                    controller: fNameCont,
                    focus: fNameFocus,
                    nextFocus: lNameFocus,
                    errorThisFieldRequired: language.requiredText,
                    decoration: inputDecoration(
                      context,
                      labelText: 'Prénom *',
                      prefixIcon:
                          ic_profile2.iconImage(size: 16).paddingAll(14),
                    ),
                    onChanged: (_) =>
                        setState(() => fieldErrors.remove('firstName')),
                  ),
                  _buildFieldError('firstName'),
                ],
              ),
            ),
            16.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    textFieldType: TextFieldType.NAME,
                    controller: lNameCont,
                    focus: lNameFocus,
                    nextFocus: emailFocus,
                    errorThisFieldRequired: language.requiredText,
                    decoration: inputDecoration(
                      context,
                      labelText: 'Nom *',
                      prefixIcon:
                          ic_profile2.iconImage(size: 16).paddingAll(14),
                    ),
                    onChanged: (_) =>
                        setState(() => fieldErrors.remove('lastName')),
                  ),
                  _buildFieldError('lastName'),
                ],
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
          decoration: inputDecoration(
            context,
            labelText: 'Email *',
            prefixIcon: ic_message.iconImage(size: 16).paddingAll(14),
          ),
          onChanged: (_) => setState(() => fieldErrors.remove('email')),
        ),
        _buildFieldError('email'),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.PASSWORD,
          controller: passwordCont,
          focus: passwordFocus,
          nextFocus: mobileFocus,
          obscureText: true,
          suffixPasswordVisibleWidget:
              ic_show.iconImage(size: 16).paddingAll(14),
          suffixPasswordInvisibleWidget:
              ic_hide.iconImage(size: 16).paddingAll(14),
          errorThisFieldRequired: language.requiredText,
          decoration: inputDecoration(
            context,
            labelText: 'Mot de passe *',
            prefixIcon: Icon(Icons.lock_outline, size: 18).paddingAll(14),
          ),
          onChanged: (_) => setState(() => fieldErrors.remove('password')),
        ),
        _buildFieldError('password'),
        16.height,
        Container(
          padding: const EdgeInsets.all(8),
          decoration: boxDecorationWithRoundedCorners(
            backgroundColor: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: fieldErrors['mobile'] != null
                ? Border.all(color: Colors.red, width: 1)
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: boxDecorationWithRoundedCorners(
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "+${selectedCountry.phoneCode}",
                  style: boldTextStyle(color: primaryColor),
                ),
              ).onTap(changeCountry),
              12.width,
              Expanded(
                child: AppTextField(
                  textFieldType: TextFieldType.PHONE,
                  controller: mobileCont,
                  focus: mobileFocus,
                  errorThisFieldRequired: language.requiredText,
                  decoration: InputDecoration(
                    labelText: 'Téléphone *',
                    hintText: '${selectedCountry.example}',
                    border: InputBorder.none,
                  ),
                  onChanged: (_) =>
                      setState(() => fieldErrors.remove('mobile')),
                ),
              ),
            ],
          ),
        ),
        _buildFieldError('mobile'),
      ],
    );
  }

  Widget _buildProfessionalInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.work_outline,
          title: 'Informations professionnelles',
          subtitle: 'Détails sur votre activité et vos compétences',
        ),
        24.height,
        isLoadingServices
            ? const Center(child: CircularProgressIndicator())
                .paddingSymmetric(vertical: 32)
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: boxDecorationWithRoundedCorners(
                  backgroundColor: context.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: fieldErrors['service'] != null
                      ? Border.all(color: Colors.red, width: 1)
                      : null,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: selectedServiceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Service / Métier *',
                      border: InputBorder.none,
                    ),
                    items: serviceOptions.map((s) {
                      return DropdownMenuItem<String>(
                        value: s['id'],
                        child: Container(
                          width: double.infinity,
                          child: Row(
                            children: [
                              if (s['icon'] != null && s['icon']!.isNotEmpty)
                                Image.network(s['icon']!,
                                    width: 24, height: 24),
                              8.width,
                              Expanded(
                                child: Text(
                                  s['name'] ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedServiceId = val;
                        fieldErrors.remove('service');
                        final sel = serviceOptions.firstWhere(
                          (e) => e['id'] == val,
                          orElse: () => {},
                        );
                        professionCont.text =
                            sel.isNotEmpty ? (sel['name'] ?? '') : '';
                      });
                    },
                    icon: Icon(Icons.arrow_drop_down,
                        color: textSecondaryColorGlobal),
                  ),
                ),
              ),
        _buildFieldError('service'),
        16.height,
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    textFieldType: TextFieldType.PHONE,
                    controller: experienceYearsCont,
                    focus: experienceYearsFocus,
                    nextFocus: hourlyRateFocus,
                    decoration: inputDecoration(
                      context,
                      labelText: 'Expérience (années) *',
                      prefixIcon: Icon(Icons.timeline, size: 18).paddingAll(14),
                    ),
                    onChanged: (_) =>
                        setState(() => fieldErrors.remove('experience')),
                  ),
                  _buildFieldError('experience'),
                ],
              ),
            ),
            16.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    textFieldType: TextFieldType.PHONE,
                    controller: hourlyRateCont,
                    focus: hourlyRateFocus,
                    nextFocus: dailyRateFocus,
                    decoration: inputDecoration(
                      context,
                      labelText: 'Taux horaire (FCFA) *',
                      prefixIcon:
                          Icon(Icons.attach_money, size: 18).paddingAll(14),
                    ),
                    onChanged: (_) =>
                        setState(() => fieldErrors.remove('hourlyRate')),
                  ),
                  _buildFieldError('hourlyRate'),
                ],
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
          decoration: inputDecoration(
            context,
            labelText: 'Taux journalier (FCFA) *',
            prefixIcon: Icon(Icons.attach_money, size: 18).paddingAll(14),
          ),
          onChanged: (_) => setState(() => fieldErrors.remove('dailyRate')),
        ),
        _buildFieldError('dailyRate'),
        16.height,
        AppTextField(
          textFieldType: TextFieldType.MULTILINE,
          controller: bioCont,
          focus: bioFocus,
          minLines: 4,
          maxLines: 6,
          decoration: inputDecoration(
            context,
            labelText: 'Bio / Description *',
            hintText:
                'Décrivez votre expérience, vos compétences... (min. 20 caractères)',
          ),
          onChanged: (_) => setState(() => fieldErrors.remove('bio')),
        ),
        _buildFieldError('bio'),
        16.height,
        // Sélecteur d'adresse avec Google Places Autocomplete
        Row(
          children: [
            Text('Adresse *', style: boldTextStyle(size: 14)),
            const Spacer(),
            if (isLoadingLocation)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: primaryColor),
                  ),
                  8.width,
                  Text('Détection...', style: secondaryTextStyle(size: 12)),
                ],
              )
            else
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _fetchCurrentLocation();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.my_location, size: 16, color: primaryColor),
                    6.width,
                    Text(
                      'Ma position',
                      style: boldTextStyle(size: 12, color: primaryColor),
                    ),
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
                      ? Colors.green.withOpacity(0.5)
                      : Colors.grey.withOpacity(0.3),
              width: fieldErrors['address'] != null ? 1.5 : 1,
            ),
          ),
          child: GooglePlaceAutoCompleteTextField(
            textEditingController: addressCont,
            googleAPIKey: GOOGLE_PLACES_API_KEY,
            inputDecoration: InputDecoration(
              hintText: isLoadingLocation
                  ? 'Récupération de votre position...'
                  : 'Rechercher une adresse...',
              hintStyle: secondaryTextStyle(),
              prefixIcon: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isLoadingLocation
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: primaryColor),
                      )
                    : Icon(Icons.location_on, color: primaryColor, size: 20),
              ),
              suffixIcon: addressCont.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () {},
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            debounceTime: 400,
            countries: const [
              "sn",
              "ml",
              "ci",
              "bf",
              "gn",
              "ne",
              "tg",
              "bj",
              "mr",
              "gm"
            ],
            isLatLngRequired: true,
            getPlaceDetailWithLatLng: (Prediction prediction) {
              setState(() {
                addressCont.text = prediction.description ?? '';
                addressLat = double.tryParse(prediction.lat ?? '');
                addressLon = double.tryParse(prediction.lng ?? '');
                fieldErrors.remove('address');
              });
            },
            itemClick: (Prediction prediction) {
              HapticFeedback.selectionClick();
              addressCont.text = prediction.description ?? '';
              addressCont.selection = TextSelection.fromPosition(
                TextPosition(offset: prediction.description?.length ?? 0),
              );
            },
            seperatedBuilder:
                Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
            containerHorizontalPadding: 0,
            itemBuilder: (context, index, Prediction prediction) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.place, color: primaryColor, size: 18),
                    ),
                    12.width,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prediction.structuredFormatting?.mainText ?? '',
                            style: boldTextStyle(size: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          4.height,
                          Text(
                            prediction.structuredFormatting?.secondaryText ??
                                '',
                            style: secondaryTextStyle(size: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (addressLat != null && addressLon != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                Icon(Icons.gps_fixed, size: 14, color: Colors.green),
                6.width,
                Text(
                  'Coordonnées: ${addressLat!.toStringAsFixed(4)}, ${addressLon!.toStringAsFixed(4)}',
                  style: secondaryTextStyle(size: 11, color: Colors.green),
                ),
              ],
            ),
          ),
        _buildFieldError('address'),
      ],
    );
  }

  Widget _buildDocumentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.upload_file,
          title: 'Documents justificatifs',
          subtitle: 'Téléchargez les documents requis pour validation',
        ),
        24.height,

        // Photo de profil
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(16),
          decoration: boxDecorationWithRoundedCorners(
            backgroundColor: context.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: fieldErrors['profileImage'] != null
                ? Border.all(color: Colors.red, width: 1)
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: boxDecorationWithRoundedCorners(
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: profileImageBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          profileImageBytes!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(Icons.person, size: 30, color: primaryColor),
              ),
              16.width,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Photo de profil *', style: boldTextStyle()),
                    4.height,
                    Text(
                      profileImageFile != null
                          ? '✓ Photo téléchargée'
                          : 'Ajoutez une photo de profil',
                      style: secondaryTextStyle(
                        color: profileImageFile != null ? Colors.green : null,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                text: profileImageFile != null ? 'Modifier' : 'Ajouter',
                onTap: () {
                  pickImage();
                  setState(() => fieldErrors.remove('profileImage'));
                },
                color: profileImageFile != null ? Colors.green : primaryColor,
                textColor: Colors.white,
              ),
            ],
          ),
        ),
        _buildFieldError('profileImage'),
        12.height,

        // Pièce d'identité
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(16),
          decoration: boxDecorationWithRoundedCorners(
            backgroundColor: context.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: fieldErrors['identity'] != null
                ? Border.all(color: Colors.red, width: 1)
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: boxDecorationWithRoundedCorners(
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.badge, size: 30, color: primaryColor),
              ),
              16.width,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pièce d\'identité *', style: boldTextStyle()),
                    4.height,
                    Text(
                      identityFile != null
                          ? '✓ Document téléchargé'
                          : 'CNI, Passeport ou Permis',
                      style: secondaryTextStyle(
                        color: identityFile != null ? Colors.green : null,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                text: identityFile != null ? 'Modifier' : 'Ajouter',
                onTap: () {
                  pickIdentityDocument();
                  setState(() => fieldErrors.remove('identity'));
                },
                color: identityFile != null ? Colors.green : primaryColor,
                textColor: Colors.white,
              ),
            ],
          ),
        ),
        _buildFieldError('identity'),
        12.height,

        // Preuve de profession (optionnel)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: boxDecorationWithRoundedCorners(
            backgroundColor: context.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: boxDecorationWithRoundedCorners(
                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.assignment, size: 30, color: Colors.orange),
              ),
              16.width,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Preuve de profession', style: boldTextStyle()),
                    4.height,
                    Text(
                      professionProofFile != null
                          ? '✓ Document téléchargé'
                          : 'Diplôme, certificat, recommandation (optionnel)',
                      style: secondaryTextStyle(
                        color:
                            professionProofFile != null ? Colors.green : null,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                text: professionProofFile != null ? 'Modifier' : 'Ajouter',
                onTap: pickProfessionProof,
                color:
                    professionProofFile != null ? Colors.green : Colors.orange,
                textColor: Colors.white,
              ),
            ],
          ),
        ),

        24.height,
        _buildTcAcceptWidget(),
        _buildFieldError('terms'),
      ],
    );
  }

  Widget _buildSectionHeader(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withOpacity(0.08),
            primaryColor.withOpacity(0.02),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: white, size: 22),
          ),
          16.width,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: boldTextStyle(size: 17)),
                6.height,
                Text(
                  subtitle,
                  style: secondaryTextStyle(size: 12),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTcAcceptWidget() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          isAcceptedTc = !isAcceptedTc;
          if (isAcceptedTc) {
            fieldErrors.remove('terms');
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isAcceptedTc ? Colors.green.withOpacity(0.05) : context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: fieldErrors['terms'] != null
                ? Colors.red
                : isAcceptedTc
                    ? Colors.green.withOpacity(0.5)
                    : Colors.grey.withOpacity(0.2),
            width: fieldErrors['terms'] != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isAcceptedTc ? Colors.green : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isAcceptedTc
                      ? Colors.green
                      : Colors.grey.withOpacity(0.4),
                  width: 2,
                ),
              ),
              child: isAcceptedTc
                  ? Icon(Icons.check, color: white, size: 18)
                  : null,
            ),
            16.width,
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: secondaryTextStyle(),
                  children: [
                    TextSpan(text: '${language.lblAgree} '),
                    TextSpan(
                      text: language.lblTermsOfService,
                      style: boldTextStyle(color: primaryColor, size: 14),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          checkIfLink(
                              context, appConfigurationStore.termConditions,
                              title: language.termsCondition);
                        },
                    ),
                    TextSpan(text: ' & '),
                    TextSpan(
                      text: language.privacyPolicy,
                      style: boldTextStyle(color: primaryColor, size: 14),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          checkIfLink(
                              context, appConfigurationStore.privacyPolicy,
                              title: language.privacyPolicy);
                        },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Bouton Précédent
            if (currentStep > 0)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: previousStep,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          color: context.cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_back_ios,
                                size: 16, color: textPrimaryColorGlobal),
                            6.width,
                            Text('Précédent', style: boldTextStyle(size: 15)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (currentStep > 0) 12.width,
            // Bouton Suivant/S'inscrire
            Expanded(
              flex: currentStep > 0 ? 1 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: nextStep,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primaryColor,
                            primaryColor.withOpacity(0.85),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            currentStep == totalSteps - 1
                                ? "S'inscrire"
                                : 'Suivant',
                            style: boldTextStyle(size: 15, color: white),
                          ),
                          if (currentStep < totalSteps - 1) ...[
                            6.width,
                            Icon(Icons.arrow_forward_ios,
                                size: 16, color: white),
                          ] else ...[
                            8.width,
                            Icon(Icons.check_circle_outline,
                                size: 20, color: white),
                          ],
                        ],
                      ),
                    ),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: secondaryTextStyle(),
          children: [
            TextSpan(text: "${language.alreadyHaveAccountTxt} "),
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => hideKeyboard(context),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: transparentColor,
          leading: Container(
            margin: const EdgeInsets.only(left: 8, top: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
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
            statusBarColor: context.scaffoldBackgroundColor,
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
                      onPageChanged: (index) {
                        setState(() => currentStep = index);
                      },
                      children: [
                        // Étape 1: Informations personnelles
                        SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          physics: const BouncingScrollPhysics(),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: currentStep == 0 ? 1 : 0.5,
                            child: _buildPersonalInfoStep(),
                          ),
                        ),
                        // Étape 2: Informations professionnelles
                        SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          physics: const BouncingScrollPhysics(),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: currentStep == 1 ? 1 : 0.5,
                            child: _buildProfessionalInfoStep(),
                          ),
                        ),
                        // Étape 3: Documents
                        SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          physics: const BouncingScrollPhysics(),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: currentStep == 2 ? 1 : 0.5,
                            child: _buildDocumentsStep(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildNavigationButtons(),
                  _buildFooterWidget(),
                ],
              ),
            ),
            // Loader avec animation
            Observer(
              builder: (_) => AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: appStore.isLoading ? 1 : 0,
                child: appStore.isLoading
                    ? Container(
                        color: Colors.black.withOpacity(0.3),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: context.cardColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LoaderWidget(),
                                16.height,
                                Text('Inscription en cours...',
                                    style: secondaryTextStyle()),
                              ],
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
