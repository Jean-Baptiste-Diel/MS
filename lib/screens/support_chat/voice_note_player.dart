import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Lecteur d'une note vocale dans une bulle de chat : lecture/pause,
/// barre de progression (déplaçable) et durée.
class VoiceNotePlayer extends StatefulWidget {
  final String url;

  const VoiceNotePlayer({Key? key, required this.url}) : super(key: key);

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  /// Lecture sur le haut-parleur : sans ça, après un enregistrement (session
  /// audio "voix") ou un appel, le son part dans l'écouteur, à peine audible.
  static final _speakerContext = AudioContextConfig(route: AudioContextConfigRoute.speaker).build();

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription> _subs = [];

  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loading = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _state = s);
      }),
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _position = Duration.zero);
      }),
    ]);
    _player.setAudioContext(_speakerContext).catchError((e) => log('VoiceNotePlayer context: $e'));
    // Charge la source sans jouer, pour afficher la durée tout de suite.
    _player.setSourceUrl(widget.url).catchError((e) {
      log('VoiceNotePlayer setSource: $e');
    });
  }

  Future<void> _toggle() async {
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
        return;
      }
      setState(() {
        _loading = true;
        _error = false;
      });
      // Réappliqué à chaque lecture : un enregistrement ou un appel entre-temps
      // a pu rebasculer la sortie audio vers l'écouteur.
      await _player.setAudioContext(_speakerContext);
      await _player.play(UrlSource(widget.url), position: _position);
    } catch (e) {
      log('VoiceNotePlayer play: $e');
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == PlayerState.playing;
    final total = _duration.inMilliseconds;
    final progress = total > 0 ? (_position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
    // Pendant la lecture : temps écoulé ; sinon : durée totale.
    final label = isPlaying || _position > Duration.zero ? _fmt(_position) : _fmt(_duration);

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      _error
                          ? Icons.error_outline
                          : isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: _toggle,
                  ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.35),
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: progress,
                onChanged: total > 0
                    ? (v) => _player.seek(Duration(milliseconds: (v * total).round()))
                    : null,
              ),
            ),
          ),
          6.width,
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
