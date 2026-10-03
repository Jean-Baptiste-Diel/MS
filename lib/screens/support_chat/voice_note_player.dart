import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';

/// Lecteur d'une note vocale dans une bulle de chat : un seul bouton
/// lecture / pause (comme WhatsApp), barre de progression déplaçable, durée.
/// Une fois finie, la note revient au début : un appui sur lecture la
/// réécoute, autant de fois qu'on veut.
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

  /// Note en cours de lecture : en lancer une autre la met en pause, pour ne
  /// jamais entendre deux notes en même temps.
  static _VoiceNotePlayerState? _playing;

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
      // Fin de la note : retour au début, prête à être réécoutée (bouton lecture).
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _position = Duration.zero;
            _state = PlayerState.stopped;
          });
        }
      }),
    ]);
    // Garder le fichier chargé en fin de lecture : la réécoute repart tout de
    // suite, sans retélécharger la note (ReleaseMode.release par défaut).
    _player.setReleaseMode(ReleaseMode.stop).catchError((e) => log('VoiceNotePlayer release: $e'));
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
      await _pauseOtherNote();
      setState(() {
        _loading = true;
        _error = false;
      });
      // Réappliqué à chaque lecture : un enregistrement ou un appel entre-temps
      // a pu rebasculer la sortie audio vers l'écouteur.
      await _player.setAudioContext(_speakerContext);
      // Note déjà écoutée jusqu'au bout : on repart du début.
      final atEnd = _duration > Duration.zero && _position >= _duration - const Duration(milliseconds: 300);
      if (atEnd || _state == PlayerState.completed) _position = Duration.zero;
      await _player.play(UrlSource(widget.url), position: _position);
    } catch (e) {
      log('VoiceNotePlayer play: $e');
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pauseOtherNote() async {
    final other = _playing;
    if (other != null && other != this && other.mounted) {
      await other._player.pause();
    }
    _playing = this;
  }

  /// Déplacement dans la note, lecture en cours ou non : la position affichée
  /// suit le doigt, et la prochaine lecture repart de là.
  void _seekTo(double fraction) {
    final target = Duration(milliseconds: (fraction * _duration.inMilliseconds).round());
    setState(() => _position = target);
    _player.seek(target).catchError((e) => log('VoiceNotePlayer seek: $e'));
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    if (_playing == this) _playing = null;
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
                onChanged: total > 0 ? _seekTo : null,
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
