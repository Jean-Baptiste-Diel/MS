import 'package:booking_system_flutter/component/base_scaffold_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

import '../main.dart';

/// Choix de la langue, au style Mison (logo en haut, cartes blanches, or).
class LanguagesScreen extends StatefulWidget {
  @override
  LanguagesScreenState createState() => LanguagesScreenState();
}

class LanguagesScreenState extends State<LanguagesScreen> {
  /// Nom de chaque langue dans sa propre langue.
  static const _nativeNames = {
    'fr': 'Français',
    'en': 'English',
    'ar': 'العربية',
    'hi': 'हिन्दी',
    'de': 'Deutsch',
  };

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  Future<void> _select(LanguageDataModel lang) async {
    final code = lang.languageCode;
    if (code == null || code == appStore.selectedLanguageCode) return;
    await appStore.setLanguage(code);
    if (!mounted) return;
    setState(() {});
    finish(context, true);
  }

  @override
  Widget build(BuildContext context) {
    // Français en premier, puis l'ordre habituel.
    final languages = [...localeLanguageList]
      ..sort((a, b) => (a.languageCode == 'fr' ? 0 : 1).compareTo(b.languageCode == 'fr' ? 0 : 1));

    return AppScaffold(
      appBarTitle: language.language,
      useMisonHeader: true,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: languages.length,
        separatorBuilder: (_, __) => 10.height,
        itemBuilder: (_, i) {
          final lang = languages[i];
          final selected = lang.languageCode == appStore.selectedLanguageCode;
          return Material(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _select(lang),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? kMisonGold : Colors.grey.withValues(alpha: 0.15),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    if ((lang.flag ?? '').isNotEmpty)
                      ClipOval(child: Image.asset(lang.flag!, width: 32, height: 32, fit: BoxFit.cover))
                    else
                      const Icon(Icons.language_rounded, color: kMisonGold, size: 30),
                    14.width,
                    Expanded(
                      child: Text(
                        _nativeNames[lang.languageCode] ?? lang.name ?? '',
                        style: boldTextStyle(size: 16, color: kMisonDark),
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? kMisonGold : Colors.grey.shade400,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
