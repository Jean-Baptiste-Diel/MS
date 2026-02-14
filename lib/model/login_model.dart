import 'package:booking_system_flutter/model/user_data_model.dart';


/// API returns: { access, refresh, user: { id, email, role, first_name, last_name } }
class LoginResponse {
  UserData? userData;
  String? accessToken;
  String? refreshToken;
  bool? isUserExist;
  bool? status;
  String? message;

  LoginResponse({
    this.userData,
    this.accessToken,
    this.refreshToken,
    this.isUserExist,
    this.status,
    this.message,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    // Handle Mison API response format
    UserData? user;
    String? access;
    String? refresh;

    // Mison API format: { access, refresh, user: {...} }
    if (json.containsKey('access') && json.containsKey('user')) {
      access = json['access'];
      refresh = json['refresh'];
      user = UserData.fromMisonJson(json['user'], accessToken: access);
    }
    // Legacy format: { data: {...} }
    else if (json['data'] != null) {
      user = UserData.fromJson(json['data']);
      access = user.apiToken;
    }

    return LoginResponse(
      userData: user,
      accessToken: access,
      refreshToken: refresh,
      isUserExist: json['is_user_exist'],
      status: json['status'] ?? true,
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (userData != null) {
      data['user'] = userData!.toJson();
    }
    if (accessToken != null) data['access'] = accessToken;
    if (refreshToken != null) data['refresh'] = refreshToken;
    data['is_user_exist'] = isUserExist;
    data['status'] = status;
    data['message'] = message;
    return data;
  }
}

class VerificationModel {
  bool? status;
  String? message;
  int? isEmailVerified;

  VerificationModel({this.status, this.message, this.isEmailVerified});

  factory VerificationModel.fromJson(Map<String, dynamic> json) {
    return VerificationModel(status: json['status'], message: json['message'], isEmailVerified: json['is_email_verified']);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();

    data['status'] = status;
    data['message'] = message;
    data['is_email_verified'] = isEmailVerified;
    return data;
  }
}
