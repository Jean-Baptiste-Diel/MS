import 'package:booking_system_flutter/utils/image_cache_key.dart';
import 'package:booking_system_flutter/component/mison_page_loader.dart';
import 'package:booking_system_flutter/utils/service_search.dart';
import 'dart:async';

import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../../booking/mison_search_service_screen.dart';
import '../../../notification/notification_screen.dart';

/// Carrousel de l'accueil : images réglées dans le back-office (« Images de
/// l'accueil »), indépendantes des services. Sans image côté serveur, l'image
/// Mison intégrée à l'app s'affiche.
class MisonSliderDashboardComponent extends StatefulWidget {
  final VoidCallback? callback;

  const MisonSliderDashboardComponent({Key? key, this.callback}) : super(key: key);

  @override
  State<MisonSliderDashboardComponent> createState() => _MisonSliderDashboardComponentState();
}

class _MisonSliderDashboardComponentState extends State<MisonSliderDashboardComponent> {
  PageController sliderPageController = PageController(initialPage: 0);
  int _currentPage = 0;
  Timer? _timer;
  final TextEditingController _searchCont = TextEditingController();

  /// Ouvre « Rechercher un service » avec le texte tapé, puis vide la barre.
  void _openSearch() {
    final query = _searchCont.text.trim();
    FocusScope.of(context).unfocus();
    MisonSearchServiceScreen(initialQuery: query).launch(context);
    _searchCont.clear();
    setState(() => _suggestions = []);
  }

  List<MisonService> _services = [];

  /// Images du carrousel : {image_url, service_id} (back-office).
  List<Map<String, dynamic>> _banners = [];
  bool _isLoading = true;

  /// Image de secours, intégrée à l'app.
  static const _fallbackBanner = 'assets/images/home_banner_mison.jpg';

  int get _slideCount => _banners.isEmpty ? 1 : _banners.length;

  /// Suggestions affichées sous la barre pendant la saisie.
  List<MisonService> _suggestions = [];

  /// Services correspondant à la saisie (classement partagé avec l'onglet Service).
  void _updateSuggestions(String value) {
    setState(() => _suggestions =
        value.trim().isEmpty ? [] : searchServices(_services, value).take(5).toList());
  }

  void _openService(MisonService service) {
    FocusScope.of(context).unfocus();
    _searchCont.clear();
    setState(() => _suggestions = []);
    MisonBookingFormScreen(service: service).launch(context);
  }

  @override
  void initState() {
    super.initState();
    _fetchServices();
    _fetchBanners();
  }

  Future<void> _fetchBanners() async {
    // D'abord la liste enregistrée à la dernière ouverture : affichée tout
    // de suite, images comprises (cache disque), même hors connexion.
    final saved = _withImage(getSavedHomeBanners());
    if (saved.isNotEmpty) {
      _banners = saved;
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoSlide());
    }
    try {
      final banners = _withImage(await getHomeBanners());
      if (!mounted) return;
      setState(() {
        _banners = banners;
        _isLoading = false;
        if (_currentPage >= _slideCount) _currentPage = 0;
      });
      _startAutoSlide();
      _precacheSlides();
    } catch (e) {
      // Hors connexion : la liste enregistrée reste affichée.
      log('Error fetching home banners: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static List<Map<String, dynamic>> _withImage(List<Map<String, dynamic>> banners) =>
      banners.where((b) => (b['image_url'] ?? '').toString().isNotEmpty).toList();

  /// Image touchée : ouvre la commande du service lié, s'il y en a un.
  void _openBanner(Map<String, dynamic> banner) {
    final serviceId = banner['service_id']?.toString();
    if (serviceId == null || serviceId.isEmpty) return;
    final service = _services.where((s) => s.id == serviceId).firstOrNull;
    if (service != null) MisonBookingFormScreen(service: service).launch(context);
  }

  Future<void> _fetchServices() async {
    try {
      // Réutilise le cache partagé de 10 min (getMisonServices) au lieu d'un
      // appel réseau dédié — évite de dupliquer la requête déjà faite par les
      // autres composants de l'accueil, ce qui ralentissait le chargement des
      // images du slider (bande passante saturée par des requêtes en double).
      final servicesResponse = await getMisonServices();
      if (!mounted) return;
      setState(() => _services = servicesResponse.data ?? []);
    } catch (e) {
      log('Error fetching services for search: $e');
    }
  }

  /// Précharge toutes les images du slider dès que la liste arrive, pour que
  /// le swipe/auto-slide n'affiche jamais de spinner entre deux diapos déjà
  /// vues — seule la 1ère image attend encore le réseau.
  void _precacheSlides() {
    if (!mounted) return;
    final width = (context.width() * MediaQuery.of(context).devicePixelRatio).round();
    for (final banner in _banners) {
      final url = banner['image_url']?.toString();
      if (url == null || url.isEmpty) continue;
      // Même clé que l'affichage (adresse sans la signature, qui change) :
      // l'image est gardée une seule fois et retrouvée hors connexion.
      precacheImage(
        CachedNetworkImageProvider(url, maxWidth: width, cacheKey: imageCacheKey(url)),
        context,
      ).catchError((_) {});
    }
  }

  void _startAutoSlide() {
    _timer?.cancel();
    if (getBoolAsync(AUTO_SLIDER_STATUS, defaultValue: true) && _slideCount >= 2) {
      _timer = Timer.periodic(const Duration(seconds: DASHBOARD_AUTO_SLIDER_SECOND), (Timer timer) {
        if (_currentPage < _slideCount - 1) {
          _currentPage++;
        } else {
          _currentPage = 0;
        }
        if (sliderPageController.hasClients) {
          sliderPageController.animateToPage(
            _currentPage,
            duration: const Duration(milliseconds: 950),
            curve: Curves.easeOutQuart,
          );
        }
      });

      sliderPageController.addListener(() {
        if (sliderPageController.hasClients) {
          _currentPage = sliderPageController.page!.toInt();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchCont.dispose();
    _timer?.cancel();
    sliderPageController.dispose();
    super.dispose();
  }

  Decoration get commonDecoration {
    return boxDecorationDefault(
      color: context.cardColor,
    );
  }

  /// Carrousel de l'accueil, arrondi, avec une marge.
  Widget getSliderWidget() {
    const double sliderHeight = 190;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: sliderHeight,
          width: double.infinity,
          child: Stack(
            children: [
              _isLoading
                  ? Container(
                      color: kMisonGold.withValues(alpha: 0.1),
                      child: const MisonPageLoader(),
                    )
                  : _banners.isNotEmpty
                      ? PageView.builder(
                          controller: sliderPageController,
                          itemCount: _banners.length,
                          itemBuilder: (context, index) {
                            final banner = _banners[index];
                            return GestureDetector(
                              onTap: () => _openBanner(banner),
                              child: CachedImageWidget(
                                url: banner['image_url']?.toString() ?? '',
                                height: sliderHeight,
                                width: context.width(),
                                fit: BoxFit.cover,
                              ),
                            );
                          },
                        )
                      : Image.asset(_fallbackBanner, height: sliderHeight, width: context.width(), fit: BoxFit.cover),
              if (_banners.length > 1)
                Positioned(
                  bottom: 6,
                  left: 8,
                  child: DotIndicator(
                    pageController: sliderPageController,
                    pages: _banners,
                    indicatorColor: kMisonGold,
                    unselectedIndicatorColor: white,
                    currentBoxShape: BoxShape.rectangle,
                    boxShape: BoxShape.rectangle,
                    borderRadius: radius(16),
                    currentBorderRadius: radius(16),
                    currentDotSize: 70,
                    currentDotWidth: 20,
                    dotSize: 40,
                  ).scale(scale: 0.4),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        8.height,
        getSliderWidget(),
        // Vraie barre de recherche (comme dans « Rechercher un service ») :
        // on tape ici, la validation ouvre les résultats.
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCont,
            textInputAction: TextInputAction.search,
            onChanged: _updateSuggestions,
            onSubmitted: (_) => _openSearch(),
            decoration: InputDecoration(
              hintText: 'Rechercher un service...',
              hintStyle: secondaryTextStyle(),
              prefixIcon: const Icon(Icons.search, color: kMisonGold),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, color: kMisonGold),
                onPressed: _openSearch,
              ),
              filled: true,
              fillColor: context.cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kMisonGold, width: 1.5),
              ),
            ),
          ),
        ),
        // Propositions pendant la saisie : un appui ouvre la commande du service.
        if (_suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  for (final service in _suggestions)
                    ListTile(
                      dense: true,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedImageWidget(url: service.imageUrl ?? '', height: 36, width: 36, fit: BoxFit.cover),
                      ),
                      title: Text(service.name ?? '', style: primaryTextStyle(size: 15, weight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: kMisonGold),
                      onTap: () => _openService(service),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.search, color: kMisonGold),
                    title: Text(
                      'Voir tous les résultats pour « ${_searchCont.text.trim()} »',
                      style: secondaryTextStyle(size: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: _openSearch,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Cloche des notifications (avec compteur de non-lus) pour l'en-tête d'accueil.
class MisonNotificationBell extends StatelessWidget {
  const MisonNotificationBell({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: boxDecorationDefault(color: context.cardColor, shape: BoxShape.circle),
      height: 40,
      width: 40,
      padding: const EdgeInsets.all(8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Couleurs de la marque : cloche et pastille dorées.
          ic_notification.iconImage(size: 24, color: kMisonGold).center(),
          Observer(builder: (context) {
            return Positioned(
              top: -14,
              right: -10,
              child: appStore.unreadCount.validate() > 0
                  ? Container(
                      padding: const EdgeInsets.all(4),
                      child: FittedBox(
                        child: Text(appStore.unreadCount.toString(),
                            style: primaryTextStyle(size: 12, color: Colors.white)),
                      ),
                      // Liseré blanc : la pastille dorée se détache de la cloche dorée.
                      decoration: BoxDecoration(
                        color: kMisonGold,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    )
                  : const Offstage(),
            );
          }),
        ],
      ),
    ).onTap(() {
      NotificationScreen().launch(context);
    });
  }
}
