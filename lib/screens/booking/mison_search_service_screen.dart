import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/app_empty_state.dart';
import 'package:booking_system_flutter/component/cached_image_widget.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/model/mison_service_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_booking_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

class MisonSearchServiceScreen extends StatefulWidget {
  final bool showBackButton;

  const MisonSearchServiceScreen({Key? key, this.showBackButton = true}) : super(key: key);

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
      backgroundColor: Colors.transparent,
      // Logo centré + fond de la page, comme les autres pages
      appBar: MisonAppBar(
        title: 'Rechercher un service',
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: kMisonDark),
                onPressed: () => finish(context),
              )
            : null,
      ),
      body: DotGridBackground(
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCont,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Rechercher un service...',
                hintStyle: secondaryTextStyle(),
                prefixIcon: const Icon(Icons.search, color: kMisonGold),
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
                // Bordure dorée quand on écrit dans le champ
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kMisonGold, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_isLoading)
            Expanded(
                child: Center(
                    child: LoaderWidget(colors: const [kMisonDark, kMisonGold])))
          else if (_filtered.isEmpty)
            Expanded(
              child: AppEmptyState(
                type: _searchCont.text.isEmpty
                    ? AppEmptyStateType.empty
                    : AppEmptyStateType.search,
                title: _searchCont.text.isEmpty
                    ? 'Aucun service disponible'
                    : 'Aucun résultat pour "${_searchCont.text}"',
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
      ),
    );
  }
}

class _ServiceResultTile extends StatefulWidget {
  final MisonService service;
  const _ServiceResultTile({required this.service});

  @override
  State<_ServiceResultTile> createState() => _ServiceResultTileState();
}

/// Carte d'un service : description sur 2 lignes ; la flèche › la déplie en
/// entier (et la replie). Un appui sur le reste de la carte ouvre la commande.
class _ServiceResultTileState extends State<_ServiceResultTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final hasDescription = (service.description ?? '').isNotEmpty;
    return GestureDetector(
      onTap: () => MisonBookingFormScreen(service: service).launch(context),
      child: Container(
        decoration: boxDecorationDefault(
          color: context.cardColor,
          borderRadius: radius(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Row(
            // Dépliée : l'image reste en haut, le texte s'allonge dessous.
            crossAxisAlignment: _expanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              CachedImageWidget(
                url: service.imageUrl ?? '',
                height: 128,
                width: 128,
                fit: BoxFit.cover,
                circle: false,
              ),
              16.width,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        service.name ?? '',
                        style: boldTextStyle(size: 16),
                        maxLines: _expanded ? null : 1,
                        overflow: _expanded ? null : TextOverflow.ellipsis,
                      ),
                      if (hasDescription) ...[
                        4.height,
                        Text(
                          service.description!,
                          style: secondaryTextStyle(size: 14),
                          maxLines: _expanded ? null : 2,
                          overflow: _expanded ? null : TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // › : déplie / replie la description (ne lance pas la commande)
              IconButton(
                tooltip: _expanded ? 'Réduire' : 'Voir toute la description',
                onPressed: hasDescription ? () => setState(() => _expanded = !_expanded) : null,
                icon: AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.chevron_right, color: kMisonGold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
