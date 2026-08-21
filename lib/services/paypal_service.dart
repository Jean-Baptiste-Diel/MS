import 'package:flutter/material.dart';
import 'package:flutter_paypal_checkout/flutter_paypal_checkout.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../main.dart';
import '../model/payment_gateway_response.dart';
import '../utils/common.dart';
import '../utils/configs.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class PayPalService {
  static Future paypalCheckOut({
    required BuildContext context,
    required PaymentSetting paymentSetting,
    required num totalAmount,
    required Function(Map<String, dynamic>) onComplete,
  }) async {
    appStore.setLoading(true);
    String payPalClientId = '';
    String secretKey = '';
    if (paymentSetting.isTest.getBoolInt()) {
      payPalClientId = paymentSetting.testValue!.payPalClientId.validate();
      secretKey = paymentSetting.testValue!.payPalSecretKey.validate();
    } else {
      payPalClientId = paymentSetting.liveValue!.payPalClientId.validate();
      secretKey = paymentSetting.liveValue!.payPalSecretKey.validate();
    }
    if (payPalClientId.isEmpty || secretKey.isEmpty) throw language.accessDeniedContactYourAdmin;

    PaypalCheckout(
      sandboxMode: paymentSetting.isTest.getBoolInt(),
      clientId: payPalClientId,
      secretKey: secretKey,
      returnURL: "junedr375.github.io/junedr375-payment/",
      cancelURL: "junedr375.github.io/junedr375-payment/error.html",
      transactions: [
        {
          "amount": {
            "total": totalAmount,
            "currency": await isIqonicProduct ? PAYPAL_CURRENCY_CODE : '${appConfigurationStore.currencyCode}',
            "details": {"subtotal": totalAmount, "shipping": '0', "shipping_discount": 0}
          },
          "description": 'Name: ${appStore.userFullName} - Email: ${appStore.userEmail}',
        }
      ],
      note: " - ",
      onSuccess: (Map params) async {
        log("onSuccess: $params");
        appStore.setLoading(false);
        if (params['message'] is String) {
          TopToast.show(message: params['message']);
        }
        onComplete.call({
          'transaction_id': params['data']['id'],
        });
      },
      onError: (error) {
        log("onError: $error");
        appStore.setLoading(false);
        TopToast.show(message: error.toString(), type: TopToastType.error);
        finish(context);
      },
      onCancel: (params) {
        log("cancelled: $params");
        TopToast.show(message: language.cancelled.validate());
        appStore.setLoading(false);
      },
    ).launch(context).whenComplete(() => appStore.setLoading(false));
  }
}
