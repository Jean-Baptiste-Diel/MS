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
  String? status; // PENDING, ASSIGNED, ACCEPTED, AWAITING_TRAVEL_PAYMENT, IN_PROGRESS, AWAITING_REALIZATION_PAYMENT, COMPLETED, CANCELLED, REJECTED
  String? paymentStatus; // PENDING, PAID, REFUNDED
  String? latitude;
  String? longitude;
  double? distanceKm;
  String? travelFee;       // e.g. "3000.00"
  String? realizationFee;  // e.g. "25000.00"
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
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.travelFee,
    this.realizationFee,
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
      artisan: (json['artisan'] ?? json['assigned_artisan']) != null
          ? MisonArtisanInfo.fromJson((json['artisan'] ?? json['assigned_artisan']) as Map<String, dynamic>)
          : null,
      description: json['description']?.toString(),
      serviceDate: json['service_date']?.toString(),
      serviceAddress: json['service_address']?.toString(),
      status: json['status']?.toString(),
      paymentStatus: json['payment_status']?.toString(),
      latitude: json['latitude']?.toString(),
      longitude: json['longitude']?.toString(),
      distanceKm: json['distance_km'] != null
          ? double.tryParse(json['distance_km'].toString())
          : null,
      travelFee: json['travel_fee']?.toString(),
      realizationFee: json['realization_fee']?.toString(),
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
      'latitude': latitude,
      'longitude': longitude,
      'distance_km': distanceKm,
      'travel_fee': travelFee,
      'realization_fee': realizationFee,
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
  bool get isAwaitingTravelPayment => status == 'AWAITING_TRAVEL_PAYMENT';
  bool get isInProgress => status == 'IN_PROGRESS';
  bool get isAwaitingRealizationPayment => status == 'AWAITING_REALIZATION_PAYMENT';
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED';
  bool get isRejected => status == 'REJECTED';

  bool get isAwaitingAnyPayment => isAwaitingTravelPayment || isAwaitingRealizationPayment;

  /// Montant à payer selon le statut courant
  String? get currentFeeAmount =>
      isAwaitingTravelPayment ? travelFee : isAwaitingRealizationPayment ? realizationFee : null;

  /// Can rate: only completed orders without rating
  bool get canRate => isCompleted && clientRating == null;

  /// Can call: artisan accepted and order is active
  bool get canCall =>
      artisan != null &&
      (isAccepted || isAwaitingTravelPayment || isInProgress || isAwaitingRealizationPayment);

  /// Can track artisan location: intervention en cours
  bool get canTrack => artisan != null && isInProgress;
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
    // assigned_artisan peut avoir un sous-objet user contenant first_name/last_name
    final user = json['user'] as Map<String, dynamic>?;
    return MisonArtisanInfo(
      id: json['id']?.toString(),
      firstName: (user ?? json)['first_name']?.toString(),
      lastName: (user ?? json)['last_name']?.toString(),
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
      profilePictureUrl: (json['profile_picture_url'] ?? user?['profile_picture_url'])?.toString(),
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

/// Response for POST /api/orders/{id}/call-token
class MisonCallTokenResponse {
  String? appId;
  String? channel;
  String? token;
  int? uid;

  MisonCallTokenResponse({this.appId, this.channel, this.token, this.uid});

  factory MisonCallTokenResponse.fromJson(Map<String, dynamic> json) {
    return MisonCallTokenResponse(
      appId: json['app_id']?.toString(),
      channel: json['channel']?.toString(),
      token: json['token']?.toString(),
      uid: json['uid'] != null ? int.tryParse(json['uid'].toString()) : null,
    );
  }
}

/// Request model for creating an order
class MisonCreateOrderRequest {
  String service; // UUID
  String description;
  String serviceDate; // ISO8601
  String serviceAddress;
  double? latitude;
  double? longitude;
  String? artisanId; // UUID — prestataire souhaité

  MisonCreateOrderRequest({
    required this.service,
    required this.description,
    required this.serviceDate,
    required this.serviceAddress,
    this.latitude,
    this.longitude,
    this.artisanId,
  });

  Map<String, dynamic> toJson() => {
        'service': service,
        'description': description,
        'service_date': serviceDate,
        'service_address': serviceAddress,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (artisanId != null) 'artisan_id': artisanId,
      };
}

/// Request model for worker request order (POST /api/worker-requests or /api/orders with worker_count)
class MisonWorkerRequestModel {
  String service; // UUID
  int workerCount;
  String description;
  String serviceDate; // ISO8601
  String serviceAddress;

  MisonWorkerRequestModel({
    required this.service,
    required this.workerCount,
    required this.description,
    required this.serviceDate,
    required this.serviceAddress,
  });

  Map<String, dynamic> toJson() => {
        'service': service,
        'worker_count': workerCount,
        'description': description,
        'service_date': serviceDate,
        'service_address': serviceAddress,
      };
}

/// Response model for GET /api/worker-requests
class MisonWorkerRequestResponse {
  String? message;
  List<MisonWorkerRequest>? data;

  MisonWorkerRequestResponse({this.message, this.data});

  factory MisonWorkerRequestResponse.fromJson(Map<String, dynamic> json) {
    return MisonWorkerRequestResponse(
      message: json['message']?.toString(),
      data: json['data'] != null
          ? (json['data'] as List)
              .map((e) => MisonWorkerRequest.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

class MisonWorkerRequest {
  String? id;
  MisonClient? client;
  MisonServiceInfo? service;
  int? workerCount;
  String? description;
  String? serviceDate;
  String? serviceAddress;
  String? status;
  List<MisonClient>? assignedArtisans;
  String? createdAt;

  MisonWorkerRequest({
    this.id,
    this.client,
    this.service,
    this.workerCount,
    this.description,
    this.serviceDate,
    this.serviceAddress,
    this.status,
    this.assignedArtisans,
    this.createdAt,
  });

  factory MisonWorkerRequest.fromJson(Map<String, dynamic> json) {
    return MisonWorkerRequest(
      id: json['id']?.toString(),
      client: json['client'] != null
          ? MisonClient.fromJson(json['client'] as Map<String, dynamic>)
          : null,
      service: json['service'] != null
          ? MisonServiceInfo.fromJson(json['service'] as Map<String, dynamic>)
          : null,
      workerCount: json['worker_count'] != null
          ? int.tryParse(json['worker_count'].toString())
          : null,
      description: json['description']?.toString(),
      serviceDate: json['service_date']?.toString(),
      serviceAddress: json['service_address']?.toString(),
      status: json['status']?.toString(),
      assignedArtisans: json['assigned_artisans'] != null
          ? (json['assigned_artisans'] as List)
              .map((e) => MisonClient.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      createdAt: json['created_at']?.toString(),
    );
  }

  bool get isPending => status == 'PENDING';
  bool get isAssigned => status == 'ASSIGNED';
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED';
  bool get hasArtisans => assignedArtisans != null && assignedArtisans!.isNotEmpty;
}

/// Response for GET /api/artisans
class MisonArtisanListResponse {
  String? message;
  List<MisonArtisanInfo>? data;

  MisonArtisanListResponse({this.message, this.data});

  factory MisonArtisanListResponse.fromJson(Map<String, dynamic> json) {
    return MisonArtisanListResponse(
      message: json['message']?.toString(),
      data: json['data'] != null
          ? (json['data'] as List)
              .map((e) => MisonArtisanInfo.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
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
  String? waveLaunchUrl;
  String? checkoutId;
  String? deeplink;

  MisonActionResponse({this.message, this.data, this.waveLaunchUrl, this.checkoutId, this.deeplink});

  factory MisonActionResponse.fromJson(Map<String, dynamic> json) {
    return MisonActionResponse(
      message: json['message']?.toString(),
      data: json['data'] as Map<String, dynamic>?,
      waveLaunchUrl: json['wave_launch_url']?.toString(),
      checkoutId: json['checkout_id']?.toString(),
      deeplink: json['deeplink']?.toString(),
    );
  }
}
