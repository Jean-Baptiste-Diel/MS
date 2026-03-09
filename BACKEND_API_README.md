# Documentation API - Mison User App

Version: 1.0
Date: 2026-02-23

But: Documenter précisément les endpoints attendus par l'application mobile Flutter (client), fournir les structures JSON request/response, et indiquer les mappings de champs nécessaires pour intégration backend.

--

## Règles générales
- Base URL: (ex) `https://api.mison.app/api/`
- Auth: `Authorization: Bearer <token>` (header) pour endpoints protégés
- Format: JSON, sauf multipart/form-data pour upload de fichiers
- Codes d'état: 200 OK (success), 4xx pour erreurs clients, 401 pour auth

--

## Catégorie (Category)
- Endpoint: `GET category-list?page={page}&per_page={per_page}`
- Auth: facultatif
- Description: retourne la liste des catégories / catégories principales

Request: aucun body

Response (200):

```
{
  "data": [
    {
      "id": 1,
      "name": "Plomberie",
      "description": "Services de plomberie professionnels",
      "category_image": "https://.../img.jpg",
      "is_featured": 0,
      "status": 1,
      "services": 15
    }
  ],
  "pagination": { "current_page":1, "per_page":50, "total":123 }
}
```

Client model attendu: `CategoryData` (`id`, `name`, `description`, `category_image`, `services`).

Remarque: si votre backend renvoie `image_url`, mappez-le en `category_image`.

--

## Sous-catégorie (Subcategory)
- Endpoint: `GET subcategory-list?category_id={catId}&per_page=all`
- Response: même shape que `category-list` (liste de `CategoryData`)

Usage: filtrage et navigation dans les écrans `ViewAllServiceScreen`.

--

## Service — Liste / Recherche
- Endpoint (client): `GET search-list` avec query params
- Query parameters supportés (doivent être acceptés par backend) :
  - `category_id` (csv)
  - `subcategory_id`
  - `provider_id`
  - `search` (texte)
  - `page`, `per_page`
  - `is_price_min`, `is_price_max`
  - `is_rating`, `is_featured`
  - `latitude`, `longitude`
  - `shop_id`, `zone_id`

Example request:
```
GET /api/search-list?category_id=1&search=robinet&page=1&per_page=10&latitude=..&longitude=..
```

Response (200):
```
{
  "data": [
    {
      "id": 10,
      "name": "Réparation Robinet",
      "category_id": 1,
      "category_name": "Plomberie",
      "price": 15000,
      "description": "Dépannage plomberie",
      "provider_id": 5,
      "provider_name": "Jean",
      "provider_image": "https://...",
      "service_attchments": ["https://..."],
      "is_featured": 0,
      "is_slot": 0,
      "total_review": 2,
      "total_rating": 4.5,
      "created_at": "2026-02-15T12:00:00Z"
    }
  ],
  "pagination": {...}
}
```

Client model attendu: `ServiceData`.

Remarque importante: l'API que vous avez fourni (`/api/services`) retourne des champs nommés différemment (`image_url`, `min_price`, `is_available`). Le backend doit exposer l'API utilisée par le client (`search-list`) ou fournir un mapping/compatibilité:
- `image_url` -> `provider_image` ou `service_attchments` (array)
- `min_price` -> `price`
- `is_available` -> `status` (ex: `1` disponible)

--

## Service — Détail
- Endpoint (client): `POST service-detail`
- Body: `{"service_id": <id>, "customer_id": <id?>}`
- Response: objet `ServiceDetailResponse` contenant `serviceDetail` et champs supplémentaires (slots, packages, provider info).

--

## Auth / Inscription Artisan
- Endpoint: `POST auth/register/artisan` (multipart/form-data)
- Champs requis (client-side checks):
  - `email`, `password`, `phone`, `first_name`, `last_name`, `service` (clé), `experience_years`, `bio`, `address`
  - Fichiers: `profile_picture` (selfie), `identity_document`

Notes:
- L'app vérifie la présence de `service` (clé fournie par l'UI). Backend doit accepter `service` (id ou slug). Préférence: accepter `service` comme `service_id` (int). Si backend n'accepte que le nom, le client devra envoyer le nom (ou on mettra à jour le client pour envoyer l'id).

--

## Booking / Commande
- Endpoint création: `POST booking-save`
- Body attendu (exemple minimal):
```
{
  "service_id": 10,
  "provider_id": 5,
  "date": "2026-03-01",
  "slot": "09:00-10:00",
  "booking_address_id": 12 OR "address": "...",
  "user_id": 123,
  "payment_type": "stripe", // ou wallet, cash
  "coupon_code": "OPTIONNEL"
}
```
- Après création, le client appelle `booking-detail` pour obtenir l'objet complet.

Autres endpoints:
- `GET booking-list?per_page=&page=&status=`
- `POST booking-update` (modifier statut/détails)
- `GET get-location?booking_id=` (position provider)

--

## Paiement
- Endpoints backend attendus:
  - `POST wallet-top-up` (pour rechargement de wallet)
  - `POST save-payment` (enregistrer paiement après callback)
  - `GET payment-list?booking_id={id}` (liste paiements)

Gateways gérées côté client: Stripe, Paystack, Razorpay, Flutterwave, CinetPay, Sadad, PhonePe. Pour Flutterwave la vérification peut se faire via l'API Flutterwave ou via webhook.

Remarque: backend doit fournir des webhooks sécurisés ou des endpoints de verification pour éviter la fraude.

--

## Favoris / Wishlist
- `POST save-favourite` (body: `service_id`, `customer_id`)
- `POST delete-favourite`
- `GET user-favourite-provider` (liste prestataires favoris)

--

## Providers / Users
- `GET user-detail?id={id}&login_user_id={userId?}` => `getProviderDetail` côté client

--

## Uploads / Multipart
- Endpoints qui reçoivent fichiers doivent accepter `multipart/form-data` (profile_picture, identity_document, attachments).

--

## Format d'erreur recommandé
- 200 (success) -> standard JSON (data/message)
- 4xx -> `{ "message": "Erreur...", "errors": { "field": ["msg"] } }`
- 401 -> `{ "message": "Unauthorized" }`

--

## Table de mapping rapide (Backend → Client)
- `image_url` -> `category_image` / `provider_image` / `service_attchments`
- `min_price` -> `price`
- `is_available` -> `status` (1/0) ou `is_featured` selon logique

--

## Exemples concrets à implémenter / vérifier
1. `GET /api/category-list?page=1&per_page=50` — retourne `CategoryResponse`.
2. `GET /api/subcategory-list?category_id=12&per_page=all` — retourne list de sous-catégories.
3. `GET /api/search-list?...` — supports filters listés ci-dessus.
4. `POST /api/service-detail` — body `{ "service_id": <id> }`.
5. `POST multipart /api/auth/register/artisan` — champs et fichiers décrits ci-dessus.
6. `POST /api/booking-save` — crée réservation puis `POST /api/booking-detail` pour récupérer.
7. `POST /api/save-payment` et `GET /api/payment-list?booking_id=`

--

## Notes finales et recommandations
- Préférez renvoyer les champs avec les mêmes noms que l'app attend (`category_image`, `provider_image`, `price`, `service_attchments`) pour éviter mapping côté client.
- Si vous modifiez les clés, fournissez une documentation de mapping précise ou ajoutez des endpoints de compatibilité (`/api/search-list` attendu par le client).
- Assurez-vous que tous les endpoints protégés valident `Authorization: Bearer <token>` et renvoient 401 sur token invalide.

Si vous souhaitez, je peux générer un fichier swagger/openapi minimal basé sur ce contrat.

--

## Implémentation Frontend - Modèles et Fonctions API Mison

Les modèles et fonctions suivants ont été ajoutés au frontend pour consommer l'API Mison existante:

### Fichiers créés

1. **`lib/model/mison_service_model.dart`** - Modèle pour les services Mison
2. **`lib/model/mison_order_model.dart`** - Modèles pour les commandes Mison
3. **`lib/network/rest_apis.dart`** - Fonctions API ajoutées (région "Mison API")

### Modèle MisonService (GET /api/services)

```dart
class MisonService {
  String? id;        // UUID
  String? name;
  String? minPrice;
  String? imageUrl;
  bool? isAvailable;
}
```

### Modèle MisonOrder (GET /api/orders, POST /api/orders)

```dart
class MisonOrder {
  String? id;              // UUID
  MisonClient? client;
  MisonServiceInfo? service;
  MisonArtisanInfo? artisan;
  String? description;
  String? serviceDate;     // ISO8601
  String? serviceAddress;
  String? status;          // PENDING, ASSIGNED, ACCEPTED, REJECTED, IN_PROGRESS, COMPLETED, CANCELLED
  int? clientRating;
  String? clientReview;
  String? createdAt;
  String? updatedAt;
}
```

### Fonctions API ajoutées (rest_apis.dart)

| Fonction | Endpoint | Description |
|----------|----------|-------------|
| `getMisonServices()` | `GET /api/services` | Liste des services disponibles |
| `getMisonOrders({status?})` | `GET /api/orders` | Liste des commandes (filtre optionnel par status) |
| `getMisonOrderDetail(orderId)` | `GET /api/orders/{id}` | Détails d'une commande |
| `createMisonOrder(request)` | `POST /api/orders` | Créer une nouvelle commande |
| `artisanDecisionMisonOrder(orderId, decision)` | `POST /api/orders/{id}/artisan-decision` | Décision artisan (APPROVE/REJECT) |
| `rateMisonOrder(orderId, rating, review)` | `POST /api/orders/{id}/rate` | Noter une commande complétée |

### Exemple d'utilisation

```dart
// Récupérer les services
final servicesResponse = await getMisonServices();
for (var service in servicesResponse.data ?? []) {
  print('${service.name} - ${service.minPrice}');
}

// Créer une commande
final orderRequest = MisonCreateOrderRequest(
  service: 'uuid-du-service',
  description: 'Réparation robinet cuisine',
  serviceDate: '2026-03-01T10:00:00Z',
  serviceAddress: '123 Rue Example, Ville',
);
final orderResponse = await createMisonOrder(orderRequest);

// Récupérer les commandes du client
final ordersResponse = await getMisonOrders(status: 'PENDING');

// Noter une commande
await rateMisonOrder('uuid-commande', 5, 'Excellent travail!');
```

### Status des commandes

| Status | Description |
|--------|-------------|
| `PENDING` | Commande en attente d'attribution |
| `ASSIGNED` | Artisan assigné, en attente de décision |
| `ACCEPTED` | Artisan a accepté |
| `REJECTED` | Artisan a refusé |
| `IN_PROGRESS` | Travail en cours |
| `COMPLETED` | Terminée |
| `CANCELLED` | Annulée |
