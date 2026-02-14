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

  Widget _option(
      BuildContext context, String title, String assetIcon, String type) {
    final bool isSelected = selectedType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedType = type;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFFDEEC4) : context.cardColor,
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
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: isSelected
                      ? primaryColor.withOpacity(0.1)
                      : Colors.black12,
                  shape: BoxShape.circle),
              child: Image.asset(assetIcon,
                  width: 20,
                  height: 20,
                  color: isSelected ? primaryColor : null),
            ),
            16.width,
            Text(title, style: primaryTextStyle()),
            Spacer(),
            Image.asset(ic_arrow_right,
                width: 16, height: 16, color: context.iconColor),
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
        title: Text(language.selectProfileTitle,
            style: boldTextStyle()),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    16.height,
                    _option(context, language.worker, ic_artisan,
                        'WORKER'),
                    12.height,
                    _option(context, language.individual, ic_profile2,
                        'INDIVIDUAL'),
                    12.height,
                    _option(context, language.enterprise, ic_category,
                        'ENTERPRISE'),
                    20.height,
                    Text(
                      language.selectProfileSubtitle, 
                      style: secondaryTextStyle(size: 12),
                      textAlign: TextAlign.center,
                    ).paddingOnly(top: 12),
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
