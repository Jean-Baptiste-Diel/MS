/// Modèles pour l'API Mison Services
/// Endpoint: /api/services (GET)

class MisonServicesResponse {
  String? message;
  List<MisonService>? data;

  MisonServicesResponse({this.message, this.data});

  factory MisonServicesResponse.fromJson(Map<String, dynamic> json) {
    return MisonServicesResponse(
      message: json['message']?.toString(),
      data: json['data'] != null
          ? (json['data'] as List)
              .map((e) => MisonService.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

class MisonService {
  String? id; // UUID
  String? name;
  String? description;
  String? minPrice;
  String? imageUrl;
  bool? isAvailable;

  MisonService({
    this.id,
    this.name,
    this.description,
    this.minPrice,
    this.imageUrl,
    this.isAvailable,
  });

  factory MisonService.fromJson(Map<String, dynamic> json) {
    return MisonService(
      id: json['id']?.toString(),
      name: json['name']?.toString(),
      description: json['description']?.toString(),
      minPrice: json['min_price']?.toString(),
      imageUrl: json['image_url']?.toString(),
      isAvailable: json['is_available'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'min_price': minPrice,
        'image_url': imageUrl,
        'is_available': isAvailable,
      };

  num get minPriceValue => num.tryParse(minPrice ?? '0') ?? 0;
}
