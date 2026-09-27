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

/// Slider qui affiche les images des services Mison
/// Design identique à SliderDashboardComponent1
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
  }

  List<MisonService> _services = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  Future<void> _fetchServices() async {
    try {
      // Réutilise le cache partagé de 10 min (getMisonServices) au lieu d'un
      // appel réseau dédié — évite de dupliquer la requête déjà faite par les
      // autres composants de l'accueil, ce qui ralentissait le chargement des
      // images du slider (bande passante saturée par des requêtes en double).
      final servicesResponse = await getMisonServices();
      setState(() {
        _services = servicesResponse.data ?? [];
        _isLoading = false;
      });
      _startAutoSlide();
      _precacheSlides();
    } catch (e) {
      log('Error fetching services for slider: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Précharge toutes les images du slider dès que la liste arrive, pour que
  /// le swipe/auto-slide n'affiche jamais de spinner entre deux diapos déjà
  /// vues — seule la 1ère image attend encore le réseau.
  void _precacheSlides() {
    if (!mounted) return;
    final width = (context.width() * MediaQuery.of(context).devicePixelRatio).round();
    for (final service in _services) {
      final url = service.imageUrl;
      if (url == null || url.isEmpty) continue;
      precacheImage(
        CachedNetworkImageProvider(url, maxWidth: width),
        context,
      ).catchError((_) {});
    }
  }

  void _startAutoSlide() {
    if (getBoolAsync(AUTO_SLIDER_STATUS, defaultValue: true) && _services.length >= 2) {
      _timer = Timer.periodic(const Duration(seconds: DASHBOARD_AUTO_SLIDER_SECOND), (Timer timer) {
        if (_currentPage < _services.length - 1) {
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

  /// Carrousel des services, arrondi, avec une marge.
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
                      child: const Center(
                          child: CircularProgressIndicator(color: kMisonGold, strokeWidth: 2)),
                    )
                  : _services.isNotEmpty
                      ? PageView.builder(
                          controller: sliderPageController,
                          itemCount: _services.length,
                          itemBuilder: (context, index) {
                            final service = _services[index];
                            return GestureDetector(
                              onTap: () {
                                MisonBookingFormScreen(service: service).launch(context);
                              },
                              child: CachedImageWidget(
                                url: service.imageUrl ?? '',
                                height: sliderHeight,
                                width: context.width(),
                                fit: BoxFit.cover,
                              ),
                            );
                          },
                        )
                      : CachedImageWidget(url: '', height: sliderHeight, width: context.width()),
              if (_services.length > 1)
                Positioned(
                  bottom: 6,
                  left: 8,
                  child: DotIndicator(
                    pageController: sliderPageController,
                    pages: _services,
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
