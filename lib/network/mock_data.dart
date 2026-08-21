/// Fichier contenant les données mockées pour le développement
/// Ces données seront utilisées lorsque les endpoints backend sont en cours de développement
/// 

import 'package:booking_system_flutter/model/category_model.dart';
import 'package:booking_system_flutter/model/dashboard_model.dart';
import 'package:booking_system_flutter/model/booking_data_model.dart';
import 'package:booking_system_flutter/model/booking_list_model.dart';
import 'package:booking_system_flutter/model/booking_detail_model.dart';
import 'package:booking_system_flutter/model/service_data_model.dart';
import 'package:booking_system_flutter/model/user_data_model.dart';
import 'package:booking_system_flutter/model/pagination_model.dart';

/// Flag pour activer/désactiver les données mockées
/// Mettre à false pour utiliser l'API Mison réelle
const bool USE_MOCK_DATA = false;

/// ============================================
/// MOCK DATA - CATEGORIES
/// ============================================

List<CategoryData> getMockCategories() {
  return [
    CategoryData(
      id: 1,
      name: 'Plomberie',
      description: 'Services de plomberie professionnels',
      categoryImage: 'https://images.unsplash.com/photo-1607472586893-edb57bdc0e39?w=400',
      color: '#2196F3',
      isFeatured: 1,
      status: 1,
      services: 15,
    ),
    CategoryData(
      id: 2,
      name: 'Électricité',
      description: 'Installation et réparation électrique',
      categoryImage: 'https://images.unsplash.com/photo-1621905251189-08b45d6a269e?w=400',
      color: '#FF9800',
      isFeatured: 1,
      status: 1,
      services: 12,
    ),
    CategoryData(
      id: 3,
      name: 'Ménage',
      description: 'Services de nettoyage à domicile',
      categoryImage: 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=400',
      color: '#4CAF50',
      isFeatured: 1,
      status: 1,
      services: 8,
    ),
    CategoryData(
      id: 4,
      name: 'Peinture',
      description: 'Peinture intérieure et extérieure',
      categoryImage: 'https://images.unsplash.com/photo-1562259949-e8e7689d7828?w=400',
      color: '#9C27B0',
      isFeatured: 0,
      status: 1,
      services: 6,
    ),
    CategoryData(
      id: 5,
      name: 'Jardinage',
      description: 'Entretien de jardin et espaces verts',
      categoryImage: 'https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=400',
      color: '#8BC34A',
      isFeatured: 1,
      status: 1,
      services: 10,
    ),
    CategoryData(
      id: 6,
      name: 'Menuiserie',
      description: 'Travaux de bois et menuiserie',
      categoryImage: 'https://images.unsplash.com/photo-1504148455328-c376907d081c?w=400',
      color: '#795548',
      isFeatured: 0,
      status: 1,
      services: 7,
    ),
    CategoryData(
      id: 7,
      name: 'Climatisation',
      description: 'Installation et maintenance climatisation',
      categoryImage: 'https://images.unsplash.com/photo-1585771724684-38269d6639fd?w=400',
      color: '#00BCD4',
      isFeatured: 1,
      status: 1,
      services: 5,
    ),
    CategoryData(
      id: 8,
      name: 'Serrurerie',
      description: 'Ouverture de porte et installation serrures',
      categoryImage: 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=400',
      color: '#607D8B',
      isFeatured: 0,
      status: 1,
      services: 4,
    ),
    CategoryData(
      id: 9,
      name: 'Déménagement',
      description: 'Services de déménagement professionnel',
      categoryImage: 'https://images.unsplash.com/photo-1600518464441-9154a4dea21b?w=400',
      color: '#E91E63',
      isFeatured: 0,
      status: 1,
      services: 3,
    ),
    CategoryData(
      id: 10,
      name: 'Maçonnerie',
      description: 'Travaux de maçonnerie et construction',
      categoryImage: 'https://images.unsplash.com/photo-1504307651254-35680f356dfd?w=400',
      color: '#FF5722',
      isFeatured: 0,
      status: 1,
      services: 9,
    ),
  ];
}

CategoryResponse getMockCategoryResponse() {
  return CategoryResponse(
    categoryList: getMockCategories(),
    pagination: Pagination(
      currentPage: 1,
      totalPages: 1,
      totalItems: 10,
    ),
  );
}

/// ============================================
/// MOCK DATA - PROVIDERS (ARTISANS)
/// ============================================

List<UserData> getMockProviders() {
  return [
    UserData(
      id: 1,
      firstName: 'Mamadou',
      lastName: 'Diallo',
      displayName: 'Mamadou Diallo',
      email: 'mamadou.diallo@mison.app',
      contactNumber: '+221771234567',
      profileImage: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
      userType: 'provider',
      address: 'Dakar, Sénégal',
      cityName: 'Dakar',
      providersServiceRating: 4.8,
      isFeatured: 1,
      isVerifyProvider: 1,
      designation: 'Plombier Expert',
      description: 'Plus de 10 ans d\'expérience en plomberie',
    ),
    UserData(
      id: 2,
      firstName: 'Fatou',
      lastName: 'Ndiaye',
      displayName: 'Fatou Ndiaye',
      email: 'fatou.ndiaye@mison.app',
      contactNumber: '+221772345678',
      profileImage: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
      userType: 'provider',
      address: 'Thiès, Sénégal',
      cityName: 'Thiès',
      providersServiceRating: 4.9,
      isFeatured: 1,
      isVerifyProvider: 1,
      designation: 'Spécialiste Ménage',
      description: 'Services de nettoyage professionnel',
    ),
    UserData(
      id: 3,
      firstName: 'Ibrahima',
      lastName: 'Sow',
      displayName: 'Ibrahima Sow',
      email: 'ibrahima.sow@mison.app',
      contactNumber: '+221773456789',
      profileImage: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
      userType: 'provider',
      address: 'Saint-Louis, Sénégal',
      cityName: 'Saint-Louis',
      providersServiceRating: 4.7,
      isFeatured: 0,
      isVerifyProvider: 1,
      designation: 'Électricien Certifié',
      description: 'Installation et dépannage électrique',
    ),
    UserData(
      id: 4,
      firstName: 'Aminata',
      lastName: 'Fall',
      displayName: 'Aminata Fall',
      email: 'aminata.fall@mison.app',
      contactNumber: '+221774567890',
      profileImage: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400',
      userType: 'provider',
      address: 'Dakar, Sénégal',
      cityName: 'Dakar',
      providersServiceRating: 4.6,
      isFeatured: 1,
      isVerifyProvider: 1,
      designation: 'Peintre Décoratrice',
      description: 'Peinture et décoration intérieure',
    ),
    UserData(
      id: 5,
      firstName: 'Ousmane',
      lastName: 'Ba',
      displayName: 'Ousmane Ba',
      email: 'ousmane.ba@mison.app',
      contactNumber: '+221775678901',
      profileImage: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=400',
      userType: 'provider',
      address: 'Ziguinchor, Sénégal',
      cityName: 'Ziguinchor',
      providersServiceRating: 4.5,
      isFeatured: 0,
      isVerifyProvider: 1,
      designation: 'Jardinier Paysagiste',
      description: 'Création et entretien de jardins',
    ),
  ];
}

/// ============================================
/// MOCK DATA - SERVICES
/// ============================================

List<ServiceData> getMockServices() {
  return [
    ServiceData(
      id: 1,
      name: 'Réparation fuite d\'eau',
      description: 'Réparation rapide de toutes fuites d\'eau. Service disponible 24h/24.',
      categoryId: 1,
      categoryName: 'Plomberie',
      providerId: 1,
      providerName: 'Mamadou Diallo',
      providerImage: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
      price: 15000,
      discount: 10,
      duration: '60',
      type: 'fixed',
      status: 1,
      isFeatured: 1,
      totalRating: 4.8,
      totalReview: 45,
      attachments: [
        'https://images.unsplash.com/photo-1607472586893-edb57bdc0e39?w=600',
      ],
    ),
    ServiceData(
      id: 2,
      name: 'Installation prise électrique',
      description: 'Installation et remplacement de prises électriques aux normes.',
      categoryId: 2,
      categoryName: 'Électricité',
      providerId: 3,
      providerName: 'Ibrahima Sow',
      providerImage: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
      price: 10000,
      discount: 0,
      duration: '45',
      type: 'fixed',
      status: 1,
      isFeatured: 1,
      totalRating: 4.7,
      totalReview: 32,
      attachments: [
        'https://images.unsplash.com/photo-1621905251189-08b45d6a269e?w=600',
      ],
    ),
    ServiceData(
      id: 3,
      name: 'Nettoyage complet maison',
      description: 'Nettoyage professionnel de votre maison ou appartement.',
      categoryId: 3,
      categoryName: 'Ménage',
      providerId: 2,
      providerName: 'Fatou Ndiaye',
      providerImage: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
      price: 25000,
      discount: 15,
      duration: '180',
      type: 'hourly',
      status: 1,
      isFeatured: 1,
      totalRating: 4.9,
      totalReview: 78,
      attachments: [
        'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=600',
      ],
    ),
    ServiceData(
      id: 4,
      name: 'Peinture chambre',
      description: 'Peinture complète d\'une chambre standard (jusqu\'à 15m²).',
      categoryId: 4,
      categoryName: 'Peinture',
      providerId: 4,
      providerName: 'Aminata Fall',
      providerImage: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400',
      price: 50000,
      discount: 20,
      duration: '480',
      type: 'fixed',
      status: 1,
      isFeatured: 0,
      totalRating: 4.6,
      totalReview: 25,
      attachments: [
        'https://images.unsplash.com/photo-1562259949-e8e7689d7828?w=600',
      ],
    ),
    ServiceData(
      id: 5,
      name: 'Entretien jardin mensuel',
      description: 'Entretien mensuel de votre jardin: tonte, taille, arrosage.',
      categoryId: 5,
      categoryName: 'Jardinage',
      providerId: 5,
      providerName: 'Ousmane Ba',
      providerImage: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=400',
      price: 35000,
      discount: 0,
      duration: '240',
      type: 'fixed',
      status: 1,
      isFeatured: 1,
      totalRating: 4.5,
      totalReview: 18,
      attachments: [
        'https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=600',
      ],
    ),
    ServiceData(
      id: 6,
      name: 'Débouchage canalisation',
      description: 'Débouchage de canalisations bouchées avec équipement professionnel.',
      categoryId: 1,
      categoryName: 'Plomberie',
      providerId: 1,
      providerName: 'Mamadou Diallo',
      providerImage: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
      price: 20000,
      discount: 5,
      duration: '90',
      type: 'fixed',
      status: 1,
      isFeatured: 0,
      totalRating: 4.8,
      totalReview: 52,
      attachments: [
        'https://images.unsplash.com/photo-1607472586893-edb57bdc0e39?w=600',
      ],
    ),
  ];
}

List<ServiceData> getMockFeaturedServices() {
  return getMockServices().where((s) => s.isFeatured == 1).toList();
}

/// ============================================
/// MOCK DATA - SLIDERS
/// ============================================

List<SliderModel> getMockSliders() {
  return [
    SliderModel(
      id: 1,
      title: 'Bienvenue sur Mison',
      description: 'Trouvez les meilleurs ouvriers près de chez vous',
      sliderImage: 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=800',
      status: 1,
      type: 'category',
      typeId: 1,
    ),
    SliderModel(
      id: 2,
      title: 'Promotion -20%',
      description: 'Sur tous les services de peinture ce mois-ci!',
      sliderImage: 'https://images.unsplash.com/photo-1562259949-e8e7689d7828?w=800',
      status: 1,
      type: 'service',
      typeId: 4,
    ),
    SliderModel(
      id: 3,
      title: 'Nouveaux ouvriers',
      description: 'Découvrez nos ouvriers vérifiés',
      sliderImage: 'https://images.unsplash.com/photo-1504307651254-35680f356dfd?w=800',
      status: 1,
      type: 'provider',
      typeId: 1,
    ),
  ];
}

/// ============================================
/// MOCK DATA - CUSTOMER REVIEWS
/// ============================================

List<DashboardCustomerReview> getMockCustomerReviews() {
  return [
    DashboardCustomerReview(
      id: 1,
      customerId: 100,
      customerName: 'Awa Diop',
      profileImage: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
      rating: 5.0,
      review: 'Excellent travail! Mamadou a réparé ma fuite en moins d\'une heure. Je recommande vivement!',
      serviceId: 1,
      serviceName: 'Réparation fuite d\'eau',
      bookingId: 101,
      createdAt: '2026-02-10T14:30:00Z',
    ),
    DashboardCustomerReview(
      id: 2,
      customerId: 101,
      customerName: 'Moussa Sarr',
      profileImage: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=400',
      rating: 4.5,
      review: 'Très professionnelle, ma maison est impeccable. Fatou fait un travail remarquable.',
      serviceId: 3,
      serviceName: 'Nettoyage complet maison',
      bookingId: 102,
      createdAt: '2026-02-08T10:15:00Z',
    ),
    DashboardCustomerReview(
      id: 3,
      customerId: 102,
      customerName: 'Khady Mbaye',
      profileImage: 'https://images.unsplash.com/photo-1489424731084-a5d8b219a5bb?w=400',
      rating: 5.0,
      review: 'Installation parfaite et rapide. Ibrahima connaît vraiment son métier!',
      serviceId: 2,
      serviceName: 'Installation prise électrique',
      bookingId: 103,
      createdAt: '2026-02-05T16:45:00Z',
    ),
  ];
}

/// ============================================
/// MOCK DATA - BOOKINGS (RESERVATIONS)
/// ============================================

List<BookingData> getMockBookings() {
  return [
    BookingData(
      id: 1001,
      customerId: 100,
      customerName: 'Utilisateur Test',
      serviceId: 1,
      serviceName: 'Réparation fuite d\'eau',
      providerId: 1,
      providerName: 'Mamadou Diallo',
      providerImage: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
      status: 'pending',
      statusLabel: 'En attente',
      date: '2026-02-15 00:00:00',
      bookingSlot: '09:00:00',
      address: '123 Rue de Dakar, Dakar',
      amount: 15000,
      totalAmount: 15000,
      discount: 10,
      paymentStatus: 'pending',
      type: 'fixed',
      description: 'Fuite sous l\'évier de la cuisine',
      handyman: [],
      serviceAttachments: ['https://images.unsplash.com/photo-1607472586893-edb57bdc0e39?w=600'],
    ),
    BookingData(
      id: 1002,
      customerId: 100,
      customerName: 'Utilisateur Test',
      serviceId: 3,
      serviceName: 'Nettoyage complet maison',
      providerId: 2,
      providerName: 'Fatou Ndiaye',
      providerImage: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
      status: 'accept',
      statusLabel: 'Acceptée',
      date: '2026-02-14 00:00:00',
      bookingSlot: '14:00:00',
      address: '456 Avenue Bourguiba, Dakar',
      amount: 25000,
      totalAmount: 21250,
      discount: 15,
      paymentStatus: 'pending',
      type: 'hourly',
      description: 'Nettoyage complet appartement 3 chambres',
      handyman: [],
      serviceAttachments: ['https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=600'],
    ),
    BookingData(
      id: 1003,
      customerId: 100,
      customerName: 'Utilisateur Test',
      serviceId: 2,
      serviceName: 'Installation prise électrique',
      providerId: 3,
      providerName: 'Ibrahima Sow',
      providerImage: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
      status: 'on_going',
      statusLabel: 'En cours',
      date: '2026-02-12 00:00:00',
      bookingSlot: '10:00:00',
      address: '789 Boulevard Général de Gaulle, Dakar',
      amount: 10000,
      totalAmount: 10000,
      discount: 0,
      paymentStatus: 'advance_paid',
      paidAmount: 3000,
      type: 'fixed',
      description: 'Installation de 2 prises dans le salon',
      handyman: [],
      serviceAttachments: ['https://images.unsplash.com/photo-1621905251189-08b45d6a269e?w=600'],
    ),
    BookingData(
      id: 1004,
      customerId: 100,
      customerName: 'Utilisateur Test',
      serviceId: 4,
      serviceName: 'Peinture chambre',
      providerId: 4,
      providerName: 'Aminata Fall',
      providerImage: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400',
      status: 'completed',
      statusLabel: 'Terminée',
      date: '2026-02-08 00:00:00',
      bookingSlot: '08:00:00',
      address: '321 Rue Cheikh Anta Diop, Dakar',
      amount: 50000,
      totalAmount: 40000,
      discount: 20,
      paymentStatus: 'paid',
      type: 'fixed',
      description: 'Peinture chambre principale - couleur bleu ciel',
      totalRating: 5.0,
      totalReview: 1,
      handyman: [],
      serviceAttachments: ['https://images.unsplash.com/photo-1562259949-e8e7689d7828?w=600'],
    ),
    BookingData(
      id: 1005,
      customerId: 100,
      customerName: 'Utilisateur Test',
      serviceId: 5,
      serviceName: 'Entretien jardin mensuel',
      providerId: 5,
      providerName: 'Ousmane Ba',
      providerImage: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=400',
      status: 'cancelled',
      statusLabel: 'Annulée',
      date: '2026-02-05 00:00:00',
      bookingSlot: '07:00:00',
      address: '555 Rue Faidherbe, Dakar',
      amount: 35000,
      totalAmount: 35000,
      discount: 0,
      paymentStatus: 'pending',
      type: 'fixed',
      reason: 'Client indisponible',
      handyman: [],
      serviceAttachments: ['https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=600'],
    ),
  ];
}

BookingData? getMockUpcomingBooking() {
  // Retourner la première réservation en attente ou acceptée comme prochaine réservation
  final bookings = getMockBookings();
  try {
    return bookings.firstWhere(
      (b) => b.status == 'pending' || b.status == 'accept',
    );
  } catch (e) {
    return null;
  }
}

BookingListResponse getMockBookingListResponse() {
  return BookingListResponse(
    data: getMockBookings(),
    pagination: Pagination(
      currentPage: 1,
      totalPages: 1,
      totalItems: 5,
    ),
  );
}

/// ============================================
/// MOCK DATA - DASHBOARD RESPONSE
/// ============================================

DashboardResponse getMockDashboardResponse() {
  return DashboardResponse(
    category: getMockCategories(),
    provider: getMockProviders(),
    service: getMockServices(),
    featuredServices: getMockFeaturedServices(),
    slider: getMockSliders(),
    dashboardCustomerReview: getMockCustomerReviews(),
    upcomingData: getMockUpcomingBooking(),
    notificationUnreadCount: 3,
    isEmailVerified: 1,
    shops: [],
    referralRule: true,
    promotionalBanner: [],
  );
}

/// ============================================
/// UTILITAIRES MOCK DATA
/// ============================================

/// Simule un délai réseau pour les données mockées
Future<T> simulateNetworkDelay<T>(T data, {int milliseconds = 500}) async {
  await Future.delayed(Duration(milliseconds: milliseconds));
  return data;
}

/// Filtre les réservations par statut
List<BookingData> getMockBookingsByStatus(String status) {
  if (status.isEmpty || status == 'all') {
    return getMockBookings();
  }
  return getMockBookings().where((b) => b.status == status).toList();
}

/// Obtient une catégorie par ID
CategoryData? getMockCategoryById(int id) {
  try {
    return getMockCategories().firstWhere((c) => c.id == id);
  } catch (e) {
    return null;
  }
}

/// Obtient un service par ID
ServiceData? getMockServiceById(int id) {
  try {
    return getMockServices().firstWhere((s) => s.id == id);
  } catch (e) {
    return null;
  }
}

/// Obtient un prestataire par ID
UserData? getMockProviderById(int id) {
  try {
    return getMockProviders().firstWhere((p) => p.id == id);
  } catch (e) {
    return null;
  }
}

/// Obtient une réservation par ID
BookingData? getMockBookingById(int id) {
  try {
    return getMockBookings().firstWhere((b) => b.id == id);
  } catch (e) {
    return null;
  }
}

/// Obtient les services par catégorie
List<ServiceData> getMockServicesByCategory(int categoryId) {
  return getMockServices().where((s) => s.categoryId == categoryId).toList();
}

/// Obtient les services par prestataire
List<ServiceData> getMockServicesByProvider(int providerId) {
  return getMockServices().where((s) => s.providerId == providerId).toList();
}

/// ============================================
/// MOCK DATA - BOOKING DETAIL RESPONSE
/// ============================================

/// Génère une réponse de détail de réservation mockée
BookingDetailResponse getMockBookingDetailResponse(int bookingId) {
  BookingData? booking = getMockBookingById(bookingId);
  
  // Si la réservation n'existe pas, retourner une réponse par défaut
  if (booking == null) {
    booking = getMockBookings().first;
  }
  
  // Obtenir le service et le prestataire correspondants
  ServiceData? service = getMockServiceById(booking.serviceId ?? 1);
  UserData? provider = getMockProviderById(booking.providerId ?? 1);
  
  // Créer le client mocké
  UserData customer = UserData(
    id: 100,
    firstName: 'Utilisateur',
    lastName: 'Test',
    displayName: 'Utilisateur Test',
    email: 'test@mison.app',
    contactNumber: '+221771234567',
    profileImage: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400',
    userType: 'user',
    address: 'Dakar, Sénégal',
  );
  
  // Créer les activités de réservation mockées
  List<BookingActivity> activities = [
    BookingActivity(
      id: 1,
      bookingId: bookingId,
      activityType: 'add_booking',
      activityMessage: 'Réservation créée',
      datetime: '2026-02-10 10:00:00',
      createdAt: '2026-02-10T10:00:00Z',
    ),
  ];
  
  // Ajouter des activités selon le statut
  if (booking.status == 'accept' || booking.status == 'on_going' || booking.status == 'completed') {
    activities.add(BookingActivity(
      id: 2,
      bookingId: bookingId,
      activityType: 'accept_booking',
      activityMessage: 'Réservation acceptée par le prestataire',
      datetime: '2026-02-10 11:00:00',
      createdAt: '2026-02-10T11:00:00Z',
    ));
  }
  
  if (booking.status == 'on_going' || booking.status == 'completed') {
    activities.add(BookingActivity(
      id: 3,
      bookingId: bookingId,
      activityType: 'start_booking',
      activityMessage: 'Le service a commencé',
      datetime: '2026-02-12 09:00:00',
      createdAt: '2026-02-12T09:00:00Z',
    ));
  }
  
  if (booking.status == 'completed') {
    activities.add(BookingActivity(
      id: 4,
      bookingId: bookingId,
      activityType: 'complete_booking',
      activityMessage: 'Service terminé avec succès',
      datetime: '2026-02-12 12:00:00',
      createdAt: '2026-02-12T12:00:00Z',
    ));
  }
  
  if (booking.status == 'cancelled') {
    activities.add(BookingActivity(
      id: 2,
      bookingId: bookingId,
      activityType: 'cancel_booking',
      activityMessage: 'Réservation annulée: ${booking.reason ?? "Raison non spécifiée"}',
      datetime: '2026-02-05 14:00:00',
      createdAt: '2026-02-05T14:00:00Z',
    ));
  }
  
  return BookingDetailResponse(
    bookingDetail: booking,
    service: service,
    providerData: provider,
    customer: customer,
    bookingActivity: activities,
    handymanData: provider != null ? [provider] : [],
    ratingData: [],
    customerReview: null,
    taxes: [],
    serviceProof: [],
    earnPoints: 0,
  );
}
