import 'package:booking_system_flutter/component/animated_dropdown.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Indicatif téléphonique : liste animée des pays (Sénégal en premier, avec
/// recherche) qui se déplie sous la ligne du numéro, comme à l'inscription.
///
/// [fieldBuilder] construit la ligne indicatif + numéro ; il reçoit l'état
/// ouvert et la fonction qui ouvre/ferme la liste.
class MisonCountryCodeDropdown extends StatelessWidget {
  final Country selected;
  final ValueChanged<Country> onChanged;
  final Widget Function(BuildContext context, bool isOpen, VoidCallback toggle) fieldBuilder;

  const MisonCountryCodeDropdown({
    Key? key,
    required this.selected,
    required this.onChanged,
    required this.fieldBuilder,
  }) : super(key: key);

  static List<Country>? _cache;

  static List<Country> get _countries {
    return _cache ??= () {
      final list = CountryService().getAll();
      final sn = list.where((c) => c.countryCode == 'SN').toList();
      return [...sn, ...list.where((c) => c.countryCode != 'SN')];
    }();
  }

  /// Le pays chargé depuis le profil n'a parfois que l'indicatif : on retrouve
  /// le pays correspondant (Sénégal en priorité pour +221).
  String get _selectedCode {
    if (selected.countryCode.isNotEmpty) return selected.countryCode;
    return _countries
            .where((c) => c.phoneCode == selected.phoneCode)
            .map((c) => c.countryCode)
            .firstOrNull ??
        'SN';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedDropdown<String>(
      hint: 'Indicatif',
      value: _selectedCode,
      options: _countries
          .map((c) => DropdownOption(
              c.countryCode,
              '${c.flagEmoji}  +${c.phoneCode}  ${c.getTranslatedName(context) ?? c.name}'))
          .toList(),
      accentColor: kMisonGold,
      searchable: true,
      searchHint: 'Rechercher un pays ou un indicatif',
      onChanged: (code) {
        final country = CountryService().findByCode(code);
        if (country != null) onChanged(country);
      },
      triggerBuilder: (context, _, isOpen, toggle) => fieldBuilder(context, isOpen, toggle),
    );
  }
}

/// Bouton « 🇸🇳 +221 ▾ » à placer à gauche du champ numéro.
class MisonCountryCodeButton extends StatelessWidget {
  final Country country;
  final bool isOpen;
  final VoidCallback onTap;
  final double height;

  const MisonCountryCodeButton({
    Key? key,
    required this.country,
    required this.isOpen,
    required this.onTap,
    this.height = 58,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final flag = country.countryCode.isNotEmpty
        ? country.flagEmoji
        : (country.phoneCode == '221' ? '🇸🇳' : '');
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOpen ? kMisonGold : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${flag.isNotEmpty ? '$flag ' : ''}+${country.phoneCode}',
                style: primaryTextStyle(size: 15)),
            2.width,
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 20, color: isOpen ? kMisonGold : textSecondaryColorGlobal),
            ),
          ],
        ),
      ),
    );
  }
}
