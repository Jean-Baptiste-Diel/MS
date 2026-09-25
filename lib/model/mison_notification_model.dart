/// Notification de l'historique Mison (GET /api/notifications).
class MisonNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final String? orderId;
  final bool isRead;
  final DateTime? createdAt;

  const MisonNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.orderId,
    required this.isRead,
    required this.createdAt,
  });

  factory MisonNotification.fromJson(Map<String, dynamic> json) {
    return MisonNotification(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      orderId: json['order_id']?.toString(),
      isRead: json['is_read'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
    );
  }

  MisonNotification copyWith({bool? isRead}) => MisonNotification(
        id: id,
        title: title,
        body: body,
        type: type,
        orderId: orderId,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );
}

class MisonNotificationResponse {
  final int unreadCount;
  final List<MisonNotification> data;

  const MisonNotificationResponse({required this.unreadCount, required this.data});

  factory MisonNotificationResponse.fromJson(Map<String, dynamic> json) {
    return MisonNotificationResponse(
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '') ?? 0,
      data: (json['data'] as List? ?? [])
          .map((e) => MisonNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
