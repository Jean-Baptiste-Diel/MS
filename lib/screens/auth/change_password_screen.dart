import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/base_scaffold_widget.dart';
import 'package:booking_system_flutter/component/mison_account_sheets.dart';
import 'package:booking_system_flutter/component/mison_discreet_cancel_button.dart';
import 'package:booking_system_flutter/screens/auth/sign_in_screen.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/images.dart';
import 'package:booking_system_flutter/utils/model_keys.dart';
import 'package:booking_system_flutter/utils/pin_utils.dart';
import 'package:booking_system_flutter/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class ChangePasswordScreen extends StatefulWidget {
  @override
  ChangePasswordScreenState createState() => ChangePasswordScreenState();
}

class ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  TextEditingController oldPasswordCont = TextEditingController();
  TextEditingController newPasswordCont = TextEditingController();
  TextEditingController reenterPasswordCont = TextEditingController();

  FocusNode oldPasswordFocus = FocusNode();
  FocusNode newPasswordFocus = FocusNode();
  FocusNode reenterPasswordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    //
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  Future<void> changePassword() async {
    if (formKey.currentState!.validate()) {
      if (oldPasswordCont.text.trim() != getStringAsync(USER_PASSWORD)) {
        return TopToast.show(message: language.provideValidCurrentPasswordMessage.validate());
      }

      formKey.currentState!.save();
      hideKeyboard(context);

      var request = {
        UserKeys.oldPassword: oldPasswordCont.text,
        UserKeys.newPassword: newPasswordCont.text,
      };
      appStore.setLoading(true);

      try {
        final res = await changeUserPassword(request);
        await setValue(USER_PASSWORD, newPasswordCont.text);
        appStore.setLoading(false);
        TopToast.show(message: res.message.validate());
        finish(context);
      } catch (e) {
        appStore.setLoading(false);
        TopToast.show(message: e.toString(), type: TopToastType.error);
      }
    }
  }

  void _deleteAccount() {
    ifNotTester(() async {
      final message = await showMisonDeleteAccountSheet(context);
      if (message == null) return; // annulé

      appStore.setLoading(true);
      try {
        await userService.removeDocument(appStore.uid);
        await userService.deleteUser();
      } catch (_) {}
      await clearPreferences();
      appStore.setLoading(false);

      TopToast.show(message: message, type: TopToastType.success);
      // Page de connexion, comme après une déconnexion.
      push(
        SignInScreen(),
        isNewTask: true,
        pageRouteAnimation: PageRouteAnimation.Fade,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBarTitle: language.changePassword,
      useMisonHeader: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Text(
                  language.lblChangePwdTitle,
                  textAlign: TextAlign.center,
                  style: boldTextStyle(color: appTextPrimaryColor),
                ),
              ),
              24.height,
              AppTextField(
                textFieldType: TextFieldType.PASSWORD,
                controller: oldPasswordCont,
                focus: oldPasswordFocus,
                nextFocus: newPasswordFocus,
                obscureText: true,
                // Code PIN : clavier numérique, chiffres uniquement
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                suffixPasswordVisibleWidget: ic_show.iconImage(size: 10).paddingAll(14),
                suffixPasswordInvisibleWidget: ic_hide.iconImage(size: 10).paddingAll(14),
                decoration: inputDecoration(
                  context,
                  labelText: 'Ancien code PIN',
                ),
                isValidationRequired: true,
                // Pas de limite à 4 chiffres : un ancien code peut être plus long
                validator: (val) {
                  if (val == null || val.isEmpty) {
                    return language.requiredText;
                  }
                  return null;
                },
              ),
              16.height,
              AppTextField(
                textFieldType: TextFieldType.PASSWORD,
                controller: newPasswordCont,
                focus: newPasswordFocus,
                obscureText: true,
                nextFocus: reenterPasswordFocus,
                keyboardType: pinKeyboardType,
                inputFormatters: pinInputFormatters,
                suffixPasswordVisibleWidget: ic_show.iconImage(size: 10).paddingAll(14),
                suffixPasswordInvisibleWidget: ic_hide.iconImage(size: 10).paddingAll(14),
                decoration: inputDecoration(context, labelText: 'Nouveau code PIN (4 chiffres)'),
                isValidationRequired: true,
                validator: validatePin,
              ),
              16.height,
              AppTextField(
                textFieldType: TextFieldType.PASSWORD,
                controller: reenterPasswordCont,
                obscureText: true,
                focus: reenterPasswordFocus,
                keyboardType: pinKeyboardType,
                inputFormatters: pinInputFormatters,
                suffixPasswordVisibleWidget: ic_show.iconImage(size: 10).paddingAll(14),
                suffixPasswordInvisibleWidget: ic_hide.iconImage(size: 10).paddingAll(14),
                validator: (v) =>
                    validatePinConfirmation(v, newPasswordCont.text),
                onFieldSubmitted: (s) {
                  ifNotTester(() {
                    changePassword();
                  });
                },
                decoration: inputDecoration(context, labelText: 'Confirmer le code PIN'),
              ),
              24.height,
              AppButton(
                text: language.confirm,
                color: kMisonGold,
                textColor: Colors.white,
                width: context.width() - context.navigationBarHeight,
                onTap: () {
                  ifNotTester(() {
                    changePassword();
                  });
                },
              ),
              24.height,
              // Déconnexion, en gris, avant la suppression du compte
              AppButton(
                text: language.logout,
                color: Colors.grey.shade200,
                textColor: Colors.grey.shade800,
                elevation: 0,
                width: context.width() - context.navigationBarHeight,
                onTap: () => logout(context),
              ),
              16.height,
              // Suppression du compte : dans « Sécurité », sous la modification du PIN
              MisonDiscreetCancelButton(
                label: language.lblDeleteAccount,
                onTap: _deleteAccount,
                expanded: true,
              ),
              24.height,
            ],
          ),
        ),
      ),
    );
  }
}
