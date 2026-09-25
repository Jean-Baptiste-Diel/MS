import 'package:booking_system_flutter/component/app_empty_state.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_notification_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/booking/mison_order_detail_screen.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

/// Historique des notifications Mison (GET /api/notifications).
class NotificationScreen extends StatefulWidget {
  @override
  _NotificationScreenState createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<MisonNotification> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  Future<void> _load() async {
    try {
      final res = await getMisonNotifications();
      setState(() {
        _items = res.data;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      log('getMisonNotifications error: $e');
      setState(() {
        _error = 'Impossible de charger les notifications.';
        _isLoading = false;
      });
    }
  }

  int get _unreadCount => _items.where((n) => !n.isRead).length;

  void _syncBadges() {
    appStore.setUnreadCount(_unreadCount);
    artisanNotifBadge.value = _unreadCount;
    setValue(ARTISAN_NOTIF_BADGE_KEY, _unreadCount);
  }

  Future<void> _markAllRead() async {
    if (_unreadCount == 0) return;
    final previous = _items;
    setState(() => _items = _items.map((n) => n.copyWith(isRead: true)).toList());
    _syncBadges();
    try {
      await markMisonNotificationsRead();
    } catch (e) {
      setState(() => _items = previous);
      _syncBadges();
      TopToast.show(message: 'Impossible de marquer les notifications comme lues.', type: TopToastType.error);
    }
  }

  Future<void> _open(MisonNotification n) async {
    if (!n.isRead) {
      setState(() => _items = _items.map((e) => e.id == n.id ? e.copyWith(isRead: true) : e).toList());
      _syncBadges();
      markMisonNotificationsRead(id: n.id).catchError((e) => log('mark read error: $e'));
    }
    // Ouvre la commande concernée
    if (n.orderId != null && n.orderId!.isNotEmpty) {
      await MisonOrderDetailScreen(orderId: n.orderId!).launch(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kMisonHeaderBg,
      appBar: MisonAppBar(
        title: 'Notifications',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kMisonDark),
          onPressed: () => Navigator.pop(context),
        ),
        titleTrailing: _unreadCount > 0
            ? TextButton(
                onPressed: _markAllRead,
                child: Text('Tout marquer lu', style: boldTextStyle(size: 13, color: kMisonGold)),
              )
            : null,
      ),
      body: DotGridBackground(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: LoaderWidget(colors: const [kMisonDark, kMisonGold]));
    }
    if (_error != null) {
      return AppEmptyState(
        type: AppEmptyStateType.error,
        title: _error,
        retryLabel: language.reload,
        onRetry: () {
          setState(() => _isLoading = true);
          _load();
        },
      );
    }
    return RefreshIndicator(
      color: kMisonGold,
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: context.height() * 0.12),
                const AppEmptyState(
                  type: AppEmptyStateType.empty,
                  title: 'Aucune notification',
                  subtitle: 'Vos notifications sur vos commandes et paiements apparaîtront ici.',
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _items.length,
              separatorBuilder: (_, __) => 10.height,
              itemBuilder: (_, i) => _NotificationTile(
                notification: _items[i],
                onTap: () => _open(_items[i]),
              ),
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final MisonNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  IconData get _icon {
    final t = notification.type;
    if (t.startsWith('PAYMENT') || t.contains('FEE')) return Icons.payments_outlined;
    if (t == 'ORDER_CANCELLED' || t == 'ORDER_ARTISAN_RELEASED') return Icons.event_busy_rounded;
    if (t == 'ORDER_COMPLETED' || t == 'ORDER_RATED') return Icons.check_circle_outline_rounded;
    if (t == 'ORDER_STARTED') return Icons.handyman_outlined;
    if (t.startsWith('ORDER')) return Icons.assignment_outlined;
    if (t == 'WELCOME') return Icons.waving_hand_outlined;
    return Icons.notifications_none_rounded;
  }

  /// « À l'instant », « il y a 5 min », « il y a 2 h », « Hier à 14:32 », « 12 sept. à 09:10 ».
  String get _when {
    final date = notification.createdAt;
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24 && DateTime.now().day == date.day) return 'il y a ${diff.inHours} h';
    final hour = DateFormat('HH:mm').format(date);
    if (diff.inDays < 2) return 'Hier à $hour';
    return '${DateFormat('d MMM', 'fr_FR').format(date)} à $hour';
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // Non lue : doré clair ; lue : carte blanche
          color: unread ? kMisonGold.withValues(alpha: 0.10) : context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: unread ? kMisonGold.withValues(alpha: 0.45) : Colors.transparent,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kMisonGold.withValues(alpha: unread ? 0.20 : 0.10),
              ),
              child: Icon(_icon, color: kMisonGold, size: 22),
            ),
            12.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: boldTextStyle(size: 15, color: kMisonDark),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unread) ...[
                        8.width,
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(color: kMisonGold, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                  if (notification.body.isNotEmpty) ...[
                    4.height,
                    Text(notification.body, style: secondaryTextStyle(size: 14), maxLines: 3, overflow: TextOverflow.ellipsis),
                  ],
                  6.height,
                  Text(_when, style: secondaryTextStyle(size: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
