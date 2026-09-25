import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Option d'un [AnimatedDropdown] : valeur envoyée + libellé affiché.
class DropdownOption<T> {
  final T value;
  final String label;

  const DropdownOption(this.value, this.label);
}

/// Menu déroulant animé : la liste se déplie sous le bouton
/// (SizeTransition) et la flèche pivote à l'ouverture.
class AnimatedDropdown<T> extends StatefulWidget {
  final String hint;
  final T? value;
  final List<DropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool hasError;
  final Color accentColor;

  /// Affiche un champ de recherche en haut de la liste (listes longues).
  final bool searchable;
  final String searchHint;

  /// Remplace le bouton par défaut (ex. indicatif intégré au champ téléphone).
  /// Reçoit l'option choisie, l'état ouvert et la fonction qui ouvre/ferme.
  final Widget Function(BuildContext context, DropdownOption<T>? selected,
      bool isOpen, VoidCallback toggle)? triggerBuilder;

  const AnimatedDropdown({
    Key? key,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.accentColor,
    this.hasError = false,
    this.searchable = false,
    this.searchHint = 'Rechercher',
    this.triggerBuilder,
  }) : super(key: key);

  @override
  State<AnimatedDropdown<T>> createState() => _AnimatedDropdownState<T>();
}

class _AnimatedDropdownState<T> extends State<AnimatedDropdown<T>>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isOpen = false;
  final TextEditingController _searchCont = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchCont.dispose();
    super.dispose();
  }

  void _toggle() {
    FocusScope.of(context).unfocus();
    setState(() => _isOpen = !_isOpen);
    _isOpen ? _controller.forward() : _controller.reverse();
  }

  void _select(T value) {
    FocusScope.of(context).unfocus();
    widget.onChanged(value);
    setState(() {
      _isOpen = false;
      _searchCont.clear();
    });
    _controller.reverse();
  }

  List<DropdownOption<T>> get _filteredOptions {
    final q = _searchCont.text.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options
        .where((o) => o.label.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final selected =
        widget.options.where((o) => o.value == widget.value).firstOrNull;

    final Color borderColor = widget.hasError
        ? Colors.red
        : (_isOpen || selected != null)
            ? accent
            : Colors.grey.withValues(alpha: 0.15);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bouton
        if (widget.triggerBuilder != null)
          widget.triggerBuilder!(context, selected, _isOpen, _toggle)
        else
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: borderColor,
                  width: (_isOpen || widget.hasError) ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: selected == null
                        ? Text(widget.hint,
                            overflow: TextOverflow.ellipsis,
                            style: secondaryTextStyle(size: 14))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Le libellé reste visible en petit au-dessus de la valeur
                              Text(widget.hint,
                                  style: secondaryTextStyle(size: 11)),
                              2.height,
                              Text(selected.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: primaryTextStyle(size: 14)),
                            ],
                          ),
                  ),
                  RotationTransition(
                    turns:
                        Tween<double>(begin: 0, end: 0.5).animate(_controller),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: _isOpen ? accent : textSecondaryColorGlobal),
                  ),
                ],
              ),
            ),
          ),

        // Liste animée
        SizeTransition(
          sizeFactor: _animation,
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
              color: context.cardColor,
              border: Border.all(color: accent.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.searchable)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                      child: TextField(
                        controller: _searchCont,
                        onChanged: (_) => setState(() {}),
                        style: primaryTextStyle(size: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.searchHint,
                          hintStyle: secondaryTextStyle(size: 13),
                          prefixIcon: Icon(Icons.search_rounded,
                              size: 20, color: textSecondaryColorGlobal),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.25)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.25)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: accent, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  Flexible(
                    child: Builder(builder: (context) {
                      final options = _filteredOptions;
                      if (options.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Aucun résultat',
                              style: secondaryTextStyle(size: 13)),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final o = options[i];
                          final isSelected = o.value == widget.value;
                          return InkWell(
                            onTap: () => _select(o.value),
                            child: Container(
                              width: double.infinity,
                              color: isSelected
                                  ? accent.withValues(alpha: 0.10)
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      o.label,
                                      style: isSelected
                                          ? boldTextStyle(
                                              size: 14, color: accent)
                                          : primaryTextStyle(size: 14),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_rounded,
                                        size: 18, color: accent),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
