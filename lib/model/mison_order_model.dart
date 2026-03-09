/// Modèles pour l'API Mison Orders
/// Endpoints: /api/orders (GET, POST), /api/orders/{id}, etc.

class MisonOrderResponse {
  String? message;
  List<MisonOrder>? data;

  MisonOrderResponse({this.message, this.data});

  factory MisonOrderResponse.fromJson(Map<String, dynamic> json) {
    return MisonOrderResponse(
      message: json['message']?.toString(),
      data: json['data'] != null
          ? (json['data'] as List)
              .map((e) => MisonOrder.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

class MisonOrderDetailResponse {
  String? message;
  MisonOrder? data;

  MisonOrderDetailResponse({this.message, this.data});

  factory MisonOrderDetailResponse.fromJson(Map<String, dynamic> json) {
    return MisonOrderDetailResponse(
      message: json['message']?.toString(),
      data: json['data'] != null
          ? MisonOrder.fromJson(json['data'] as Map<String, dynamic>)
          : null,
    );
  }
}

class MisonOrder {
  String? id; // UUID
  MisonClient? client;
  MisonServiceInfo? service;
  MisonArtisanInfo? artisan;
  String? description;
  String? serviceDate; // ISO8601
  String? serviceAddress;
  String? status; // PENDING, ASSIGNED, ACCEPTED, REJECTED, IN_PROGRESS, COMPLETED, CANCELLED
  String? paymentStatus; // PENDING, PAID, REFUNDED
  int? clientRating;
  String? clientReview;
  String? createdAt;
  String? updatedAt;

  MisonOrder({
    this.id,
    this.client,
    this.service,
    this.artisan,
    this.description,
    this.serviceDate,
    this.serviceAddress,
    this.status,
    this.paymentStatus,
    this.clientRating,
    this.clientReview,
    this.createdAt,
    this.updatedAt,
  });

  factory MisonOrder.fromJson(Map<String, dynamic> json) {
    return MisonOrder(
      id: json['id']?.toString(),
      client: json['client'] != null
          ? MisonClient.fromJson(json['client'] as Map<String, dynamic>)
          : null,
      service: json['service'] != null
          ? MisonServiceInfo.fromJson(json['service'] as Map<String, dynamic>)
          : null,
      artisan: json['artisan'] != null
          ? MisonArtisanInfo.fromJson(json['artisan'] as Map<String, dynamic>)
          : null,
      description: json['description']?.toString(),
      serviceDate: json['service_date']?.toString(),
      serviceAddress: json['service_address']?.toString(),
      status: json['status']?.toString(),
      paymentStatus: json['payment_status']?.toString(),
      clientRating: json['client_rating'] != null
          ? int.tryParse(json['client_rating'].toString())
          : null,
      clientReview: json['client_review']?.toString(),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'client': client?.toJson(),
      'service': service?.toJson(),
      'artisan': artisan?.toJson(),
      'description': description,
      'service_date': serviceDate,
      'service_address': serviceAddress,
      'status': status,
      'payment_status': paymentStatus,
      'client_rating': clientRating,
      'client_review': clientReview,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// Status helpers
  bool get isPending => status == 'PENDING';
  bool get isAssigned => status == 'ASSIGNED';
  bool get isAccepted => status == 'ACCEPTED';
  bool get isRejected => status == 'REJECTED';
  bool get isInProgress => status == 'IN_PROGRESS';
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED';

  /// Can rate: only completed orders without rating
  bool get canRate => isCompleted && clientRating == null;
}

class MisonClient {
  String? id;
  String? email;
  String? firstName;
  String? lastName;

  MisonClient({this.id, this.email, this.firstName, this.lastName});

  factory MisonClient.fromJson(Map<String, dynamic> json) {
    return MisonClient(
      id: json['id']?.toString(),
      email: json['email']?.toString(),
      firstName: json['first_name']?.toString(),
      lastName: json['last_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
      };

  String get fullName => '${firstName ?? ''} ${lastName ?? ''}'.trim();
}

class MisonServiceInfo {
  String? id;
  String? name;
  String? minPrice;
  String? imageUrl;

  MisonServiceInfo({this.id, this.name, this.minPrice, this.imageUrl});

  factory MisonServiceInfo.fromJson(Map<String, dynamic> json) {
    return MisonServiceInfo(
      id: json['id']?.toString(),
      name: json['name']?.toString(),
      minPrice: json['min_price']?.toString(),
      imageUrl: json['image_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'min_price': minPrice,
        'image_url': imageUrl,
      };

  num get minPriceValue => num.tryParse(minPrice ?? '0') ?? 0;
}

class MisonArtisanInfo {
  String? id;
  String? firstName;
  String? lastName;
  MisonServiceInfo? service;
  int? experienceYears;
  String? bio;
  String? address;
  bool? isAvailable;
  String? averageRating;
  int? totalReviews;
  String? profilePictureUrl;

  MisonArtisanInfo({
    this.id,
    this.firstName,
    this.lastName,
    this.service,
    this.experienceYears,
    this.bio,
    this.address,
    this.isAvailable,
    this.averageRating,
    this.totalReviews,
    this.profilePictureUrl,
  });

  factory MisonArtisanInfo.fromJson(Map<String, dynamic> json) {
    return MisonArtisanInfo(
      id: json['id']?.toString(),
      firstName: json['first_name']?.toString(),
      lastName: json['last_name']?.toString(),
      service: json['service'] != null
          ? MisonServiceInfo.fromJson(json['service'] as Map<String, dynamic>)
          : null,
      experienceYears: json['experience_years'] != null
          ? int.tryParse(json['experience_years'].toString())
          : null,
      bio: json['bio']?.toString(),
      address: json['address']?.toString(),
      isAvailable: json['is_available'] == true,
      averageRating: json['average_rating']?.toString(),
      totalReviews: json['total_reviews'] != null
          ? int.tryParse(json['total_reviews'].toString())
          : null,
      profilePictureUrl: json['profile_picture_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'service': service?.toJson(),
        'experience_years': experienceYears,
        'bio': bio,
        'address': address,
        'is_available': isAvailable,
        'average_rating': averageRating,
        'total_reviews': totalReviews,
        'profile_picture_url': profilePictureUrl,
      };

  String get fullName => '${firstName ?? ''} ${lastName ?? ''}'.trim();
  num get rating => num.tryParse(averageRating ?? '0') ?? 0;
}

/// Request model for creating an order
class MisonCreateOrderRequest {
  String service; // UUID
  String description;
  String serviceDate; // ISO8601
  String serviceAddress;

  MisonCreateOrderRequest({
    required this.service,
    required this.description,
    required this.serviceDate,
    required this.serviceAddress,
  });

  Map<String, dynamic> toJson() => {
        'service': service,
        'description': description,
        'service_date': serviceDate,
        'service_address': serviceAddress,
      };
}

/// Request model for rating an order
class MisonRateOrderRequest {
  int rating; // 1-5
  String review;

  MisonRateOrderRequest({required this.rating, required this.review});

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'review': review,
      };
}

/// Request model for artisan decision
class MisonArtisanDecisionRequest {
  String decision; // APPROVE or REJECT

  MisonArtisanDecisionRequest({required this.decision});

  Map<String, dynamic> toJson() => {'decision': decision};
}

/// Response for decision/rate actions
class MisonActionResponse {
  String? message;
  Map<String, dynamic>? data;

  MisonActionResponse({this.message, this.data});

  factory MisonActionResponse.fromJson(Map<String, dynamic> json) {
    return MisonActionResponse(
      message: json['message']?.toString(),
      data: json['data'] as Map<String, dynamic>?,
    );
  }
}
