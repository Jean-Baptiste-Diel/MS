import 'package:flutter/material.dart';

abstract class BaseLanguage {
  static BaseLanguage of(BuildContext context) =>
      Localizations.of<BaseLanguage>(context, BaseLanguage)!;





  String get signIn;

  String get signUp;

  String get hintFirstNameTxt;

  String get hintLastNameTxt;

  String get hintContactNumberTxt;

  String get hintEmailAddressTxt;




  String get confirm;

  String get hintEmailTxt;

  String get forgotPassword;

  String get alreadyHaveAccountTxt;

  String get rememberMe;

  String get resetPassword;


  String get camera;

  String get language;




  String get termsCondition;


  String get privacyPolicy;


  String get changePassword;

  String get logout;

  String get editProfile;





  String get passwordNotMatch;

  String get doNotHaveAccount;





  String get lblGallery;




  String get review;



  String get contactAdmin;


  String get duration;


  String get payment;

  String get done;

  String get totalAmount;


  String get home;

  String get category;

  String get booking;

  String get profile;



  String get serviceName;

  String get service;






  String get paymentStatus;














  String get lblUnAuthorized;


  String get lblViewAll;



  String get lblChat;


  String get setAddress;

  String get requiredText;




  String get msgForLocationOn;

  String get msgForLocationOff;

  String get lblEnterPhnNumber;

  String get btnSendOtp;


  String get lblAppSetting;





  String get lblChangePwdTitle;

  String get lblForgotPwdSubtitle;



  String get lblOrContinueWith;


















  String get textProvider;





















  String get lblHold;






  String get lblCategory;
































  String get textHandyman;









  String get lblAlert;




  String get lblBackPressMsg;


  String get lblHr;




  String get lblAgree;

  String get lblTermsOfService;












  String get lblSignInWithGoogle;

  String get lblSignInWithOTP;


  String get lblDeleteAccount;

  String get lblUnderMaintenance;

  String get lblCatchUpAfterAWhile;




  String get lblPending;






  String get lblRecheck;


  String get lblUpdate;

  String get lblNewUpdate;


  String get lblAnUpdateTo;


  String get lblRegisterAsPartner;

  String get lblSignInWithApple;



  String get lblAppleSignInNotAvailable;



  String get lblAll;














  String get services;






  String get termsConditionsAccept;









  String get accept;

  String get price;

  String get remove;

  String get add;

  String get save;





  String get jobPrice;












  String get pleaseEnterValidOTP;

  String get confirmOTP;

  String get sendingOTP;







  String get extraCharges;




  String get verified;

  String get theEnteredCodeIsInvalidPleaseTryAgain;

  String get otpCodeIsSentToYourMobileNumber;






  String get internetNotAvailable;

  String get pleaseTryAgain;

  String get somethingWentWrong;

  String get postJob;









  String get lblNotValidUser;







  String get lblSignInFailed;

  String get lblUserCancelled;


  String get lblExample;


  String get lblLocationPermissionDenied;

  String get lblLocationPermissionDeniedPermanently;

  String get lblEnableLocation;

  String get lblNoUserFound;

  String get lblUserNotCreated;







  String get knownLanguages;








  String get send;


  String get clearChatMessage;


  String get accepted;

  String get onGoing;

  String get inProgress;

  String get cancelled;

  String get rejected;

  String get failed;

  String get completed;

  String get pendingApproval;

  String get waiting;

  String get paid;

  String get advancePaid;












  String get min;

  String get hour;



  String get message;

  String get wallet;





  String get invalidURL;


  String get email;

  String get badRequest;

  String get forbidden;

  String get pageNotFound;

  String get tooManyRequests;

  String get internalServerError;

  String get badGateway;

  String get serviceUnavailable;

  String get gatewayTimeout;



  String get userNotFound;

  String get requested;

  String get assigned;

  String get reload;



  String get addYourCountryCode;

  String get help;






  String get closeApp;



  String get provideValidCurrentPasswordMessage;






  String get balance;



  String get paymentMethod;



  String get serviceAddedToFavourite;

  String get serviceRemovedFromFavourite;


  String get search;

  String get close;





  String get connect;

  String get transactionId;

  String get at;




  String get by;










  String get bookingStatus;



  String get turnOn;

  String get turnOff;







  String get isAvailableGoTo;

  String get later;

  String get whyChooseMe;





  String get handymanList;





  String get reason;































  String get success;





















  String get refundPolicy;

























  String get sendMessage;






  String get featuredServices;




















  String get bankList;
















  String get bankName;


  String get availableBalance;



















  String get packageName;


  String get a;












  String get refundAmount;




  String get open;

  String get closed;

  String get createBy;

  String get repliedBy;

  String get closedBy;

  String get helpDesk;













  String get subject;



  String get on;



  String get chooseAction;

  String get chooseImage;

  String get noteYouCanUpload;

  String get removeImage;

  String get advancedRefund;

  String get lblService;

  String get dateRange;

  String get paymentType;











  String get to;





  String get bank;















  String bookingCompleted(int validate);

  String get lblShop;









  String get contactNumber;



  String shopsService(String shopName);


  String lblProvidersShops(String providerName);

  String lblShopsOffer(String serviceName);










  String shareYourPromoCode(String referrerPoints, String referredPoints);


  /// Referral share message (multi-line) used when user shares referral link
  /// {referralCode} and {referralUrl} will be interpolated in implementations.












  String unlockBenefits(String points);

  // OTP Verification
  String get verifyOTP;
  String get enterTheCodeSentTo;
  String get accountVerifiedSuccessfully;
  String get otpSentSuccessfully;
  String get verify;
  String get didNotReceiveCode;
  String get resendOTP;
  String get resendIn;

  // Artisan Registration
  // Profile selection labels
  String get experienceYears;
}
