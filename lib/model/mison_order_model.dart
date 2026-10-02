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
  bool? serverIsImmediate; // is_immediate (null : ancienne version du serveur)
  String? serviceAddress;
  String? status; // PENDING, ASSIGNED, ACCEPTED, AWAITING_TRAVEL_PAYMENT, IN_PROGRESS, AWAITING_REALIZATION_PAYMENT, COMPLETED, CANCELLED, REJECTED
  String? paymentStatus; // PENDING, PAID, REFUNDED
  String? latitude;
  String? longitude;
  double? distanceKm;
  String? travelFee;       // e.g. "3000.00"
  String? realizationFee;  // e.g. "25000.00"
  int? serverServiceFee;   // service_fee : frais de service Mison (100 FCFA)
  int? serverClientTotal;  // client_total : prestation + frais de service
  int? clientRating;
  String? clientReview;
  String? createdAt;
  String? updatedAt;
  String? enRouteAt;  // l'ouvrier est parti chez le client (« Aller chez le client »)
  String? arrivedAt;  // l'ouvrier est arrivé à l'adresse
  String? paymentMethod; // WAVE / ORANGE_MONEY une fois payé, sinon null
  String? invoiceRequestedAt; // facture demandée au support
  int? searchRadiusKm; // recherche progressive : 5, puis 10, puis 15 km
  String? searchStartedAt; // début (ou redémarrage après désistement) de la recherche
  String? searchExhaustedAt; // personne trouvé : le back-office prend le relais

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
    this.serverServiceFee,
    this.serverClientTotal,
    this.clientRating,
    this.clientReview,
    this.createdAt,
    this.updatedAt,
    this.enRouteAt,
    this.arrivedAt,
    this.paymentMethod,
    this.invoiceRequestedAt,
    this.searchRadiusKm,
    this.searchStartedAt,
    this.searchExhaustedAt,
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
      serverServiceFee: num.tryParse(json['service_fee']?.toString() ?? '')?.toInt(),
      serverClientTotal: num.tryParse(json['client_total']?.toString() ?? '')?.toInt(),
      clientRating: json['client_rating'] != null
          ? int.tryParse(json['client_rating'].toString())
          : null,
      clientReview: json['client_review']?.toString(),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      enRouteAt: json['en_route_at']?.toString(),
      arrivedAt: json['arrived_at']?.toString(),
      paymentMethod: json['payment_method']?.toString(),
      invoiceRequestedAt: json['invoice_requested_at']?.toString(),
      searchRadiusKm: num.tryParse(json['search_radius_km']?.toString() ?? '')?.toInt(),
      searchStartedAt: json['search_started_at']?.toString(),
      searchExhaustedAt: json['search_exhausted_at']?.toString(),
    )..serverIsImmediate = json['is_immediate'] is bool ? json['is_immediate'] as bool : null;
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

  /// Commande "Tout de suite" (sinon "Plus tard", programmée par le client).
  /// Le choix est enregistré par le serveur ; à défaut (ancien serveur), il est
  /// déduit de l'écart création → heure prévue, que l'app fixait à +30 min.
  bool get isImmediate {
    if (serverIsImmediate != null) return serverIsImmediate!;
    final created = DateTime.tryParse(createdAt ?? '');
    final scheduled = DateTime.tryParse(serviceDate ?? '');
    if (created == null || scheduled == null) return false;
    return scheduled.difference(created) <= const Duration(minutes: 35);
  }

  /// Le paiement des frais de déplacement a été retiré du parcours : seul le
  /// paiement de réalisation, en fin de prestation, reste dû.
  bool get isAwaitingAnyPayment => isAwaitingRealizationPayment;

  /// Frais de service Mison ajoutés au prix de la prestation.
  int get serviceFee => serverServiceFee ?? 100;

  /// Prix de la prestation fixé par l'ouvrier (FCFA), null tant qu'il ne l'est pas.
  int? get prestationPrice => num.tryParse(realizationFee ?? '')?.round();

  /// Montant payé par le client : prestation + frais de service.
  int? get clientTotal {
    if (serverClientTotal != null) return serverClientTotal;
    final price = prestationPrice;
    return price == null ? null : price + serviceFee;
  }

  /// Montant à payer selon le statut courant (frais de service inclus).
  String? get currentFeeAmount =>
      isAwaitingRealizationPayment ? clientTotal?.toString() : null;

  /// Aucun prestataire trouvé dans le rayon maximal : l'équipe Mison s'en occupe.
  bool get isSearchHandledByTeam => isPending && (searchExhaustedAt ?? '').isNotEmpty;

  /// Can rate: only completed orders without rating
  bool get canRate => isCompleted && clientRating == null;

  /// Commande active : un ouvrier est rattaché à la commande, qu'il l'ait
  /// acceptée lui-même (ACCEPTED) ou qu'un admin la lui ait affectée (ASSIGNED).
  bool get isActiveWithArtisan =>
      artisan != null &&
      (isAssigned ||
          isAccepted ||
          isAwaitingTravelPayment ||
          isInProgress ||
          isAwaitingRealizationPayment);

  /// Appel possible une fois que l'ouvrier a accepté : pas quand la commande
  /// lui est seulement affectée par un admin (ASSIGNED, en attente de confirmation).
  bool get canCall => isActiveWithArtisan && !isAssigned;

  /// Chat privé client ↔ ouvrier : dès qu'un ouvrier a accepté (pas en ASSIGNED).
  bool get canChat => isActiveWithArtisan && !isAssigned;

  /// L'ouvrier doit encore confirmer une commande que l'admin lui a affectée.
  bool get needsArtisanConfirmation => isAssigned && artisan != null;

  /// L'ouvrier peut démarrer la prestation (plus de paiement préalable).
  bool get canStart =>
      artisan != null && (isAssigned || isAccepted || isAwaitingTravelPayment);

  /// Le client peut annuler définitivement sa commande.
  /// Le client peut annuler tant que la prestation n'a pas commencé.
  bool get canCancelByClient =>
      isPending || isAssigned || isAccepted || isAwaitingTravelPayment;

  /// L'ouvrier peut se désister — après avoir accepté lui-même comme après une
  /// affectation par l'admin. La commande retourne dans le pool.
  /// Plus possible une fois arrivé chez le client : il doit commencer la
  /// prestation (ou passer par le support).
  bool get canReleaseByArtisan =>
      artisan != null &&
      (isAssigned || isAccepted || isAwaitingTravelPayment) &&
      (arrivedAt ?? '').isEmpty;

  /// Can track artisan location : dès que l'ouvrier est rattaché à la commande
  /// (accepté/affecté), pour que le client voie où il se trouve en approche.
  /// Moyen de paiement lisible (récapitulatif prestataire).
  String get paymentMethodLabel {
    switch (paymentMethod) {
      case 'WAVE':
        return 'Wave';
      case 'ORANGE_MONEY':
        return 'Orange Money';
      default:
        // Pour le moment, seul Wave est proposé au client.
        return isCompleted ? 'Wave' : 'Wave · en attente du paiement du client';
    }
  }

  /// Commande acceptée, prestation pas encore commencée : c'est la phase du
  /// trajet de l'ouvrier (« Aller chez le client » → arrivée → « Commencer »).
  bool get isBeforeStart => artisan != null && (isAssigned || isAccepted || isAwaitingTravelPayment);

  /// L'ouvrier a appuyé sur « Aller chez le client » et n'est pas encore arrivé.
  bool get isEnRoute => isBeforeStart && (enRouteAt ?? '').isNotEmpty && (arrivedAt ?? '').isEmpty;

  /// L'ouvrier est arrivé chez le client : il peut commencer la prestation.
  bool get hasArrived => isBeforeStart && (arrivedAt ?? '').isNotEmpty;

  /// Suivi en direct (mini-carte, position de l'ouvrier) : seulement pendant le
  /// trajet. Avant le départ et une fois arrivé, plus de carte des deux côtés.
  bool get canTrack => isEnRoute;
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
  String? professionName;
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
    this.professionName,
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
      professionName: json['profession_name']?.toString(),
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
        'profession_name': professionName,
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
  String? description; // facultative
  String serviceDate; // ISO8601 — ignoré si isImmediate
  bool isImmediate; // "Tout de suite" : le serveur fixe l'heure à maintenant
  String serviceAddress;
  double? latitude;
  double? longitude;
  String? artisanId; // UUID — prestataire souhaité

  MisonCreateOrderRequest({
    required this.service,
    this.description,
    required this.serviceDate,
    this.isImmediate = false,
    required this.serviceAddress,
    this.latitude,
    this.longitude,
    this.artisanId,
  });

  Map<String, dynamic> toJson() => {
        'service': service,
        if (description != null && description!.trim().isNotEmpty) 'description': description!.trim(),
        if (isImmediate) 'is_immediate': true else 'service_date': serviceDate,
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
  String? description; // facultative
  String serviceDate; // ISO8601
  String serviceAddress;

  MisonWorkerRequestModel({
    required this.service,
    required this.workerCount,
    this.description,
    required this.serviceDate,
    required this.serviceAddress,
  });

  Map<String, dynamic> toJson() => {
        'service': service,
        'worker_count': workerCount,
        if (description != null && description!.trim().isNotEmpty) 'description': description!.trim(),
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
