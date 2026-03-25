import 'dart:async';
import 'dart:io';

import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/services/support_chat_service.dart';
import 'package:booking_system_flutter/utils/colors.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';

// Délai avant de marquer un message pending comme failed
const _kSendTimeout = Duration(seconds: 10);

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({Key? key}) : super(key: key);

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final SupportChatService _service = SupportChatService();
  final ScrollController _scrollController = ScrollController();

  final List<SupportChatMessage> _messages = [];
  final Map<String, Timer> _pendingTimers = {};
  StreamSubscription? _historySub;
  StreamSubscription? _newMessageSub;
  StreamSubscription? _connectionSub;

  bool _isConnecting = true;
  bool _wsConnected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    setState(() {
      _isConnecting = true;
      _error = null;
      // Garder les messages failed existants pour permettre le retry
      _messages.removeWhere((m) => m.status != MessageStatus.failed);
    });

    try {
      // Rafraîchir le token avant tout appel pour s'assurer qu'il est valide
      await reGenerateToken().catchError((e) => log('Token refresh skipped: $e'));

      final conversationId = await _service.createOrGetConversation();
      await _service.connect(conversationId);

      _historySub = _service.historyStream.listen((history) {
        setState(() {
          // Supprimer les messages serveur existants, garder les failed locaux
          _messages.removeWhere((m) => m.status != MessageStatus.failed);
          _messages.insertAll(0, history);
          // Trier par date
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        _scrollToBottom();
      });

      _newMessageSub = _service.newMessageStream.listen((msg) {
        setState(() {
          if (msg.isMe) {
            _messages.removeWhere(
              (m) => m.status == MessageStatus.pending && m.content == msg.content,
            );
          }
          final exists = msg.id.isNotEmpty && _messages.any((m) => m.id == msg.id);
          if (!exists) _messages.add(msg);
        });
        _scrollToBottom();
      });

      // Écouter les changements d'état de connexion WS
      _connectionSub?.cancel();
      _connectionSub = _service.connectionStream.listen((connected) {
        setState(() => _wsConnected = connected);
      });
      setState(() => _wsConnected = true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  void _handleSend(String content, String messageType) {
    if (messageType == 'image') {
      _service.sendImageMessage(content);
    } else {
      _sendMessage(content);
    }
  }

  void _sendMessage(String text, {String? retryLocalId}) async {
    if (text.isEmpty) return;

    // Si retry, remettre en pending
    if (retryLocalId != null) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.localId == retryLocalId);
        if (idx != -1) _messages[idx].status = MessageStatus.pending;
      });
    }

    // Reconnecter automatiquement si WS fermé
    if (!_service.isReady) {
      setState(() => _wsConnected = false);
      final localId = retryLocalId ?? _addPending(text);
      final reconnected = await _service.reconnect();
      if (!reconnected) {
        _markFailed(localId);
        return;
      }
      setState(() => _wsConnected = true);
      final sent = _service.sendMessage(text);
      if (!sent) { _markFailed(localId); return; }
      _pendingTimers[localId]?.cancel();
      _pendingTimers[localId] = Timer(_kSendTimeout, () => _markFailed(localId));
      return;
    }

    final sent = _service.sendMessage(text);
    if (!sent) {
      _markFailed(retryLocalId ?? _addPending(text));
      return;
    }

    final localId = retryLocalId ?? _addPending(text);
    _pendingTimers[localId]?.cancel();
    _pendingTimers[localId] = Timer(_kSendTimeout, () => _markFailed(localId));
  }

  /// Ajoute un message optimiste, retourne son localId
  String _addPending(String content) {
    final msg = SupportChatMessage.optimistic(content);
    setState(() => _messages.add(msg));
    _scrollToBottom();
    return msg.localId;
  }


  void _markFailed(String localId) {
    _pendingTimers.remove(localId)?.cancel();
    setState(() {
      final idx = _messages.indexWhere((m) => m.localId == localId);
      if (idx != -1) _messages[idx].status = MessageStatus.failed;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    for (final t in _pendingTimers.values) {
      t.cancel();
    }
    _historySub?.cancel();
    _newMessageSub?.cancel();
    _connectionSub?.cancel();
    _service.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => hideKeyboard(context),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: context.primaryColor,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Support Mison', style: boldTextStyle(color: Colors.white, size: 16)),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _wsConnected ? Colors.greenAccent : Colors.orange,
                    ),
                  ),
                  4.width,
                  Text(
                    _wsConnected ? 'Connecté' : 'Reconnexion...',
                    style: secondaryTextStyle(color: Colors.white70, size: 11),
                  ),
                ],
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => finish(context),
          ),
        ),
        body: Column(
          children: [
            Expanded(child: _buildBody()),
            if (!_isConnecting && _error == null) _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isConnecting) return LoaderWidget().center();

    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
          16.height,
          Text(_error!, style: secondaryTextStyle(), textAlign: TextAlign.center),
          16.height,
          AppButton(text: 'Réessayer', color: primaryColor, onTap: _initChat),
        ],
      ).paddingSymmetric(horizontal: 32);
    }

    if (_messages.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.support_agent_rounded, size: 64, color: Colors.grey),
          16.height,
          Text('Démarrez la conversation', style: boldTextStyle()),
          8.height,
          Text('Notre équipe vous répondra dans les plus brefs délais.', style: secondaryTextStyle(), textAlign: TextAlign.center),
        ],
      ).paddingSymmetric(horizontal: 32);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
    );
  }

  Widget _buildMessageBubble(SupportChatMessage msg) {
    final isMe = msg.isMe;
    const Color bubbleMe = Color(0xFFC99700);
    const Color bubbleOther = Color(0xFF1A1A1A);
    final isFailed = msg.status == MessageStatus.failed;
    final isPending = msg.status == MessageStatus.pending;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && msg.senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(msg.senderName, style: secondaryTextStyle(size: 11)),
            ),
          Container(
            constraints: BoxConstraints(maxWidth: context.width() * 0.72),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isFailed
                  ? const Color(0xFFB00020)
                  : isMe
                      ? bubbleMe.withValues(alpha: isPending ? 0.6 : 1.0)
                      : bubbleOther,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
              boxShadow: defaultBoxShadow(blurRadius: 4, spreadRadius: 0),
            ),
            child: msg.isImage
                ? _buildImageContent(msg)
                : Text(msg.content, style: primaryTextStyle(color: Colors.white)),
          ),
          // Heure + indicateur d'état
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(msg.createdAt),
                  style: secondaryTextStyle(size: 10),
                ),
                if (isMe) ...[
                  4.width,
                  if (isPending)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey),
                    )
                  else if (isFailed)
                    GestureDetector(
                      onTap: () => _sendMessage(msg.content, retryLocalId: msg.localId),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 12, color: Color(0xFFB00020)),
                          4.width,
                          Text(
                            'Échec · Réessayer',
                            style: secondaryTextStyle(size: 10, color: const Color(0xFFB00020)),
                          ),
                        ],
                      ),
                    )
                  else
                    const Icon(Icons.done_all, size: 12, color: Colors.grey),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent(SupportChatMessage msg) {
    // Optimistic : affichage depuis les bytes en mémoire
    if ((msg.status == MessageStatus.pending || msg.status == MessageStatus.failed) && msg.localBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          msg.localBytes!,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
        ),
      );
    }
    // Message confirmé : imageUrl si dispo, sinon proxy HTTPS en fallback
    final url = (msg.imageUrl != null && msg.imageUrl!.isNotEmpty)
        ? msg.imageUrl!
        : 'https://api.mison.app/media/minio/${msg.content}';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        placeholder: (_, __) => const SizedBox(
          width: 200,
          height: 200,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white),
      ),
    );
  }

  Widget _buildInputBar() {
    return ChatInput(
      onUpload: _service.uploadImage,
      onSend: _handleSend,
      enabled: _wsConnected,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ChatInput extends StatefulWidget {
  final Future<String?> Function(File file) onUpload;
  final void Function(String content, String messageType) onSend;
  final bool enabled;

  const ChatInput({
    Key? key,
    required this.onUpload,
    required this.onSend,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();

  File? _selectedImage;
  bool _isUploading = false;

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedImage = File(picked.path));
  }

  Future<void> _send() async {
    if (_isUploading) return;

    if (_selectedImage != null) {
      setState(() => _isUploading = true);
      try {
        final objectName = await widget.onUpload(_selectedImage!);
        if (!mounted) return;
        if (objectName == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Échec de l\'upload')),
          );
          return;
        }
        widget.onSend(objectName, 'image');
        setState(() => _selectedImage = null);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    } else {
      final text = _textController.text.trim();
      if (text.isEmpty) return;
      _textController.clear();
      widget.onSend(text, 'text');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        boxShadow: defaultBoxShadow(blurRadius: 8, spreadRadius: 0),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedImage != null) _buildPreview(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    color: primaryColor,
                    onPressed: (widget.enabled && !_isUploading) ? _pickImage : null,
                  ),
                  Expanded(
                    child: AppTextField(
                      textFieldType: TextFieldType.OTHER,
                      controller: _textController,
                      focus: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      enabled: widget.enabled && !_isUploading && _selectedImage == null,
                      onFieldSubmitted: (_) => _send(),
                      decoration: inputDecoration(context).copyWith(
                        hintText: _selectedImage != null ? 'Image prête à envoyer' : 'Votre message...',
                        hintStyle: secondaryTextStyle(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  8.width,
                  Container(
                    decoration: boxDecorationDefault(borderRadius: radius(40), color: primaryColor),
                    child: _isUploading
                        ? const SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send_rounded, color: Colors.white),
                            onPressed: widget.enabled ? _send : null,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _selectedImage!,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          8.width,
          Expanded(child: Text('Image prête à envoyer', style: secondaryTextStyle())),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: _isUploading ? null : () => setState(() => _selectedImage = null),
          ),
        ],
      ),
    );
  }
}
