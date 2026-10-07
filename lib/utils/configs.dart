import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

const APP_NAME = 'MISON';
const APP_NAME_TAG_LINE = 'On-Demand Home Services App';
var defaultPrimaryColor = Color(0xFFF4BB16);

const DOMAIN_URL = 'https://dev-api.mison.app';
const BASE_URL = '$DOMAIN_URL/api/';


const DEFAULT_LANGUAGE = 'fr';

//Note: For FIREBASE_SERVER_CLIENT_ID ---> Go to android/app/google-services.json
// - Find press ctrl+F and look for "client_type": 3
// "client_id" in same object has be pasted here
const FIREBASE_SERVER_CLIENT_ID = 'YOUR_FIREBASE_SERVER_CLIENT_ID';

/// Fiche de MISON sur l'App Store (bouton « Mettre à jour » sur iPhone).
/// Identifiant Apple de l'app : 6777843890 (actif une fois l'app publiée).
const IOS_LINK_FOR_USER = 'https://apps.apple.com/app/id6777843890';

const DASHBOARD_AUTO_SLIDER_SECOND = 5;
const OTP_TEXT_FIELD_LENGTH = 6;

// Pages légales et contact du site Mison.
const TERMS_CONDITION_URL = 'https://mison-services.com/cgu/';
const PRIVACY_POLICY_URL = 'https://mison-services.com/confidentialite/';
const HELP_AND_SUPPORT_URL = 'https://mison-services.com/contact/';
const REFUND_POLICY_URL = 'https://mison-services.com/cgv/';
const INQUIRY_SUPPORT_EMAIL = 'contact@mison-services.com';

/// Numéro d'aide (celui du site mison-services.com).
const HELP_LINE_NUMBER = '+221761846030';

DateTime todayDate = DateTime(2022, 8, 24);

Country defaultCountry() {
  return Country(
    phoneCode: '221',
    countryCode: 'SN',
    e164Sc: 221,
    geographic: true,
    level: 1,
    name: 'Senegal',
    example: '777839359',
    displayName: 'Senegal (SN) [+221]',
    displayNameNoCountryCode: 'Senegal (SN)',
    e164Key: '221-SN-0',
    fullExampleWithPlusSign: '+221777839359',
  );
}

//Chat Module File Upload Configs
const chatFilesAllowedExtensions = [
  'jpg', 'jpeg', 'png', 'gif', 'webp', // Images
  'pdf', 'txt', // Documents
  'mkv', 'mp4', // Video
  'mp3', // Audio
];

const max_acceptable_file_size = 5; //Size in Mb