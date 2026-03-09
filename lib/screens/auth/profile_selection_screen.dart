import 'package:booking_system_flutter/screens/auth/artisan_sign_up_screen.dart';
import 'package:booking_system_flutter/screens/auth/sign_up_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:booking_system_flutter/main.dart';

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({Key? key}) : super(key: key);

  @override
  _ProfileSelectionScreenState createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  String? selectedType;

  Color _typeColor(String type) {
    switch (type) {
      case 'WORKER':
        return Color(0xFFE67E22);
      case 'INDIVIDUAL':
        return Color(0xFF2E86DE);
      case 'ENTERPRISE':
        return Color(0xFF16A085);
      default:
        return primaryColor;
    }
  }

  Widget _option(
      BuildContext context, String title, String assetIcon, String type) {
    final bool isSelected = selectedType == type;
    final Color accent = _typeColor(type);

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedType = type;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFFFF8E8) : context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? primaryColor : context.dividerColor,
              width: isSelected ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.06 : 1.0,
                  duration: Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isSelected
                            ? [
                                accent.withValues(alpha: 0.25),
                                accent.withValues(alpha: 0.08),
                              ]
                            : [
                                Colors.black12,
                                Colors.black12,
                              ],
                      ),
                      border: Border.all(
                        color: isSelected
                            ? accent.withValues(alpha: 0.8)
                            : context.dividerColor,
                        width: isSelected ? 1.3 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ]
                          : [],
                    ),
                    child: Image.asset(
                      assetIcon,
                      width: 20,
                      height: 20,
                      color: isSelected ? accent : context.iconColor,
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  right: isSelected ? -1 : -4,
                  top: isSelected ? -1 : -4,
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 220),
                    width: isSelected ? 10 : 6,
                    height: isSelected ? 10 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? accent
                          : context.iconColor.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ],
            ),
            16.width,
            Text(
              title,
              style: primaryTextStyle(
                color: isSelected ? Colors.black87 : null,
              ),
            ),
            Spacer(),
            Image.asset(ic_arrow_right,
                width: 16,
                height: 16,
                color: isSelected ? accent : context.iconColor),
          ],
        ),
      ),
    );
  }

  void _continue(BuildContext context) {
    if (selectedType == null) return;
    if (selectedType == 'WORKER') {
      ArtisanSignUpScreen().launch(context);
    } else if (selectedType == 'INDIVIDUAL') {
      SignUpScreen(initialAccountType: 'PARTICULIER').launch(context);
    } else if (selectedType == 'ENTERPRISE') {
      SignUpScreen(initialAccountType: 'ENTREPRISE').launch(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: transparentColor,
        leading: BackButton(color: context.iconColor),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    12.height,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        language.selectProfileTitle,
                        style: boldTextStyle(size: 28),
                      ),
                    ),
                    8.height,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        language.selectProfileSubtitle,
                        style: secondaryTextStyle(size: 12),
                      ),
                    ),
                    20.height,
                    _option(context, language.worker, ic_artisan, 'WORKER'),
                    12.height,
                    _option(context, language.individual, ic_profile2,
                        'INDIVIDUAL'),
                    12.height,
                    _option(context, language.enterprise, ic_category,
                        'ENTERPRISE'),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              child: AppButton(
                text: language.continueLabel,
                color: Colors.black,
                textColor: Colors.white,
                width: context.width(),
                height: 48,
                shapeBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                onTap: () => _continue(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
