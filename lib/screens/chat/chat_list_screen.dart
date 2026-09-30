import 'package:booking_system_flutter/utils/image_cache_key.dart';
import 'package:booking_system_flutter/component/app_empty_state.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/model/mison_order_model.dart';
import 'package:booking_system_flutter/network/rest_apis.dart';
import 'package:booking_system_flutter/screens/chat/mison_order_chat_screen.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Discussions de l'utilisateur : une par commande ayant un ouvrier rattaché.
/// Ouvre le chat temps réel (WebSocket) de la commande.
class ChatListScreen extends StatefulWidget {
  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late Future<MisonOrderResponse> _future;

  bool get _isProvider => appStore.userType == USER_TYPE_PROVIDER;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = getMisonOrders();

  /// Nom de l'interlocuteur : l'ouvrier pour un client, le client pour un ouvrier.
  String _peerName(MisonOrder o) {
    final name = _isProvider ? o.client?.fullName : o.artisan?.fullName;
    if (name != null && name.isNotEmpty) return name;
    return _isProvider ? 'Client' : 'Ouvrier';
  }

  Future<void> _openChat(MisonOrder o) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MisonOrderChatScreen(orderId: o.id!, peerName: _peerName(o)),
      ),
    );
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const MisonAppBar(title: 'Discussions'),
      body: FutureBuilder<MisonOrderResponse>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: LoaderWidget(colors: const [kMisonDark, kMisonGold]));
          }
          if (snap.hasError) {
            return AppEmptyState(
              type: AppEmptyStateType.error,
              title: snap.error.toString(),
              retryLabel: language.reload,
              onRetry: () => setState(_load),
            );
          }

          // Commandes où un ouvrier est rattaché : le chat est ouvert
          final chats = (snap.data?.data ?? [])
              .where((o) => o.id != null && o.canChat)
              .toList();

          return RefreshIndicator(
            color: kMisonGold,
            onRefresh: () async {
              setState(_load);
              await _future;
            },
            child: chats.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: context.height() * 0.1),
                      AppEmptyState(
                        type: AppEmptyStateType.empty,
                        title: 'Aucune discussion',
                        subtitle: _isProvider
                            ? 'Vos échanges avec les clients apparaîtront ici dès que vous acceptez une commande.'
                            : 'Vos échanges avec les ouvriers apparaîtront ici dès qu\'un ouvrier accepte votre commande.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: chats.length,
                    separatorBuilder: (_, __) => 10.height,
                    itemBuilder: (_, i) => _ChatTile(
                      order: chats[i],
                      peerName: _peerName(chats[i]),
                      peerPhoto: _isProvider ? null : chats[i].artisan?.profilePictureUrl,
                      onTap: () => _openChat(chats[i]),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final MisonOrder order;
  final String peerName;
  final String? peerPhoto;
  final VoidCallback onTap;

  const _ChatTile({
    required this.order,
    required this.peerName,
    required this.peerPhoto,
    required this.onTap,
  });

  String get _statusLabel {
    switch (order.status?.trim().toUpperCase()) {
      case 'ASSIGNED':                     return 'Ouvrier proposé';
      case 'ACCEPTED':                     return 'Ouvrier trouvé';
      case 'AWAITING_TRAVEL_PAYMENT':      return 'Paiement du déplacement';
      case 'IN_PROGRESS':                  return 'Intervention en cours';
      case 'AWAITING_REALIZATION_PAYMENT': return 'Paiement de la prestation';
      default:                             return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = peerName.isNotEmpty ? peerName[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar : photo de l'ouvrier, sinon initiale sur fond doré
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kMisonGold.withValues(alpha: 0.15),
              ),
              clipBehavior: Clip.antiAlias,
              child: (peerPhoto != null && peerPhoto!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: peerPhoto!,
                      cacheKey: imageCacheKey(peerPhoto!),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _initial(initial),
                    )
                  : _initial(initial),
            ),
            14.width,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(peerName,
                      style: boldTextStyle(size: 16, color: kMisonDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  3.height,
                  Text(order.service?.name ?? 'Commande',
                      style: secondaryTextStyle(size: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (_statusLabel.isNotEmpty) ...[
                    3.height,
                    Text(_statusLabel,
                        style: boldTextStyle(size: 12, color: kMisonGold)),
                  ],
                ],
              ),
            ),
            8.width,
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: kMisonGold,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initial(String initial) => Center(
        child: Text(initial, style: boldTextStyle(size: 20, color: kMisonGold)),
      );
}
