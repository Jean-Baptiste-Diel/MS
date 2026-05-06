import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../component/empty_error_state_widget.dart';

/// Écran de sélection de service (Type de main d'œuvre)
/// Affiche une grille de services disponibles depuis l'API Mison
class MisonServiceSelectionScreen extends StatefulWidget {
  const MisonServiceSelectionScreen({Key? key}) : super(key: key);

  @override
  State<MisonServiceSelectionScreen> createState() => _MisonServiceSelectionScreenState();
}

class _MisonServiceSelectionScreenState extends State<MisonServiceSelectionScreen> {
  List<MisonService> _services = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  Future<void> _fetchServices() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await getMisonServices();
      setState(() {
        _services = response.data ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarWidget(
        'Type de main d\'œuvre',
        textColor: Colors.white,
        textSize: 18,
        color: primaryColor,
        systemUiOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarColor: context.primaryColor,
        ),
        showBack: Navigator.canPop(context),
        backWidget: BackWidget(),
      ),
      body: Stack(
        children: [
          _buildBody(),
          Observer(
            builder: (context) => LoaderWidget().visible(appStore.isLoading.validate()),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return NoDataWidget(
        title: _error!,
        imageWidget: const ErrorStateWidget(),
        retryText: language.reload,
        onRetry: () {
          _fetchServices();
        },
      );
    }

    if (_services.isEmpty) {
      return NoDataWidget(
        title: 'Aucun service disponible',
        imageWidget: const EmptyStateWidget(),
      );
    }

    return AnimatedScrollView(
      onSwipeRefresh: () async {
        await _fetchServices();
        return await 2.seconds.delay;
      },
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      listAnimationType: ListAnimationType.FadeIn,
      fadeInConfiguration: FadeInConfiguration(duration: 2.seconds),
      children: [
        // Titre
        Text(
          'Type de main d\'œuvre',
          style: boldTextStyle(size: 18),
        ).paddingBottom(16),
        
        // Grille de services
        AnimatedWrap(
          runSpacing: 16,
          spacing: 16,
          itemCount: _services.length,
          listAnimationType: ListAnimationType.FadeIn,
          fadeInConfiguration: FadeInConfiguration(duration: 2.seconds),
          itemBuilder: (_, index) {
            final service = _services[index];
            return _ServiceGridItem(
              service: service,
              onTap: () {
                MisonBookingFormScreen(service: service).launch(context);
              },
            );
          },
        ).center(),
      ],
    );
  }
}

/// Widget pour afficher un service dans la grille
class _ServiceGridItem extends StatelessWidget {
  final MisonService service;
  final VoidCallback onTap;

  const _ServiceGridItem({
    required this.service,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = (context.width() - 64) / 3; // 3 colonnes avec padding
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: boxDecorationDefault(
          color: context.cardColor,
          borderRadius: radius(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icône/Image du service
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: service.imageUrl != null && service.imageUrl!.isNotEmpty
                  ? CachedImageWidget(
                      url: service.imageUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                    ).center()
                  : Icon(
                      _getIconForService(service.name ?? ''),
                      size: 28,
                      color: primaryColor,
                    ),
            ),
            8.height,
            // Nom du service
            Text(
              service.name ?? '',
              style: primaryTextStyle(size: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Retourne une icône par défaut selon le nom du service
  IconData _getIconForService(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('maçon') || name.contains('macon')) return Icons.construction;
    if (name.contains('plomb')) return Icons.plumbing;
    if (name.contains('électr') || name.contains('electr')) return Icons.electrical_services;
    if (name.contains('menuis')) return Icons.carpenter;
    if (name.contains('peintr') || name.contains('peinture')) return Icons.format_paint;
    if (name.contains('climati') || name.contains('froid')) return Icons.ac_unit;
    if (name.contains('carrel')) return Icons.grid_on;
    if (name.contains('ferron') || name.contains('soud')) return Icons.hardware;
    return Icons.handyman;
  }
}
