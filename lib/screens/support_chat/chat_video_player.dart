import 'dart:async';
import 'dart:io';

import 'package:booking_system_flutter/component/loader_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Vidéo du chat en plein écran, comme la photo : fond noir, lecture / pause
/// d'un appui, barre de progression pour avancer ou reculer, croix ou
/// glisser vers le bas pour fermer. Les commandes se masquent pendant la
/// lecture ; un appui les fait réapparaître.
class ChatVideoPlayer extends StatefulWidget {
  final String? url;
  final File? file;

  const ChatVideoPlayer({super.key, this.url, this.file});

  static void open(BuildContext context, {String? url, File? file}) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => ChatVideoPlayer(url: url, file: file),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  State<ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

class _ChatVideoPlayerState extends State<ChatVideoPlayer> {
  late final VideoPlayerController _controller = widget.file != null
      ? VideoPlayerController.file(widget.file!)
      : VideoPlayerController.networkUrl(Uri.parse(widget.url ?? ''));
  bool _ready = false;
  bool _failed = false;
  bool _showControls = true;
  Timer? _hideTimer;
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _onTick() {
    if (!mounted) return;
    // Fin de la vidéo : commandes visibles pour la relancer.
    if (_ready && !_controller.value.isPlaying && !_showControls) {
      setState(() => _showControls = true);
    } else {
      setState(() {});
    }
  }

  void _play() {
    if (_controller.value.position >= _controller.value.duration) _controller.seekTo(Duration.zero);
    _controller.play();
    _scheduleHide();
  }

  void _togglePlay() {
    if (!_ready) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      _play();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) setState(() => _showControls = false);
    });
  }

  void _onTap() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  String _format(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    final opacity = (1 - _dragDy.abs() / 400).clamp(0.3, 1.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: opacity),
        body: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTap,
              onVerticalDragUpdate: (d) => setState(() => _dragDy += d.delta.dy),
              onVerticalDragEnd: (_) {
                if (_dragDy.abs() > 120) {
                  Navigator.pop(context);
                } else {
                  setState(() => _dragDy = 0);
                }
              },
              child: Transform.translate(
                offset: Offset(0, _dragDy),
                child: Center(
                  child: _failed
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48),
                          const SizedBox(height: 12),
                          Text('Vidéo indisponible', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                        ])
                      : !_ready
                          ? const LoaderWidget(colors: [Colors.white, Color(0xFFC49716)])
                          : AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(_controller)),
                ),
              ),
            ),
            if (_ready && _showControls) ...[
              Center(
                child: GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                    child: Icon(
                      value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Text(_format(value.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            colors: const VideoProgressColors(
                              playedColor: Color(0xFFC49716),
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(_format(value.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
