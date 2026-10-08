import 'package:booking_system_flutter/utils/configs.dart' show DOMAIN_URL;
import 'package:booking_system_flutter/screens/support_chat/chat_image_viewer.dart';
import 'package:booking_system_flutter/services/chat_unread_store.dart';
import 'package:booking_system_flutter/utils/image_pick_sizes.dart';
import 'package:booking_system_flutter/utils/image_cache_key.dart';
import 'dart:async';
import 'dart:io';

import 'package:booking_system_flutter/utils/mison_call_utils.dart';
import 'package:booking_system_flutter/component/mison_app_bar.dart';
import 'package:booking_system_flutter/component/dot_grid_background.dart';
import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:booking_system_flutter/network/network_utils.dart';
import 'package:booking_system_flutter/services/support_chat_service.dart';
import 'package:booking_system_flutter/utils/common.dart';
import 'package:booking_system_flutter/utils/order_events.dart';
import 'package:booking_system_flutter/utils/top_toast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'voice_note_player.dart';

// Délai avant de marquer un message pending comme failed
const _kSendTimeout = Duration(seconds: 10);

class SupportChatScreen extends StatefulWidget {
  /// Quand renseigné, l'écran ouvre le chat privé client ↔ ouvrier de cette
  /// commande au lieu de la conversation de support.
  final String? orderId;
  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;

  /// Nom de l'interlocuteur à appeler ; si renseigné (chat de commande),
  /// un bouton d'appel s'affiche en face du nom.
  final String? callPeerName;

  const SupportChatScreen({
    Key? key,
    this.orderId,
    this.title = 'Support Mison',
    this.emptyTitle = 'Démarrez la conversation',
    this.emptySubtitle = 'Notre équipe vous répondra dans les plus brefs délais.',
    this.emptyIcon = Icons.support_agent_rounded,
    this.callPeerName,
  }) : super(key: key);

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
  StreamSubscription? _errorSub;
  StreamSubscription? _closedSub;
  StreamSubscription<String?>? _orderEventsSub;
  bool _left = false;

  bool _isConnecting = true;
  bool _wsConnected = false;
  String? _error;

  // Reconnexion automatique : le socket peut tomber sur simple perte réseau,
  // l'utilisateur ne doit pas avoir à quitter puis rouvrir l'écran.
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const _kMaxReconnectAttempts = 5;

  @override
  void initState() {
    super.initState();
    _initChat();
    // Commande terminée pendant la discussion : elle se ferme et disparaît.
    if (widget.orderId != null) {
      _orderEventsSub = OrderEvents.stream.listen((id) {
        if (id == null || id == widget.orderId) _checkStillOpen();
      });
    }
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
      await refreshToken();

      final conversationId = widget.orderId != null
          ? await _service.createOrGetOrderConversation(widget.orderId!)
          : await _service.createOrGetConversation();
      // Prestation terminée : la discussion n'existe plus pour eux.
      if (widget.orderId != null && !_service.canSend) {
        _leaveClosedChat();
        return;
      }
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

      // Le serveur n'a pas pu traiter un message : les messages sont traités
      // dans l'ordre, c'est donc le plus ancien encore en attente qui a échoué.
      // Il passe en "échec" tout de suite (avec le bouton réessayer).
      // La prestation s'est terminée pendant la discussion : lecture seule.
      _closedSub?.cancel();
      _closedSub = _service.closedStream.listen((_) => _leaveClosedChat());

      _errorSub?.cancel();
      _errorSub = _service.errorStream.listen((error) {
        if (!mounted) return;
        final pending = _messages.where(
          (m) => m.isMe && m.status == MessageStatus.pending && !m.isImage,
        );
        if (pending.isNotEmpty) _markFailed(pending.first.localId);
        TopToast.show(message: error, type: TopToastType.error);
      });

      // Écouter les changements d'état de connexion WS
      _connectionSub?.cancel();
      _connectionSub = _service.connectionStream.listen((connected) {
        if (!mounted) return;
        setState(() => _wsConnected = connected);
        if (connected) {
          _reconnectAttempt = 0;
          _reconnectTimer?.cancel();
        } else {
          _scheduleReconnect();
        }
      });
      _reconnectAttempt = 0;
      setState(() => _wsConnected = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _scheduleReconnect() {
    if (!mounted || _reconnectAttempt >= _kMaxReconnectAttempts) return;
    _reconnectTimer?.cancel();
    // Back-off progressif : 2s, 4s, 6s, 8s, 10s.
    final delay = Duration(seconds: 2 * (_reconnectAttempt + 1));
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () async {
      if (!mounted || _service.isReady) return;
      final ok = await _service.reconnect();
      if (!mounted) return;
      if (ok) {
        setState(() => _wsConnected = true);
        _reconnectAttempt = 0;
      } else {
        _scheduleReconnect();
      }
    });
  }

  void _handleSend(String content, String messageType) {
    if (messageType == 'image') {
      _service.sendImageMessage(content);
    } else if (messageType == 'audio') {
      if (!_service.sendAudioMessage(content)) {
        TopToast.show(message: 'Note vocale non envoyée, réessayez.', type: TopToastType.error);
      }
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
    ChatUnreadStore.refresh(); // pastilles à jour en revenant à la liste
    for (final t in _pendingTimers.values) {
      t.cancel();
    }
    _reconnectTimer?.cancel();
    _historySub?.cancel();
    _newMessageSub?.cancel();
    _connectionSub?.cancel();
    _errorSub?.cancel();
    _closedSub?.cancel();
    _orderEventsSub?.cancel();
    _service.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => hideKeyboard(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Logo centré + fond de la page, comme l'accueil
        appBar: MisonAppBar(
          title: widget.title,
          // Bouton d'appel en face du nom (chat d'une commande uniquement)
          titleTrailing: _canCall
              ? GestureDetector(
                  onTap: () => startMisonOrderCall(
                    context,
                    orderId: widget.orderId!,
                    otherPartyName: widget.callPeerName!,
                  ),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kMisonGold,
                      boxShadow: [
                        BoxShadow(
                          color: kMisonGold.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                  ),
                )
              : null,
          subtitle: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _wsConnected ? Colors.green : kMisonGold,
                ),
              ),
              4.width,
              Text(
                _wsConnected ? 'Connecté' : 'Reconnexion...',
                style: secondaryTextStyle(size: 13),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: kMisonDark),
            onPressed: () => finish(context),
          ),
        ),
        body: DotGridBackground(
          child: Column(
            children: [
              Expanded(child: _buildBody()),
              if (!_isConnecting && _error == null)
                _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isConnecting) return LoaderWidget(colors: const [kMisonDark, kMisonGold]).center();

    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
          16.height,
          Text(_error!, style: secondaryTextStyle(), textAlign: TextAlign.center),
          16.height,
          AppButton(text: 'Réessayer', color: kMisonGold, onTap: _initChat),
        ],
      ).paddingSymmetric(horizontal: 32);
    }

    if (_messages.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.emptyIcon, size: 64, color: Colors.grey),
          16.height,
          Text(widget.emptyTitle, style: boldTextStyle()),
          8.height,
          Text(widget.emptySubtitle, style: secondaryTextStyle(), textAlign: TextAlign.center),
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

  /// Appel dans la conversation, façon WhatsApp : bulle alignée comme un
  /// message (à droite si j'ai appelé), icône ronde, « Appel vocal » et, en
  /// dessous, flèche de direction + durée ou issue. Un appui rappelle.
  Widget _buildCallEvent(SupportChatMessage msg) {
    final isMe = msg.isMe;
    final onBubble = Colors.white;
    final ok = isMe ? const Color(0xFF0B5D1E) : Colors.greenAccent.shade400;
    final missedIncoming = !isMe && msg.callOutcome != 'completed';

    final String title;
    final String subtitle;
    switch (msg.callOutcome) {
      case 'completed':
        final d = msg.callDurationSeconds;
        title = 'Appel vocal';
        subtitle = d >= 60 ? '${d ~/ 60} min ${(d % 60).toString().padLeft(2, '0')} s' : '$d s';
      case 'declined':
        title = isMe ? 'Appel vocal' : 'Appel vocal manqué';
        subtitle = isMe ? 'Refusé' : 'Vous avez refusé';
      default: // missed
        title = isMe ? 'Appel vocal' : 'Appel vocal manqué';
        subtitle = isMe ? 'Pas de réponse' : 'Appuyez pour rappeler';
    }
    final arrowColor = missedIncoming ? Colors.redAccent.shade100 : ok;
    final arrow = isMe
        ? Icons.north_east_rounded
        : missedIncoming
            ? Icons.call_missed_rounded
            : Icons.south_west_rounded;

    final canCallBack = _canCall;
    const radius16 = Radius.circular(16);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: context.width() * 0.72, minWidth: 210),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFC99700) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: radius16,
            topRight: radius16,
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: defaultBoxShadow(blurRadius: 4, spreadRadius: 0),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: canCallBack
                ? () => startMisonOrderCall(
                      context,
                      orderId: widget.orderId!,
                      otherPartyName: widget.callPeerName!,
                    )
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: onBubble.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          missedIncoming ? Icons.phone_missed_rounded : Icons.call_rounded,
                          size: 21,
                          color: missedIncoming ? Colors.redAccent.shade100 : onBubble,
                        ),
                      ),
                      12.width,
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: boldTextStyle(size: 15, color: onBubble),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            3.height,
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(arrow, size: 14, color: arrowColor),
                                4.width,
                                Flexible(
                                  child: Text(
                                    subtitle,
                                    style: primaryTextStyle(size: 13, color: onBubble.withValues(alpha: 0.8)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      8.width,
                    ],
                  ),
                  2.height,
                  Text(
                    DateFormat('HH:mm').format(msg.createdAt),
                    style: secondaryTextStyle(size: 11, color: onBubble.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(SupportChatMessage msg) {
    if (msg.isCall) return _buildCallEvent(msg);
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
              child: Text(msg.senderName, style: secondaryTextStyle(size: 13)),
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
                : msg.isAudio
                    ? VoiceNotePlayer(
                        url: (msg.audioUrl != null && msg.audioUrl!.isNotEmpty)
                            ? msg.audioUrl!
                            : '$DOMAIN_URL/media/minio/${msg.content}',
                      )
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
                  style: secondaryTextStyle(size: 12),
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
                            style: secondaryTextStyle(size: 12, color: const Color(0xFFB00020)),
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
    final heroTag = 'chat-image-${msg.id}';
    // Optimistic : affichage depuis les bytes en mémoire
    if ((msg.status == MessageStatus.pending || msg.status == MessageStatus.failed) && msg.localBytes != null) {
      return GestureDetector(
        onTap: () => ChatImageViewer.open(context, bytes: msg.localBytes, heroTag: heroTag),
        child: Hero(
          tag: heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(msg.localBytes!, width: 200, height: 200, fit: BoxFit.cover),
          ),
        ),
      );
    }
    // Message confirmé : imageUrl si dispo, sinon proxy HTTPS en fallback
    final url = (msg.imageUrl != null && msg.imageUrl!.isNotEmpty)
        ? msg.imageUrl!
        : '$DOMAIN_URL/media/minio/${msg.content}';
    // Appui : l'image en grand (zoom, glisser vers le bas pour fermer).
    return GestureDetector(
      onTap: () => ChatImageViewer.open(context, url: url, heroTag: heroTag),
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: url,
            cacheKey: imageCacheKey(url),
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            placeholder: (_, __) => const SizedBox(
              width: 200,
              height: 200,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: kMisonGold)),
            ),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// Appel possible : chat d'une commande encore en cours.
  bool get _canCall => widget.orderId != null && widget.callPeerName != null && _service.canSend;

  Future<void> _checkStillOpen() async {
    if (_left) return;
    try {
      await _service.createOrGetOrderConversation(widget.orderId!);
      if (!_service.canSend) _leaveClosedChat();
    } catch (_) {
      // réseau : le serveur refusera de toute façon les envois
    }
  }

  /// La prestation est terminée : la discussion se ferme (elle n'apparaît plus
  /// dans « Discussions » jusqu'à une nouvelle commande ensemble).
  void _leaveClosedChat() {
    if (_left || !mounted) return;
    _left = true;
    TopToast.show(message: 'Prestation terminée : cette discussion est fermée.');
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
  }

  Widget _buildInputBar() {
    return ChatInput(
      onUpload: _service.uploadImage,
      onUploadAudio: _service.uploadAudio,
      onSend: _handleSend,
      enabled: _wsConnected,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ChatInput extends StatefulWidget {
  final Future<String?> Function(File file) onUpload;
  final Future<String?> Function(File file) onUploadAudio;
  final void Function(String content, String messageType) onSend;
  final bool enabled;

  const ChatInput({
    Key? key,
    required this.onUpload,
    required this.onUploadAudio,
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

  // ── Note vocale : maintenir le micro pour enregistrer, relâcher pour
  // envoyer, glisser vers la gauche pour annuler.
  static const _maxRecordDuration = Duration(minutes: 2);
  static const _minRecordDuration = Duration(seconds: 1);
  static const _cancelSlideDistance = 90.0;
  static const _lockSlideDistance = 55.0;

  final _recorder = AudioRecorder();
  Future<void>? _recorderStarting;
  Timer? _recordTimer;
  bool _isRecording = false;
  bool _isLocked = false;
  bool _isPaused = false;
  Duration _recordElapsed = Duration.zero;
  double _slideDx = 0;
  // 0 → 1 : progression du glissement vers le cadenas (comme WhatsApp).
  double _slideUp = 0;
  // Point rouge qui clignote pendant l'enregistrement.
  Timer? _blinkTimer;
  bool _dotVisible = true;
  Offset? _pointerDownPos;
  bool _hasText = false;

  bool get _slideCancels => _slideDx < -_cancelSlideDistance;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  Future<void> _startRecording() async {
    if (!widget.enabled || _isUploading || _isRecording) return;
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Autorisez l\'accès au micro pour envoyer une note vocale.')),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/note_${DateTime.now().millisecondsSinceEpoch}.m4a';
    HapticFeedback.mediumImpact();
    setState(() {
      _isRecording = true;
      _isLocked = false;
      _isPaused = false;
      _recordElapsed = Duration.zero;
      _slideDx = 0;
      _slideUp = 0;
      _dotVisible = true;
    });
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && !_isPaused) setState(() => _dotVisible = !_dotVisible);
    });
    // AAC mono 64 kb/s : ~0,5 Mo par minute, qualité voix suffisante.
    _recorderStarting = _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
      path: path,
    );
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isPaused) return;
      setState(() => _recordElapsed += const Duration(seconds: 1));
      if (_recordElapsed >= _maxRecordDuration) _stopRecording(send: true);
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _blinkTimer?.cancel();
    final elapsed = _recordElapsed;
    setState(() {
      _isRecording = false;
      _isLocked = false;
      _isPaused = false;
      _slideUp = 0;
    });

    // L'appui a pu être relâché avant la fin du démarrage de l'enregistreur.
    try {
      await _recorderStarting;
    } catch (e) {
      log('record start: $e');
      return;
    }

    // Annulée, ou trop courte (moins d'1 s, appui bref) : abandonnée sans message.
    if (!send || elapsed < _minRecordDuration) {
      await _recorder.cancel();
      return;
    }

    final path = await _recorder.stop();
    if (path == null || !mounted) return;
    final file = File(path);
    setState(() => _isUploading = true);
    try {
      final objectName = await widget.onUploadAudio(file);
      if (!mounted) return;
      if (objectName == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de l\'envoi de la note vocale')),
        );
        return;
      }
      widget.onSend(objectName, 'audio');
    } finally {
      if (mounted) setState(() => _isUploading = false);
      file.delete().catchError((_) => file);
    }
  }

  /// Enregistrement verrouillé : pause / reprise (comme WhatsApp).
  Future<void> _togglePause() async {
    try {
      await _recorderStarting;
      if (_isPaused) {
        await _recorder.resume();
      } else {
        await _recorder.pause();
      }
      if (mounted) setState(() {
        _isPaused = !_isPaused;
        _dotVisible = true;
      });
    } catch (e) {
      log('record pause: $e');
    }
  }

  String _formatElapsed(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: kChatPhotoQuality,
      maxWidth: kChatPhotoMaxSide,
      maxHeight: kChatPhotoMaxSide,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedImage = File(picked.path));
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: kMisonGold),
                title: const Text('Galerie'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_outlined, color: kMisonGold),
                title: const Text('Appareil photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.camera);
                },
              ),
              8.height,
            ],
          ),
        );
      },
    );
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
    _recordTimer?.cancel();
    _blinkTimer?.cancel();
    _recorder.dispose();
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
            if (_isRecording && _isLocked)
              _buildLockedRecordingBar()
            else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    color: kMisonGold,
                    onPressed: (widget.enabled && !_isUploading && !_isRecording) ? _showImageSourceSheet : null,
                  ),
                  Expanded(
                    child: _isRecording
                        ? _buildRecordingIndicator()
                        : AppTextField(
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
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: boxDecorationDefault(borderRadius: radius(40), color: kMisonGold),
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
                            : (_hasText || _selectedImage != null)
                                ? IconButton(
                                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                                    onPressed: widget.enabled ? _send : null,
                                  )
                                : _buildMicButton(),
                      ),
                      // Cadenas au-dessus du micro : glisser vers le haut verrouille.
                      if (_isRecording && !_isLocked)
                        Positioned(
                          bottom: 58 + 24 * _slideUp,
                          right: 2,
                          child: _LockHint(progress: _slideUp),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton() {
    return Listener(
      onPointerDown: (e) {
        // Enregistrement verrouillé : le bouton est devenu « envoyer ».
        if (_isRecording && _isLocked) {
          _stopRecording(send: true);
          return;
        }
        if (widget.enabled && !_isUploading && !_isRecording) {
          _pointerDownPos = e.position;
          _startRecording();
        }
      },
      onPointerMove: (e) {
        if (_isRecording && _pointerDownPos != null) {
          final dx = e.position.dx - _pointerDownPos!.dx;
          final dy = e.position.dy - _pointerDownPos!.dy;
          setState(() {
            _slideDx = dx;
            _slideUp = (-dy / _lockSlideDistance).clamp(0.0, 1.0);
            if (dy < -_lockSlideDistance && !_isLocked) {
              _isLocked = true;
              HapticFeedback.heavyImpact();
            }
          });
          if (dx < -_cancelSlideDistance) {
            _stopRecording(send: false);
            _pointerDownPos = null;
          }
        }
      },
      onPointerUp: (e) {
        if (_isRecording && !_isLocked) {
          _stopRecording(send: !_slideCancels);
        }
        _pointerDownPos = null;
      },
      onPointerCancel: (e) {
        if (_isRecording && !_isLocked) {
          _stopRecording(send: false);
        }
        _pointerDownPos = null;
      },
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(
          _isRecording ? (_isLocked ? Icons.send_rounded : Icons.mic_rounded) : Icons.mic_none_rounded,
          color: widget.enabled ? Colors.white : Colors.white54,
        ),
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    // Le texte suit le doigt et s'efface à mesure qu'on glisse vers l'annulation.
    final cancelProgress = (-_slideDx / _cancelSlideDistance).clamp(0.0, 1.0);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: boxDecorationDefault(
        borderRadius: radius(24),
        color: context.cardColor,
        border: Border.all(color: kMisonGold.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: _dotVisible ? 1 : 0.15,
            child: const Icon(Icons.mic_rounded, color: Colors.red, size: 20),
          ),
          6.width,
          Text(_formatElapsed(_recordElapsed), style: boldTextStyle(size: 14)),
          Expanded(
            child: Transform.translate(
              offset: Offset(_slideDx.clamp(-_cancelSlideDistance, 0.0) * 0.6, 0),
              child: Opacity(
                opacity: 1 - cancelProgress * 0.8,
                child: Text(
                  '‹  Glisser pour annuler',
                  style: secondaryTextStyle(size: 13, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Enregistrement verrouillé, comme WhatsApp : chrono en haut ; poubelle,
  /// pause / reprise et envoyer en bas. Le doigt peut être relâché.
  Widget _buildLockedRecordingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Opacity(
                opacity: _isPaused || _dotVisible ? 1 : 0.15,
                child: Icon(Icons.fiber_manual_record, color: _isPaused ? Colors.grey : Colors.red, size: 14),
              ),
              8.width,
              Text(_formatElapsed(_recordElapsed), style: boldTextStyle(size: 16)),
              12.width,
              Expanded(
                child: Text(
                  _isPaused ? 'En pause' : 'Enregistrement…',
                  style: secondaryTextStyle(size: 13),
                ),
              ),
            ],
          ),
          10.height,
          Row(
            children: [
              IconButton(
                tooltip: 'Supprimer',
                onPressed: () => _stopRecording(send: false),
                icon: Icon(Icons.delete_outline_rounded, color: Colors.grey.shade700, size: 28),
              ),
              const Spacer(),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: _togglePause,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                  child: Icon(_isPaused ? Icons.mic_rounded : Icons.pause_rounded, color: Colors.red),
                ),
              ),
              const Spacer(),
              Container(
                decoration: boxDecorationDefault(borderRadius: radius(40), color: kMisonGold),
                child: IconButton(
                  tooltip: 'Envoyer',
                  onPressed: () => _stopRecording(send: true),
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
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

/// Cadenas au-dessus du micro pendant l'enregistrement (comme WhatsApp) :
/// ouvert avec une flèche vers le haut, il se ferme et passe au doré à mesure
/// que le doigt glisse vers lui.
class _LockHint extends StatelessWidget {
  final double progress;
  const _LockHint({required this.progress});

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(Colors.grey.shade600, kMisonGold, progress)!;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(progress >= 0.95 ? Icons.lock_rounded : Icons.lock_open_rounded, color: color, size: 22),
          Opacity(
            opacity: 1 - progress,
            child: Icon(Icons.keyboard_arrow_up_rounded, color: Colors.grey.shade500, size: 22),
          ),
        ],
      ),
    );
  }
}
