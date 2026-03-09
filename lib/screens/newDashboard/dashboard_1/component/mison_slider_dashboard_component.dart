import 'dart:async';
import 'dart:convert';

import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';

import '../../../notification/notification_screen.dart';
import '../../../service/search_service_screen.dart';

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

  List<MisonService> _services = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  Future<void> _fetchServices() async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (appStore.token.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${appStore.token}';
      }

      final uri = Uri.parse('https://api.mison.app/api/services');
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final servicesResponse = MisonServicesResponse.fromJson(body);
        setState(() {
          _services = servicesResponse.data ?? [];
          _isLoading = false;
        });
        _startAutoSlide();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      log('Error fetching services for slider: $e');
      setState(() => _isLoading = false);
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
    _timer?.cancel();
    sliderPageController.dispose();
    super.dispose();
  }

  Decoration get commonDecoration {
    return boxDecorationDefault(
      color: context.cardColor,
    );
  }

  Widget getSliderWidget() {
    return SizedBox(
      height: 300,
      width: context.width(),
      child: Stack(
        children: [
          _isLoading
              ? Container(
                  height: 250,
                  width: context.width(),
                  color: primaryColor.withOpacity(0.1),
                  child: const Center(child: CircularProgressIndicator()),
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
                            height: 250,
                            width: context.width(),
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    )
                  : CachedImageWidget(url: '', height: 250, width: context.width()),
          if (_services.length > 1)
            Positioned(
              bottom: 25,
              left: 16,
              child: DotIndicator(
                pageController: sliderPageController,
                pages: _services,
                indicatorColor: primaryColor,
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
          if (appStore.isLoggedIn)
            Positioned(
              top: context.statusBarHeight + 16,
              right: 16,
              child: Container(
                decoration: boxDecorationDefault(color: context.cardColor, shape: BoxShape.circle),
                height: 36,
                padding: const EdgeInsets.all(8),
                width: 36,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ic_notification.iconImage(size: 24, color: primaryColor).center(),
                    Observer(builder: (context) {
                      return Positioned(
                        top: -20,
                        right: -10,
                        child: appStore.unreadCount.validate() > 0
                            ? Container(
                                padding: const EdgeInsets.all(4),
                                child: FittedBox(
                                  child: Text(appStore.unreadCount.toString(), style: primaryTextStyle(size: 12, color: Colors.white)),
                                ),
                                decoration: boxDecorationDefault(color: Colors.red, shape: BoxShape.circle),
                              )
                            : const Offstage(),
                      );
                    })
                  ],
                ),
              ).onTap(() {
                NotificationScreen().launch(context);
              }),
            )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        getSliderWidget(),
        Row(
          children: [
            Observer(
              builder: (context) {
                return AppButton(
                  padding: const EdgeInsets.all(0),
                  width: context.width(),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: commonDecoration,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ic_location.iconImage(color: appStore.isDarkMode ? Colors.white : Colors.black),
                        8.width,
                        Text(
                          appStore.isCurrentLocation ? getStringAsync(CURRENT_ADDRESS) : language.lblLocationOff,
                          style: secondaryTextStyle(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ).expand(),
                        8.width,
                        ic_active_location.iconImage(size: 24, color: appStore.isCurrentLocation ? primaryColor : grey),
                      ],
                    ),
                  ),
                  onTap: () async {
                    locationWiseService(context, () {
                      widget.callback?.call();
                    });
                  },
                );
              },
            ).expand(),
            16.width,
            GestureDetector(
              onTap: () {
                SearchServiceScreen().launch(context);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: commonDecoration,
                child: ic_search.iconImage(color: primaryColor),
              ),
            ),
          ],
        ).paddingAll(16),
      ],
    );
  }
}
