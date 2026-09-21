import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/utils/configs.dart';
import 'package:http/http.dart' as http;
import 'package:nb_utils/nb_utils.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final String _WS_BASE = '${DOMAIN_URL.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://')}/ws/chat';
const String _CONVERSATIONS_ENDPOINT = '${BASE_URL}chat/conversations';

enum MessageStatus { sent, pending, failed }
enum MessageType { text, image }

class SupportChatMessage {
  final String id;
  final String localId;
  final String content;       // texte ou object_name pour les images
  final String? imageUrl;     // URL pré-signée pour afficher l'image
  final Uint8List? localBytes; // bytes locaux pour preview avant upload
  final String senderName;
  final bool isMe;
  final DateTime createdAt;
  final MessageType messageType;
  MessageStatus status;

  SupportChatMessage({
    required this.id,
    required this.localId,
    required this.content,
    this.imageUrl,
    this.localBytes,
    required this.senderName,
    required this.isMe,
    required this.createdAt,
    this.messageType = MessageType.text,
    this.status = MessageStatus.sent,
  });

  bool get isImage => messageType == MessageType.image;

  factory SupportChatMessage.fromJson(Map<String, dynamic> json) {
    final senderId = (json['sender_id'] ?? json['sender'])?.toString() ?? '';
    final rawType = json['message_type']?.toString() ?? 'text';
    return SupportChatMessage(
      id: json['id']?.toString() ?? '',
      localId: '',
      content: json['content']?.toString() ?? '',
      imageUrl: json['image_url']?.toString(),
      senderName: json['sender_name']?.toString() ?? '',
      isMe: senderId == appStore.uid,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      messageType: rawType == 'image' ? MessageType.image : MessageType.text,
      status: MessageStatus.sent,
    );
  }

  factory SupportChatMessage.optimistic(String content) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    return SupportChatMessage(
      id: '',
      localId: id,
      content: content,
      senderName: '',
      isMe: true,
      createdAt: DateTime.now(),
      status: MessageStatus.pending,
    );
  }

  factory SupportChatMessage.optimisticImage(String localPath, Uint8List bytes) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    return SupportChatMessage(
      id: '',
      localId: id,
      content: localPath,
      localBytes: bytes,
      senderName: '',
      isMe: true,
      createdAt: DateTime.now(),
      messageType: MessageType.image,
      status: MessageStatus.pending,
    );
  }
}

class SupportChatService {
  WebSocketChannel? _channel;
  String? _conversationId;
  bool _isReady = false;
  bool _disposed = false;

  /// Émet l'historique initial (liste de messages)
  final _historyController = StreamController<List<SupportChatMessage>>.broadcast();

  /// Émet les nouveaux messages en temps réel
  final _newMessageController = StreamController<SupportChatMessage>.broadcast();

  /// Émet l'état de connexion (true = connecté, false = déconnecté)
  final _connectionController = StreamController<bool>.broadcast();

  Stream<List<SupportChatMessage>> get historyStream => _historyController.stream;
  Stream<SupportChatMessage> get newMessageStream => _newMessageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isReady => _isReady;
  String? get conversationId => _conversationId;

  /// Crée ou récupère la conversation de support
  Future<String> createOrGetConversation() async {
    log('SupportChat: POST $_CONVERSATIONS_ENDPOINT');
    log('SupportChat: token = ${appStore.token.isEmpty ? "VIDE" : appStore.token.substring(0, 20)}...');

    final response = await http.post(
      Uri.parse(_CONVERSATIONS_ENDPOINT),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer ${appStore.token}',
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      },
    );

    log('SupportChat: status=${response.statusCode} body=${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      // L'API peut retourner directement l'id ou le nester dans "conversation"
      _conversationId = (body['id'] ?? body['conversation']?['id'])?.toString() ?? '';
      if (_conversationId!.isEmpty) throw 'Conversation ID introuvable dans la réponse';
      return _conversationId!;
    } else {
      String detail = '';
      try {
        final body = jsonDecode(response.body);
        detail = body['detail'] ?? body['message'] ?? body['error'] ?? '';
      } catch (_) {
        detail = response.body;
      }
      throw 'Erreur ${response.statusCode}${detail.isNotEmpty ? " : $detail" : ""}';
    }
  }

  /// Crée ou récupère le chat privé client ↔ ouvrier d'une commande
  Future<String> createOrGetOrderConversation(String orderId) async {
    final response = await http.post(
      Uri.parse('$_CONVERSATIONS_ENDPOINT/order'),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer ${appStore.token}',
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      },
      body: jsonEncode({'order_id': orderId}),
    );

    log('OrderChat: status=${response.statusCode} body=${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      _conversationId = body['id']?.toString() ?? '';
      if (_conversationId!.isEmpty) throw 'Conversation ID introuvable dans la réponse';
      return _conversationId!;
    }

    String detail = '';
    try {
      final body = jsonDecode(response.body);
      detail = body['detail'] ?? body['message'] ?? body['error'] ?? '';
    } catch (_) {
      detail = response.body;
    }
    throw 'Erreur ${response.statusCode}${detail.isNotEmpty ? " : $detail" : ""}';
  }

  /// Connecte (ou reconnecte) le WebSocket
  Future<void> connect(String conversationId) async {
    _conversationId = conversationId;
    _isReady = false;
    _channel?.sink.close();

    final uri = Uri.parse('$_WS_BASE/$conversationId?token=${appStore.token}');
    _channel = WebSocketChannel.connect(uri);

    // Monter le listener AVANT await ready pour ne pas rater l'historique
    _channel!.stream.listen(
      _handleIncoming,
      onError: (e) {
        _isReady = false;
        if (!_connectionController.isClosed) _connectionController.add(false);
        log('SupportChat WS error: $e');
      },
      onDone: () {
        _isReady = false;
        if (!_connectionController.isClosed) _connectionController.add(false);
        log('SupportChat WS closed');
      },
    );

    await _channel!.ready;
    _isReady = true;
    if (!_connectionController.isClosed) _connectionController.add(true);
    log('SupportChat WS ready');
  }

  /// Reconnecte le WS — rafraîchit le token si nécessaire
  Future<bool> reconnect() async {
    if (_conversationId == null || _disposed) return false;
    try {
      final refreshed = await refreshToken();
      if (!refreshed) return false;
      await connect(_conversationId!);
      return true;
    } catch (e) {
      log('SupportChat reconnect error: $e');
      return false;
    }
  }

  void _handleIncoming(dynamic data) {
    try {
      final json = jsonDecode(data.toString()) as Map<String, dynamic>;
      final type = json['type']?.toString();

      if (type == 'history') {
        // Historique complet : {"type": "history", "messages": [...]}
        final rawList = json['messages'] as List<dynamic>? ?? [];
        final history = rawList
            .map((e) => SupportChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (!_historyController.isClosed) _historyController.add(history);
      } else {
        // Nouveau message en temps réel
        final message = SupportChatMessage.fromJson(json);
        if (!_newMessageController.isClosed) _newMessageController.add(message);
      }
    } catch (e) {
      log('SupportChat parse error: $e');
    }
  }

  /// Envoie un message texte, retourne true si envoyé, false si WS non prêt
  bool sendMessage(String content) {
    if (_channel == null || !_isReady) {
      log('SupportChat: tentative d\'envoi mais WS non prêt');
      return false;
    }
    _channel!.sink.add(jsonEncode({'type': 'message', 'content': content}));
    log('SupportChat: message envoyé → $content');
    return true;
  }

  /// Upload une image, retourne l'object_name ou null en cas d'erreur
  Future<String?> uploadImage(File file) async {
    if (_conversationId == null) return null;
    final ext = file.path.split('.').last.toLowerCase();
    final size = await file.length();
    log('SupportChat uploadImage: path=${file.path} ext=$ext size=${size}B');
    final uri = Uri.parse('${BASE_URL}chat/conversations/$_conversationId/upload-image');
    final request = http.MultipartRequest('POST', uri)
      ..headers[HttpHeaders.authorizationHeader] = 'Bearer ${appStore.token}'
      ..files.add(await http.MultipartFile.fromPath('image', file.path));
    try {
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      log('SupportChat uploadImage: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        return body['object_name']?.toString();
      }
    } catch (e) {
      log('SupportChat uploadImage error: $e');
    }
    return null;
  }

  /// Envoie un message image via WS, retourne true si envoyé
  bool sendImageMessage(String objectName) {
    if (_channel == null || !_isReady) {
      log('SupportChat: tentative d\'envoi image mais WS non prêt');
      return false;
    }
    _channel!.sink.add(jsonEncode({
      'type': 'message',
      'message_type': 'image',
      'content': objectName,
    }));
    log('SupportChat: image envoyée → $objectName');
    return true;
  }

  void dispose() {
    _disposed = true;
    _channel?.sink.close();
    _historyController.close();
    _newMessageController.close();
    _connectionController.close();
  }
}
