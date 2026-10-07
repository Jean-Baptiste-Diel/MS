import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/booking_detail_model.dart';
import 'package:booking_system_flutter/screens/booking/component/price_common_widget.dart';
import 'package:booking_system_flutter/screens/wallet/user_wallet_balance_screen.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/extensions/num_extenstions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../component/app_common_dialog.dart';
import '../../component/base_scaffold_widget.dart';
import '../../component/empty_error_state_widget.dart';
import '../../component/wallet_balance_component.dart';
import '../../model/payment_gateway_response.dart';
import '../../network/rest_apis.dart';
import '../../utils/configs.dart';
import '../../utils/model_keys.dart';
import '../dashboard/dashboard_screen.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';

class PaymentScreen extends StatefulWidget {
  final BookingDetailResponse bookings;
  final bool isForAdvancePayment;

  PaymentScreen({required this.bookings, this.isForAdvancePayment = false});

  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Future<List<PaymentSetting>>? future;

  PaymentSetting? currentPaymentMethod;

  num totalAmount = 0;
  num? advancePaymentAmount;

  @override
  void initState() {
    super.initState();
    init();

    if (widget.bookings.service!.isAdvancePayment && widget.bookings.service!.isFixedService && !widget.bookings.service!.isFreeService && widget.bookings.bookingDetail!.bookingPackage == null) {
      if (widget.bookings.bookingDetail!.paidAmount.validate() == 0) {
        advancePaymentAmount = widget.bookings.bookingDetail!.totalAmount.validate() * widget.bookings.service!.advancePaymentPercentage.validate() / 100;
        totalAmount = widget.bookings.bookingDetail!.totalAmount.validate() * widget.bookings.service!.advancePaymentPercentage.validate() / 100;
      } else {
        totalAmount = widget.bookings.bookingDetail!.totalAmount.validate() - widget.bookings.bookingDetail!.paidAmount.validate();
      }
    } else {
      totalAmount = widget.bookings.bookingDetail!.totalAmount.validate();
    }

    log(totalAmount);
  }

  void init() async {
    log("ISaDVANCE${widget.isForAdvancePayment}");
    future = getPaymentGateways(requireCOD: !widget.isForAdvancePayment);
    setState(() {});
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  Future<void> _handleClick() async {
    appStore.setLoading(true);
    if (currentPaymentMethod!.type == PAYMENT_METHOD_COD) {
      savePay(paymentMethod: PAYMENT_METHOD_COD, paymentStatus: SERVICE_PAYMENT_STATUS_PENDING);
    } else if (currentPaymentMethod!.type == PAYMENT_METHOD_FROM_WALLET) {
      savePay(
        paymentMethod: PAYMENT_METHOD_FROM_WALLET,
        paymentStatus: widget.isForAdvancePayment ? SERVICE_PAYMENT_STATUS_ADVANCE_PAID : SERVICE_PAYMENT_STATUS_PAID,
        txnId: '',
      );
    } else {
      // Moyens de paiement du modèle d'origine retirés (Mison : paiement Wave).
      appStore.setLoading(false);
      TopToast.show(message: 'Moyen de paiement non disponible.', type: TopToastType.error);
    }
  }

  Future<void> savePay({String txnId = '', String paymentMethod = '', String paymentStatus = ''}) async {
    Map request = {
      CommonKeys.bookingId: widget.bookings.bookingDetail!.id.validate(),
      CommonKeys.customerId: appStore.userId,
      CouponKeys.discount: widget.bookings.service!.discount,
      BookingServiceKeys.totalAmount: totalAmount,
      CommonKeys.dateTime: DateFormat(BOOKING_SAVE_FORMAT).format(DateTime.now()),
      CommonKeys.txnId: txnId != '' ? txnId : "#${widget.bookings.bookingDetail!.id.validate()}",
      CommonKeys.paymentStatus: paymentStatus,
      CommonKeys.paymentMethod: paymentMethod,
    };

    if (widget.bookings.service != null &&
        widget.bookings.service!.isAdvancePayment &&
        widget.bookings.service!.isFixedService &&
        !widget.bookings.service!.isFreeService &&
        widget.bookings.bookingDetail!.bookingPackage == null) {
      request[AdvancePaymentKey.advancePaymentAmount] = advancePaymentAmount ?? widget.bookings.bookingDetail!.paidAmount;

      if ((widget.bookings.bookingDetail!.paymentStatus == null ||
              widget.bookings.bookingDetail!.paymentStatus != SERVICE_PAYMENT_STATUS_ADVANCE_PAID ||
              widget.bookings.bookingDetail!.paymentStatus != SERVICE_PAYMENT_STATUS_PAID) &&
          (widget.bookings.bookingDetail!.paidAmount == null || widget.bookings.bookingDetail!.paidAmount.validate() <= 0)) {
        // TODO: check this condition  widget.bookings.bookingPackage?.id == -1
        request[CommonKeys.paymentStatus] = SERVICE_PAYMENT_STATUS_ADVANCE_PAID;
      } else if (widget.bookings.bookingDetail!.paymentStatus == SERVICE_PAYMENT_STATUS_ADVANCE_PAID) {
        request[CommonKeys.paymentStatus] = SERVICE_PAYMENT_STATUS_PAID;
      }
    }

    appStore.setLoading(true);
    await savePayment(request).then((value) {
      appStore.setLoading(false);
      push(DashboardScreen(redirectToBooking: true), isNewTask: true, pageRouteAnimation: PageRouteAnimation.Fade);
    }).catchError((e) {
      TopToast.show(message: e.toString(), type: TopToastType.error);
      appStore.setLoading(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
        builder: (context) => AppScaffold(
            appBarTitle: language.payment,
            child: Stack(
              children: [
                AnimatedScrollView(
                  listAnimationType: ListAnimationType.FadeIn,
                  fadeInConfiguration: FadeInConfiguration(duration: 2.seconds),
                  physics: const AlwaysScrollableScrollPhysics(),
                  onSwipeRefresh: () async {
                    if (!appStore.isLoading) init();
                    return await 1.seconds.delay;
                  },
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PriceCommonWidget(
                              bookingDetail: widget.bookings.bookingDetail!,
                              serviceDetail: widget.bookings.service!,
                              taxes: widget.bookings.bookingDetail!.taxes.validate(),
                              couponData: widget.bookings.couponData,
                              bookingPackage: widget.bookings.bookingDetail!.bookingPackage != null ? widget.bookings.bookingDetail!.bookingPackage : null,
                            ),
                            32.height,
                            Text(language.lblChoosePaymentMethod, style: boldTextStyle(size: LABEL_TEXT_SIZE)),
                          ],
                        ).paddingAll(16),
                        SnapHelperWidget<List<PaymentSetting>>(
                          future: future,
                          onSuccess: (list) {
                            return AnimatedListView(
                              itemCount: list.length,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              listAnimationType: ListAnimationType.FadeIn,
                              fadeInConfiguration: FadeInConfiguration(duration: 2.seconds),
                              emptyWidget: NoDataWidget(
                                title: language.noPaymentMethodFound,
                                imageWidget: const EmptyStateWidget(),
                              ),
                              itemBuilder: (context, index) {
                                PaymentSetting value = list[index];

                                if (value.status.validate() == 0) return const Offstage();

                                return RadioGroup(
                                  groupValue: currentPaymentMethod,
                                  onChanged: (PaymentSetting? ind) {
                                    currentPaymentMethod = ind;
                                    setState(() {});
                                  },
                                  child: RadioListTile<PaymentSetting>(
                                    dense: true,
                                    activeColor: primaryColor,
                                    value: value,
                                    controlAffinity: ListTileControlAffinity.trailing,
                                    title: Text(value.title.validate(), style: primaryTextStyle()),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        if (appConfigurationStore.isEnableUserWallet) const WalletBalanceComponent().paddingSymmetric(vertical: 8, horizontal: 16),
                        if (!appStore.isLoading)
                          AppButton(
                            onTap: () async {
                              if (currentPaymentMethod == null) {
                                return TopToast.show(message: language.chooseAnyOnePayment.validate());
                              }

                              if (currentPaymentMethod!.type == PAYMENT_METHOD_COD || currentPaymentMethod!.type == PAYMENT_METHOD_FROM_WALLET) {
                                if (currentPaymentMethod!.type == PAYMENT_METHOD_FROM_WALLET) {
                                  appStore.setLoading(true);
                                  num walletBalance = await getUserWalletBalance();

                                  appStore.setLoading(false);
                                  if (walletBalance >= totalAmount) {
                                    showConfirmDialogCustom(
                                      context,
                                      dialogType: DialogType.CONFIRMATION,
                                      title: "${language.lblPayWith} ${currentPaymentMethod!.title.validate()}?",
                                      primaryColor: primaryColor,
                                      positiveText: language.lblYes,
                                      negativeText: language.lblCancel,
                                      onAccept: (p0) {
                                        _handleClick();
                                      },
                                    );
                                  } else {
                                    TopToast.show(message: language.insufficientBalanceMessage.validate());

                                    if (appConfigurationStore.onlinePaymentStatus) {
                                      showConfirmDialogCustom(
                                        context,
                                        dialogType: DialogType.CONFIRMATION,
                                        title: language.doYouWantToTopUpYourWallet,
                                        positiveText: language.lblYes,
                                        negativeText: language.lblNo,
                                        cancelable: false,
                                        primaryColor: context.primaryColor,
                                        onAccept: (p0) {
                                          pop();
                                          push(UserWalletBalanceScreen());
                                        },
                                        onCancel: (p0) {
                                          pop();
                                        },
                                      );
                                    }
                                  }
                                } else {
                                  showConfirmDialogCustom(
                                    context,
                                    dialogType: DialogType.CONFIRMATION,
                                    title: "${language.lblPayWith} ${currentPaymentMethod!.title.validate()}?",
                                    primaryColor: primaryColor,
                                    positiveText: language.lblYes,
                                    negativeText: language.lblCancel,
                                    onAccept: (p0) async {
                                      Navigator.of(context).pop();
                                      await 100.milliseconds.delay;
                                      _handleClick();
                                    },
                                  );
                                }
                              } else {
                                _handleClick().catchError((e) {
                                  appStore.setLoading(false);
                                  TopToast.show(message: e.toString(), type: TopToastType.error);
                                });
                              }
                            },
                            text: "${language.lblPayNow} ${totalAmount.toPriceFormat()}",
                            color: context.primaryColor,
                            width: context.width(),
                          ).paddingAll(16),
                      ],
                    ),
                  ],
                ),
                if (appStore.isLoading) LoaderWidget(),
              ],
            ),),);
  }
}