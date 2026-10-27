import 'package:booking_system_flutter/component/mison_account_sheets.dart' show showMisonConfirmSheet;
import 'package:booking_system_flutter/component/base_scaffold_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold;
import 'package:booking_system_flutter/screens/map/mison_location_picker_screen.dart';
import 'package:booking_system_flutter/services/favorite_places_store.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Noms proposés en un appui.
const _suggestedLabels = ['Maison', 'Bureau', 'Famille'];

IconData favoritePlaceIcon(String label) => switch (label.toLowerCase()) {
      'maison' => Icons.home_rounded,
      'bureau' => Icons.work_rounded,
      'famille' => Icons.family_restroom_rounded,
      _ => Icons.star_rounded,
    };

/// Nom du lieu favori (Maison, Bureau… ou libre). null : annulé.
Future<String?> askFavoritePlaceLabel(BuildContext context, {required String address, String? initial}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      void submit([String? value]) {
        final label = (value ?? ctrl.text).trim();
        if (label.isEmpty) {
          TopToast.show(message: 'Donnez un nom à ce lieu');
          return;
        }
        Navigator.pop(sheetContext, label);
      }

      return Container(
        decoration: BoxDecoration(
          color: sheetContext.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            20.height,
            Text('Ajouter aux favoris', style: boldTextStyle(size: 18)),
            6.height,
            Text(address, style: secondaryTextStyle(size: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            16.height,
            Wrap(
              spacing: 8,
              children: [
                for (final label in _suggestedLabels)
                  ActionChip(
                    avatar: Icon(favoritePlaceIcon(label), size: 18, color: kMisonGold),
                    label: Text(label),
                    onPressed: () => submit(label),
                  ),
              ],
            ),
            12.height,
            TextField(
              controller: ctrl,
              autofocus: initial != null,
              maxLength: 30,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                hintText: 'Ou un autre nom (ex. Chez maman)',
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.35)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kMisonGold, width: 1.5),
                ),
              ),
            ),
            20.height,
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMisonGold,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Enregistrer', style: boldTextStyle(color: Colors.white, size: 15)),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Enregistre le lieu après avoir demandé son nom. true : enregistré.
Future<bool> saveFavoritePlace(BuildContext context, {required String address, required double lat, required double lon}) async {
  final label = await askFavoritePlaceLabel(context, address: address);
  if (label == null) return false;
  final ok = await FavoritePlacesStore.add(FavoritePlace(label: label, address: address, lat: lat, lon: lon));
  if (!ok) {
    TopToast.show(
      message: 'Vous avez déjà ${FavoritePlacesStore.maxPlaces} lieux favoris : supprimez-en un dans votre profil.',
      type: TopToastType.error,
    );
    return false;
  }
  TopToast.show(message: '« $label » ajouté à vos lieux favoris.');
  return true;
}

/// Profil → « Mes lieux favoris » : ajouter (sur la carte), renommer, supprimer.
class MisonFavoritePlacesScreen extends StatefulWidget {
  const MisonFavoritePlacesScreen({super.key});

  @override
  State<MisonFavoritePlacesScreen> createState() => _MisonFavoritePlacesScreenState();
}

class _MisonFavoritePlacesScreenState extends State<MisonFavoritePlacesScreen> {
  List<FavoritePlace> _places = FavoritePlacesStore.load();

  void _reload() => setState(() => _places = FavoritePlacesStore.load());

  Future<void> _add() async {
    if (_places.length >= FavoritePlacesStore.maxPlaces) {
      TopToast.show(message: 'Vous avez déjà ${FavoritePlacesStore.maxPlaces} lieux favoris : supprimez-en un.');
      return;
    }
    final picked = await MisonLocationPickerScreen.open(context);
    if (picked == null || !mounted) return;
    await saveFavoritePlace(context, address: picked.address, lat: picked.lat, lon: picked.lon);
    _reload();
  }

  Future<void> _rename(FavoritePlace place) async {
    final label = await askFavoritePlaceLabel(context, address: place.address, initial: place.label);
    if (label == null) return;
    await FavoritePlacesStore.add(FavoritePlace(label: label, address: place.address, lat: place.lat, lon: place.lon));
    _reload();
  }

  Future<void> _remove(FavoritePlace place) async {
    final ok = await showMisonConfirmSheet(
      context,
      title: 'Supprimer « ${place.label} » ?',
      subtitle: 'Ce lieu ne sera plus proposé à vos prochaines commandes.',
      icon: Icons.delete_outline_rounded,
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (!ok) return;
    await FavoritePlacesStore.remove(place);
    _reload();
  }

  /// Lieu : icône sans rond, nom, adresse, suppression (comme les lignes du profil).
  Widget _placeRow(FavoritePlace place) {
    return InkWell(
      onTap: () => _rename(place),
      borderRadius: radius(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            SizedBox(width: 24, child: Icon(favoritePlaceIcon(place.label), size: 22, color: kMisonGold)),
            14.width,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(place.label, style: boldTextStyle(size: 16)),
                2.height,
                Text(place.address, style: secondaryTextStyle(size: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ).expand(),
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              onPressed: () => _remove(place),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBarTitle: 'Mes lieux favoris',
      useMisonHeader: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            'Vos adresses enregistrées vous sont proposées à chaque commande. Touchez un lieu pour le renommer.',
            style: secondaryTextStyle(size: 14),
          ),
          16.height,
          if (_places.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              decoration: boxDecorationWithRoundedCorners(
                borderRadius: radius(16),
                backgroundColor: context.cardColor,
                border: Border.all(color: context.dividerColor.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Icon(Icons.star_outline_rounded, size: 44, color: kMisonGold.withValues(alpha: 0.7)),
                  10.height,
                  Text('Aucun lieu favori', style: boldTextStyle(size: 16)),
                  4.height,
                  Text('Ajoutez votre maison, votre bureau…', style: secondaryTextStyle(size: 14)),
                ],
              ),
            )
          else
            // Même carte que les menus du profil : lignes séparées par un trait.
            Container(
              decoration: boxDecorationWithRoundedCorners(
                borderRadius: radius(16),
                backgroundColor: context.cardColor,
                border: Border.all(color: context.dividerColor.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _places.length; i++) ...[
                    _placeRow(_places[i]),
                    if (i != _places.length - 1)
                      Divider(height: 1, color: context.dividerColor.withValues(alpha: 0.5)),
                  ],
                ],
              ),
            ),
          20.height,
          AppButton(
            text: 'Ajouter un lieu',
            color: kMisonGold,
            textColor: Colors.white,
            width: context.width(),
            onTap: _add,
          ),
        ],
      ),
    );
  }
}
