import 'package:booking_system_flutter/component/app_empty_state.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/newDashboard/dashboard_1/component/mison_artisan_list_component.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

class MisonArtisanListScreen extends StatefulWidget {
  const MisonArtisanListScreen({Key? key}) : super(key: key);

  @override
  State<MisonArtisanListScreen> createState() => _MisonArtisanListScreenState();
}

class _MisonArtisanListScreenState extends State<MisonArtisanListScreen> {
  List<MisonArtisanInfo> _all = [];
  List<MisonArtisanInfo> _filtered = [];
  bool _isLoading = true;
  bool _hasError = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final res = await getMisonArtisans();
      final list = res.data ?? [];
      setState(() { _all = list; _filtered = list; _isLoading = false; });
    } catch (_) {
      setState(() { _isLoading = false; _hasError = true; });
    }
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all.where((a) =>
              a.fullName.toLowerCase().contains(q) ||
              (a.service?.name?.toLowerCase().contains(q) ?? false)).toList();
    });
  }

  @override
  void setState(fn) { if (mounted) super.setState(fn); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Prestataires', style: boldTextStyle(color: Colors.white, size: 18)),
      ),
      body: DotGridBackground(
        child: Column(
        children: [
          // ── Barre de recherche ───────────────────────────────────────────
          Container(
            color: primaryColor,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: primaryTextStyle(size: 16),
                decoration: InputDecoration(
                  hintText: 'Recherchez un prestataire ou un service...',
                  hintStyle: secondaryTextStyle(size: 15),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.withValues(alpha: 0.7)),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),

          // ── Contenu ──────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _hasError
                    ? AppEmptyState(
                        type: AppEmptyStateType.error,
                        onRetry: _load,
                      )
                    : _filtered.isEmpty
                        ? AppEmptyState(
                            type: AppEmptyStateType.search,
                            title: _searchCtrl.text.isEmpty
                                ? 'Aucun prestataire disponible'
                                : 'Aucun résultat pour "${_searchCtrl.text}"',
                          )
                        : RefreshIndicator(
                            color: primaryColor,
                            onRefresh: _load,
                            child: GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 0.82,
                              ),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) => ArtisanCard(
                                artisan: _filtered[i],
                                width: double.infinity,
                              ),
                            ),
                          ),
          ),
        ],
        ),
      ),
    );
  }
}
