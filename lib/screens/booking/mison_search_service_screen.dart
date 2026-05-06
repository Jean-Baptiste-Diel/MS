import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';

class MisonSearchServiceScreen extends StatefulWidget {
  const MisonSearchServiceScreen({Key? key}) : super(key: key);

  @override
  State<MisonSearchServiceScreen> createState() => _MisonSearchServiceScreenState();
}

class _MisonSearchServiceScreenState extends State<MisonSearchServiceScreen> {
  final TextEditingController _searchCont = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<MisonService> _allServices = [];
  List<MisonService> _filtered = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadServices();
    _searchCont.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCont.removeListener(_onSearchChanged);
    _searchCont.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final response = await getMisonServices();
      if (mounted) {
        setState(() {
          _allServices = response.data ?? [];
          _filtered = _allServices;
          _isLoading = false;
        });
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchCont.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filtered = _allServices;
      } else {
        _filtered = _allServices.where((s) {
          final name = (s.name ?? '').toLowerCase();
          final desc = (s.description ?? '').toLowerCase();
          return name.contains(query) || desc.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      appBar: appBarWidget(
        'Rechercher un service',
        textColor: Colors.white,
        color: primaryColor,
        systemUiOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarColor: primaryColor,
        ),
        showBack: true,
        backWidget: BackWidget(),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCont,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Rechercher un service...',
                hintStyle: secondaryTextStyle(),
                prefixIcon: Icon(Icons.search, color: primaryColor),
                suffixIcon: _searchCont.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _searchCont.clear(),
                      )
                    : null,
                filled: true,
                fillColor: context.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_filtered.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _searchCont.text.isEmpty
                      ? 'Aucun service disponible'
                      : 'Aucun résultat pour "${_searchCont.text}"',
                  style: secondaryTextStyle(),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final service = _filtered[index];
                  return _ServiceResultTile(service: service);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ServiceResultTile extends StatelessWidget {
  final MisonService service;
  const _ServiceResultTile({required this.service});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => MisonBookingFormScreen(service: service).launch(context),
      child: Container(
        decoration: boxDecorationDefault(
          color: context.cardColor,
          borderRadius: radius(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: CachedImageWidget(
                url: service.imageUrl ?? '',
                height: 80,
                width: 80,
                fit: BoxFit.cover,
                circle: false,
              ),
            ),
            16.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name ?? '',
                    style: boldTextStyle(size: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (service.description != null && service.description!.isNotEmpty) ...[
                    4.height,
                    Text(
                      service.description!,
                      style: secondaryTextStyle(size: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  8.height,
                  Text(
                    'À partir de ${service.minPriceValue.toStringAsFixed(0)} FCFA',
                    style: boldTextStyle(color: primaryColor, size: 13),
                  ),
                  8.height,
                ],
              ),
            ),
            16.width,
            Icon(Icons.chevron_right, color: primaryColor),
            8.width,
          ],
        ),
      ),
    );
  }
}
