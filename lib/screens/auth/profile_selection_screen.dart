import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/screens/auth/artisan_sign_up_screen.dart';
import 'package:booking_system_flutter/screens/auth/sign_up_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';

// Couleurs de la marque (logo)
const Color _kBrandGold = Color(0xFFC49716);
const Color _kBrandDark = Color(0xFF3A3A3A);

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({Key? key}) : super(key: key);

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  String? _selected;

  void _continue() {
    if (_selected == null) return;
    if (_selected == 'WORKER') {
      ArtisanSignUpScreen().launch(context);
    } else {
      SignUpScreen(initialAccountType: 'PARTICULIER').launch(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      extendBodyBehindAppBar: true,
      body: DotGridBackground(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _ProfileCard(
                          type: 'WORKER',
                          isSelected: _selected == 'WORKER',
                          assetIcon: ic_artisan,
                          title: 'Ouvrier / Prestataire',
                          tag: 'Je propose des services',
                          description:
                              'Plombier, électricien, peintre… Rejoignez le réseau Mison, '
                              'recevez des demandes clients dans votre zone et gérez vos chantiers depuis l\'app.',
                          features: const [
                            'Recevez des demandes',
                            'Gérez vos chantiers',
                            'Développez votre activité',
                          ],
                          accentColor: _kBrandGold,
                          bgColors: const [Color(0xFFFFF8E1), Colors.white],
                          onTap: () => setState(() => _selected = 'WORKER'),
                        ),
                        const SizedBox(height: 14),
                        _ProfileCard(
                          type: 'INDIVIDUAL',
                          isSelected: _selected == 'INDIVIDUAL',
                          assetIcon: ic_profile2,
                          title: 'Particulier',
                          tag: 'Je cherche un ouvrier',
                          description:
                              'Publiez votre projet en quelques secondes, comparez des prestataires '
                              'vérifiés et réservez le professionnel qu\'il vous faut — rapidement et en toute confiance.',
                          features: const [
                            'Devis gratuits',
                            'Ouvriers vérifiés',
                            'Paiement sécurisé',
                          ],
                          accentColor: _kBrandDark,
                          bgColors: const [Color(0xFFF2F2F2), Colors.white],
                          onTap: () => setState(() => _selected = 'INDIVIDUAL'),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            _ContinueButton(
              enabled: _selected != null,
              selectedType: _selected,
              onTap: _continue,
            ),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 240,
      backgroundColor: const Color(0xFFFFFFFF),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        statusBarColor: Colors.transparent,
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded,
            color: Colors.black, size: 24),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _HeaderBackground(),
      ),
    );
  }
}

// ── Collapsible Header ────────────────────────────────────────────────────────

class _HeaderBackground extends StatelessWidget {
  const _HeaderBackground();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 4, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [_logo(), 12.width, _brand()]),
              18.height,
              Text(
                'Qui êtes-vous ?',
                style: TextStyle(
                  color: appTextPrimaryColor,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              8.height,
              Text(
                'Sélectionnez votre profil pour une expérience adaptée.',
                style: TextStyle(
                  color: appTextSecondaryColor,
                  fontSize: 15,
                  height: 1.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logo() => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
              colors: [_kBrandGold, _kBrandGold.withValues(alpha: 0.65)]),
          boxShadow: [
            BoxShadow(
                color: _kBrandGold.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: const Icon(Icons.home_work_rounded, color: Colors.white, size: 18),
      );

  Widget _brand() => RichText(
        text: TextSpan(children: [
          TextSpan(
            text: 'Mi',
            style: TextStyle(
                color: _kBrandDark,
                fontSize: 21,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5),
          ),
          TextSpan(
            text: 'son',
            style: TextStyle(
                color: _kBrandGold,
                fontSize: 21,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5),
          ),
        ]),
      );
}

// ── Profile Card ─────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String type;
  final bool isSelected;
  final String assetIcon;
  final String title;
  final String tag;
  final String description;
  final List<String> features;
  final Color accentColor;
  final List<Color> bgColors;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.type,
    required this.isSelected,
    required this.assetIcon,
    required this.title,
    required this.tag,
    required this.description,
    required this.features,
    required this.accentColor,
    required this.bgColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: bgColors),
          border: Border.all(
            color: isSelected
                ? accentColor.withValues(alpha: 0.65)
                : borderColor,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.22),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Stack(
          children: [
            // Decorative radial glow (top-right corner)
            Positioned(
              top: -36,
              right: -36,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    accentColor.withValues(alpha: isSelected ? 0.14 : 0.04),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Always-visible compact row ─────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Icon circle
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor.withValues(
                              alpha: isSelected ? 0.16 : 0.08),
                          border: Border.all(
                            color: accentColor.withValues(
                                alpha: isSelected ? 0.55 : 0.18),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Image.asset(
                            assetIcon,
                            width: 26,
                            height: 26,
                            color: isSelected
                                ? accentColor
                                : accentColor.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      14.width,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tag (sans fond arrondi)
                            Text(
                              tag,
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                              ),
                            ),
                            6.height,
                            Text(
                              title,
                              style: TextStyle(
                                color: appTextPrimaryColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      12.width,
                      // Selection indicator
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              isSelected ? accentColor : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? accentColor
                                : Colors.black.withValues(alpha: 0.15),
                            width: 1.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                      color:
                                          accentColor.withValues(alpha: 0.5),
                                      blurRadius: 8)
                                ]
                              : [],
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ],
                  ),

                  // ── Expanded section: only when selected ───────────────
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 280),
                    sizeCurve: Curves.easeOutCubic,
                    firstChild:
                        const SizedBox(width: double.infinity, height: 0),
                    secondChild: _expandedSection(),
                    crossFadeState: isSelected
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expandedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        16.height,
        // Separator
        Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accentColor.withValues(alpha: 0.35),
                Colors.transparent,
              ],
              stops: const [0, 0.7],
            ),
          ),
        ),
        14.height,
        // Description
        Text(
          description,
          style: TextStyle(
            color: appTextSecondaryColor,
            fontSize: 15,
            height: 1.65,
          ),
        ),
        14.height,
        // Feature pills : côte à côte, un tiers de largeur chacune
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < features.length; i++) ...[
                if (i > 0) 6.width,
                Expanded(
                  child: _FeaturePill(label: features[i], accentColor: accentColor),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final String label;
  final Color accentColor;

  const _FeaturePill({required this.label, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: accentColor.withValues(alpha: 0.12),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded,
              size: 18, color: accentColor.withValues(alpha: 0.85)),
          4.height,
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              color: accentColor.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Continue Button ───────────────────────────────────────────────────────────

class _ContinueButton extends StatefulWidget {
  final bool enabled;
  final String? selectedType;
  final VoidCallback onTap;

  const _ContinueButton({
    required this.enabled,
    required this.selectedType,
    required this.onTap,
  });

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton> {
  bool _pressed = false;

  Color get _accent {
    if (widget.selectedType == 'WORKER') return _kBrandGold;
    if (widget.selectedType == 'INDIVIDUAL') return _kBrandDark;
    return Colors.black.withValues(alpha: 0.06);
  }

  Color get _labelColor {
    if (!widget.enabled) return appTextSecondaryColor.withValues(alpha: 0.5);
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
      child: GestureDetector(
        onTapDown: widget.enabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap();
              }
            : null,
        onTapCancel: widget.enabled
            ? () => setState(() => _pressed = false)
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: widget.enabled
                  ? _accent
                  : Colors.black.withValues(alpha: 0.05),
              boxShadow: widget.enabled
                  ? [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.38),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      color: _labelColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                    child: const Text('Continuer'),
                  ),
                  if (widget.enabled) ...[
                    8.width,
                    Icon(Icons.arrow_forward_rounded,
                        size: 18, color: _labelColor),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
