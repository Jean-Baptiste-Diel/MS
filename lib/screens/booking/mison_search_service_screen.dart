import 'package:booking_system_flutter/utils/service_search.dart';
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

  /// Texte tapé dans la barre de recherche de l'accueil.
  final String initialQuery;

  const MisonSearchServiceScreen({Key? key, this.showBackButton = true, this.initialQuery = ''}) : super(key: key);

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
    _searchCont.text = widget.initialQuery;
    _loadServices();
    _searchCont.addListener(_onSearchChanged);
    _focusNode.addListener(() => setState(() {}));
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
        // Recherche venue de l'accueil : filtre dès le chargement.
        if (_searchCont.text.isNotEmpty) _onSearchChanged();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged() {
    // Liste filtrée et classée comme les suggestions de l'accueil
    // (accents ignorés, noms qui commencent par le texte en premier).
    setState(() => _filtered = searchServices(_allServices, _searchCont.text));
  }

  /// Suggestions affichées sous la barre pendant la saisie (champ actif).
  bool get _showSuggestions =>
      _focusNode.hasFocus && _searchCont.text.trim().isNotEmpty && _filtered.isNotEmpty;

  void _openService(MisonService service) {
    _focusNode.unfocus();
    MisonBookingFormScreen(service: service).launch(context);
  }

  Widget _buildSuggestions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
            for (final service in _filtered.take(5))
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
              // Ferme les suggestions : la liste complète reste dessous.
              onTap: () => _focusNode.unfocus(),
            ),
          ],
        ),
      ),
    );
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
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _focusNode.unfocus(),
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
          // Suggestions pendant la saisie, comme la barre de l'accueil.
          if (_showSuggestions) _buildSuggestions(),
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
