import 'package:booking_system_flutter/component/back_widget.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/extensions/num_extenstions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

import '../../component/empty_error_state_widget.dart';
import 'package:booking_system_flutter/screens/booking/track_location.dart';

/// Écran de détail d'une commande Mison
/// Utilise getMisonOrderDetail() pour récupérer les données de l'API
class MisonOrderDetailScreen extends StatefulWidget {
  final String orderId;

  const MisonOrderDetailScreen({Key? key, required this.orderId}) : super(key: key);

  @override
  State<MisonOrderDetailScreen> createState() => _MisonOrderDetailScreenState();
}

class _MisonOrderDetailScreenState extends State<MisonOrderDetailScreen> {
  late Future<MisonOrderDetailResponse> future;
  bool isRating = false;
  bool isStarted = false;
  bool isPaying = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() {
    future = getMisonOrderDetail(widget.orderId);
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd MMM yyyy', 'fr_FR').format(date);
    } catch (e) {
      return isoDate;
    }
  }

  String _formatTime(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('HH:mm').format(date);
    } catch (e) {
      return '';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'PENDING':
        return pending;
      case 'ASSIGNED':
        return assigned_booking;
      case 'ACCEPTED':
        return accept;
      case 'IN_PROGRESS':
        return in_progress;
      case 'COMPLETED':
        return completed;
      case 'CANCELLED':
        return cancelled;
      case 'REJECTED':
        return rejected;
      default:
        return defaultStatus;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'PENDING':
        return 'En attente';
      case 'ASSIGNED':
        return 'Artisan assigné';
      case 'ACCEPTED':
        return 'Accepté';
      case 'IN_PROGRESS':
        return 'En cours';
      case 'COMPLETED':
        return 'Terminé';
      case 'CANCELLED':
        return 'Annulé';
      case 'REJECTED':
        return 'Refusé';
      default:
        return status ?? 'Inconnu';
    }
  }

  void _showRatingDialog(MisonOrder order) {
    int rating = 5;
    final reviewController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: radius(16)),
            title: Text('Noter cette prestation', style: boldTextStyle()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Star rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: ratingBarColor,
                        size: 32,
                      ),
                      onPressed: () {
                        setDialogState(() => rating = index + 1);
                      },
                    );
                  }),
                ),
                16.height,
                // Review text
                AppTextField(
                  controller: reviewController,
                  textFieldType: TextFieldType.MULTILINE,
                  minLines: 3,
                  maxLines: 5,
                  decoration: inputDecoration(context).copyWith(
                    hintText: 'Votre avis...',
                    fillColor: context.cardColor,
                    filled: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Annuler', style: primaryTextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  setState(() => isRating = true);
                  
                  try {
                    await rateMisonOrder(
                      order.id ?? '',
                      rating,
                      reviewController.text,
                    );
                    toast('Merci pour votre avis !');
                    init();
                    setState(() {});
                  } catch (e) {
                    toast('Erreur: ${e.toString()}');
                  } finally {
                    setState(() => isRating = false);
                  }
                },
                child: Text('Envoyer', style: boldTextStyle(color: primaryColor)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPaymentModal(MisonOrder order) {
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: radius(12)),
            title: Text('Facture', style: boldTextStyle()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Saisir le montant à payer', style: secondaryTextStyle()),
                12.height,
                AppTextField(
                  controller: amountController,
                  textFieldType: TextFieldType.PHONE,
                  decoration: inputDecoration(context).copyWith(
                    hintText: 'Montant',
                    filled: true,
                    fillColor: context.cardColor,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Annuler', style: primaryTextStyle(color: Colors.grey)),
              ),
              AppButton(
                text: 'Payer',
                color: const Color(0xFFC99700),
                textColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onTap: () async {
                  final val = amountController.text.trim();
                  if (val.isEmpty) {
                    toast('Veuillez saisir un montant');
                    return;
                  }
                  Navigator.pop(context);
                  toast('Paiement simulé: $val');
                },
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarWidget(
        'Détail de la commande',
        textColor: Colors.white,
        color: primaryColor,
        systemUiOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarColor: primaryColor,
        ),
        showBack: true,
        backWidget: BackWidget(),
      ),
      body: Stack(
        children: [
          SnapHelperWidget<MisonOrderDetailResponse>(
            future: future,
            loadingWidget: const Center(child: CircularProgressIndicator()),
            errorBuilder: (error) {
              return NoDataWidget(
                title: error,
                imageWidget: const ErrorStateWidget(),
                retryText: language.reload,
                onRetry: () {
                  init();
                  setState(() {});
                },
              );
            },
            onSuccess: (response) {
              final order = response.data;
              if (order == null) {
                return NoDataWidget(
                  title: 'Commande non trouvée',
                  imageWidget: const EmptyStateWidget(),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: boxDecorationDefault(
                        color: _getStatusColor(order.status).withOpacity(0.1),
                        borderRadius: radius(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getStatusIcon(order.status),
                            color: _getStatusColor(order.status),
                            size: 24,
                          ),
                          12.width,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getStatusLabel(order.status),
                                  style: boldTextStyle(
                                    color: _getStatusColor(order.status),
                                  ),
                                ),
                                if (order.status == 'PENDING')
                                  Text(
                                    'Votre demande est en cours de traitement',
                                    style: secondaryTextStyle(size: 12),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    24.height,
                    
                    // Service info
                    _SectionCard(
                      title: 'Service',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.service?.name ?? 'Service',
                            style: boldTextStyle(size: 18),
                          ),
                          if (order.service?.minPrice != null) ...[
                            8.height,
                            Text(
                              'Prix minimum: ${order.service!.minPrice}F',
                              style: secondaryTextStyle(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    16.height,
                    
                    // Date & Time
                    _SectionCard(
                      title: 'Date et heure',
                      child: Row(
                        children: [
                          Expanded(
                            child: _InfoItem(
                              icon: Icons.calendar_today,
                              label: 'Date',
                              value: _formatDate(order.serviceDate),
                            ),
                          ),
                          Expanded(
                            child: _InfoItem(
                              icon: Icons.access_time,
                              label: 'Heure',
                              value: _formatTime(order.serviceDate),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    16.height,
                    
                    // Address
                    _SectionCard(
                      title: 'Adresse',
                      child: _InfoItem(
                        icon: Icons.location_on,
                        label: 'Zone d\'intervention',
                        value: order.serviceAddress ?? '',
                      ),
                    ),
                    
                    16.height,
                    
                    // Description
                    if (order.description != null && order.description!.isNotEmpty)
                      _SectionCard(
                        title: 'Description',
                        child: Text(
                          order.description!,
                          style: primaryTextStyle(),
                        ),
                      ),
                    
                    16.height,
                 /*    // Price Detail (simple breakdown)
                    _SectionCard(
                      title: 'Price Detail',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Prix', style: secondaryTextStyle()),
                              Text(
                                (order.service?.minPriceValue ?? 0).toPriceFormat(),
                                style: primaryTextStyle(),
                              ),
                            ],
                          ),
                          8.height,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Sous-total', style: secondaryTextStyle()),
                              Text(
                                (order.service?.minPriceValue ?? 0).toPriceFormat(),
                                style: primaryTextStyle(),
                              ),
                            ],
                          ),
                          8.height,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Taxe', style: secondaryTextStyle()),
                              Text(
                                // simple 18% tax for display
                                ((order.service?.minPriceValue ?? 0) * 0.18).toPriceFormat(),
                                style: primaryTextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                          12.height,
                          Divider(),
                          12.height,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total', style: boldTextStyle()),
                              Text(
                                ((order.service?.minPriceValue ?? 0) * 1.18).toPriceFormat(),
                                style: boldTextStyle(color: primaryColor),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    16.height, */
                    // Cancel Booking button
                    AppButton(
                      width: double.infinity,
                      text: 'Annuler la commande',
                      color: Colors.red,
                      textColor: Colors.white,
                      shapeBorder: RoundedRectangleBorder(borderRadius: radius(12)),
                      onTap: () {
                        showConfirmDialogCustom(
                          context,
                          title: 'Annuler la commande',
                          subTitle: 'Êtes-vous sûr de vouloir annuler cette commande ?',
                          positiveText: 'Oui, annuler',
                          negativeText: 'Non',
                          dialogType: DialogType.DELETE,
                          onAccept: (_) async {
                            appStore.setLoading(true);
                            // TODO: Call API to cancel order
                            // await cancelMisonOrder(order.id ?? '');
                            toast('Commande annulée');
                            appStore.setLoading(false);
                            init();
                            setState(() {});
                          },
                        );
                      },
                    ),
                    
                    16.height,
                    
                    // Artisan info (if assigned)
                    if (order.artisan != null)
                      _SectionCard(
                        title: 'Artisan assigné',
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: primaryColor.withOpacity(0.1),
                              backgroundImage: order.artisan!.profilePictureUrl != null
                                  ? NetworkImage(order.artisan!.profilePictureUrl!)
                                  : null,
                              child: order.artisan!.profilePictureUrl == null
                                  ? Icon(Icons.person, color: primaryColor, size: 30)
                                  : null,
                            ),
                            16.width,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.artisan!.fullName,
                                    style: boldTextStyle(size: 16),
                                  ),
                                  4.height,
                                  if (order.artisan!.experienceYears != null)
                                    Text(
                                      '${order.artisan!.experienceYears} ans d\'expérience',
                                      style: secondaryTextStyle(),
                                    ),
                                  4.height,
                                  if (order.artisan!.averageRating != null)
                                    Row(
                                      children: [
                                        Icon(Icons.star, size: 16, color: ratingBarColor),
                                        4.width,
                                        Text(
                                          '${order.artisan!.averageRating} (${order.artisan!.totalReviews ?? 0} avis)',
                                          style: secondaryTextStyle(),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Client rating (if already rated)
                    if (order.clientRating != null) ...[
                      16.height,
                      _SectionCard(
                        title: 'Votre évaluation',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: List.generate(5, (index) {
                                return Icon(
                                  index < order.clientRating! ? Icons.star : Icons.star_border,
                                  color: ratingBarColor,
                                  size: 24,
                                );
                              }),
                            ),
                            if (order.clientReview != null && order.clientReview!.isNotEmpty) ...[
                              8.height,
                              Text(
                                order.clientReview!,
                                style: secondaryTextStyle(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    
                    32.height,

                    // Map preview + tracking controls (when artisan assigned or in progress)
                    if (order.artisan != null && (order.isAssigned || order.isInProgress)) ...[
                      _SectionCard(
                        title: 'Handyman location',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 180,
                              child: Container(
                                decoration: boxDecorationDefault(
                                  color: context.cardColor,
                                  borderRadius: radius(8),
                                ),
                                child: Center(
                                  child: Text('Carte de prévisualisation', style: secondaryTextStyle()),
                                ),
                              ),
                            ),
                            12.height,
                            Row(
                              children: [
                                AppButton(
                                  onTap: () {
                                    // attempt to parse order id to int
                                    final idInt = int.tryParse(order.id ?? '');
                                    if (idInt == null) {
                                      toast('Impossible de tracker: id invalide');
                                      return;
                                    }
                                    TrackLocation(bookingId: idInt, isHandyman: true).launch(context);
                                  },
                                  padding: const EdgeInsets.only(top: 0, left: 8, right: 8),
                                  height: 42,
                                  color: const Color(0xFF39A81D),
                                  textColor: white,
                                  text: 'Track',
                                ).expand(),
                                16.width,
                                Container(
                                  width: 42,
                                  height: 42,
                                  padding: const EdgeInsets.all(12),
                                  decoration: boxDecorationDefault(
                                    color: Colors.white,
                                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                                  ),
                                  child: Icon(Icons.refresh, color: textSecondaryColor),
                                ).onTap(() {
                                  toast('Actualisation...');
                                }),
                                16.width,
                                Container(
                                  width: 42,
                                  height: 42,
                                  padding: const EdgeInsets.all(12),
                                  decoration: boxDecorationDefault(
                                    color: Colors.white,
                                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                                  ),
                                  child: Icon(Icons.share, color: textSecondaryColor),
                                ).onTap(() {
                                  toast('Partager...');
                                }),
                              ],
                            ),
                            12.height,
                            Text('Handyman Reached? Click To Start', style: secondaryTextStyle()),
                            8.height,
                            AppButton(
                              width: double.infinity,
                              text: isStarted || order.isInProgress ? 'En cours' : 'Start',
                              color: isStarted || order.isInProgress ? Colors.green : primaryColor,
                              textColor: Colors.white,
                              shapeBorder: RoundedRectangleBorder(borderRadius: radius(8)),
                              onTap: () {
                                if (order.isInProgress) {
                                  toast('Le travail est déjà en cours');
                                  return;
                                }
                                setState(() {
                                  isStarted = true;
                                });
                                toast('Travail commencé');
                              },
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Pay button (shown when started or completed)
                    if (isStarted || order.isCompleted) ...[
                      16.height,
                      AppButton(
                        width: double.infinity,
                        text: 'Payer',
                        color: primaryColor,
                        textColor: Colors.white,
                        shapeBorder: RoundedRectangleBorder(borderRadius: radius(12)),
                        onTap: () => _showPaymentModal(order),
                      ),
                    ],
                    
                    // Rate button (if completed and not rated)
                    if (order.canRate)
                      AppButton(
                        width: double.infinity,
                        text: 'Noter cette prestation',
                        color: primaryColor,
                        textColor: Colors.white,
                        shapeBorder: RoundedRectangleBorder(borderRadius: radius(12)),
                        onTap: () => _showRatingDialog(order),
                      ),
                  ],
                ),
              );
            },
          ),
          
          if (isRating)
            Container(
              color: Colors.black26,
              child: Center(child: LoaderWidget()),
            ),
            
          Observer(
            builder: (context) => LoaderWidget().visible(appStore.isLoading.validate()),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'PENDING':
        return Icons.hourglass_empty;
      case 'ASSIGNED':
        return Icons.person_add;
      case 'ACCEPTED':
        return Icons.check_circle;
      case 'IN_PROGRESS':
        return Icons.construction;
      case 'COMPLETED':
        return Icons.verified;
      case 'CANCELLED':
        return Icons.cancel;
      case 'REJECTED':
        return Icons.block;
      default:
        return Icons.info;
    }
  }
}

/// Section card widget
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: boxDecorationDefault(
        color: context.cardColor,
        borderRadius: radius(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: boldTextStyle(size: 14, color: Colors.grey)),
          12.height,
          child,
        ],
      ),
    );
  }
}

/// Info item widget
class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: primaryColor),
        12.width,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: secondaryTextStyle(size: 12)),
            Text(value, style: primaryTextStyle()),
          ],
        ),
      ],
    );
  }
}
