import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'source_bridge_contract.dart';
import 'video_player_host.dart';

typedef VideoControllerFactory = VideoPlayerController Function(
  PreparedPlayback source,
);

class DatomVideoPlayerHost implements VideoPlayerHost {
  DatomVideoPlayerHost(this._onEvent, this._videoFactory) {
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _emitTime(),
    );
  }

  final void Function(Map<String, Object?>) _onEvent;
  final VideoControllerFactory _videoFactory;
  final AudioPlayer _audio = AudioPlayer();

  VideoPlayerController? _video;
  PreparedPlayback? _active;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  Timer? _timer;
  bool _lastPlaying = false;
  bool _lastBuffering = false;
  bool _lastCompleted = false;
  String? _lastError;
  double _volume = 1;
  bool _muted = false;
  double _rate = 1;

  void _emit(String kind, [Map<String, Object?> values = const {}]) {
    final source = _active;
    if (source == null) {
      return;
    }
    _onEvent({
      'kind': kind,
      'sourceGeneration': source.generation,
      ...values,
    });
  }

  @override
  Widget buildSurface() {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0
            ? 16 / 9
            : controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  @override
  Future<void> load(PreparedPlayback source) async {
    await close();
    _active = source;
    _lastPlaying = false;
    _lastBuffering = false;
    _lastCompleted = false;
    _lastError = null;
    if (source.kind == 'video') {
      final controller = _videoFactory(source);
      _video = controller;
      controller.addListener(_observeVideo);
      try {
        await controller.initialize();
        if (!identical(_active, source)) {
          return;
        }
        await controller.setVolume(_muted ? 0 : _volume);
        await controller.setPlaybackSpeed(_rate);
        _emit('loaded-metadata', {
          'duration': controller.value.duration.inMilliseconds / 1000,
          'width': controller.value.size.width.round(),
          'height': controller.value.size.height.round(),
        });
      } catch (_) {
        if (identical(_active, source)) {
          _emit('error', {'error': 'unsupported-format'});
        }
        rethrow;
      }
    } else {
      _audioStateSubscription =
          _audio.playerStateStream.listen(_observeAudioState);
      try {
        final duration = await _audio.setUrl(source.location);
        if (!identical(_active, source)) {
          return;
        }
        await _audio.setVolume(_muted ? 0 : _volume);
        await _audio.setSpeed(_rate);
        _emit('loaded-metadata', {
          'duration': (duration ?? Duration.zero).inMilliseconds / 1000,
          'width': 0,
          'height': 0,
        });
      } catch (_) {
        if (identical(_active, source)) {
          _emit('error', {'error': 'unsupported-format'});
        }
        rethrow;
      }
    }
  }

  void _observeVideo() {
    final controller = _video;
    if (controller == null || _active?.kind != 'video') {
      return;
    }
    final value = controller.value;
    if (value.hasError && value.errorDescription != _lastError) {
      _lastError = value.errorDescription;
      _emit('error', {'error': 'decode'});
    }
    if (value.isPlaying != _lastPlaying) {
      _lastPlaying = value.isPlaying;
      _emit(value.isPlaying ? 'playing' : 'pause');
    }
    if (value.isBuffering != _lastBuffering) {
      _lastBuffering = value.isBuffering;
      if (value.isBuffering) {
        _emit('waiting');
      }
    }
    if (value.isCompleted && !_lastCompleted) {
      _lastCompleted = true;
      _emit('ended');
    } else if (!value.isCompleted) {
      _lastCompleted = false;
    }
  }

  void _observeAudioState(PlayerState state) {
    final playing = state.playing;
    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      _emit(playing ? 'playing' : 'pause');
    }
    final buffering = state.processingState == ProcessingState.buffering ||
        state.processingState == ProcessingState.loading;
    if (buffering != _lastBuffering) {
      _lastBuffering = buffering;
      if (buffering) {
        _emit('waiting');
      }
    }
    final completed = state.processingState == ProcessingState.completed;
    if (completed && !_lastCompleted) {
      _lastCompleted = true;
      _emit('ended');
    } else if (!completed) {
      _lastCompleted = false;
    }
  }

  void _emitTime() {
    final source = _active;
    if (source == null) {
      return;
    }
    if (source.kind == 'video') {
      final value = _video?.value;
      if (value == null || !value.isInitialized) {
        return;
      }
      _emit('time', {
        'position': value.position.inMilliseconds / 1000,
        'duration': value.duration.inMilliseconds / 1000,
        'buffered': value.buffered
            .map((range) => [
                  range.start.inMilliseconds / 1000,
                  range.end.inMilliseconds / 1000,
                ])
            .toList(growable: false),
      });
    } else {
      _emit('time', {
        'position': _audio.position.inMilliseconds / 1000,
        'duration': (_audio.duration ?? Duration.zero).inMilliseconds / 1000,
        'buffered': [
          [0.0, _audio.bufferedPosition.inMilliseconds / 1000],
        ],
      });
    }
  }

  @override
  Future<void> play() async {
    if (_active?.kind == 'video') {
      await _video?.play();
    } else {
      await _audio.play();
    }
  }

  @override
  Future<void> pause() async {
    if (_active?.kind == 'video') {
      await _video?.pause();
    } else {
      await _audio.pause();
    }
  }

  @override
  Future<void> seek(double seconds) async {
    _emit('seeking');
    final position = Duration(milliseconds: (seconds * 1000).round());
    if (_active?.kind == 'video') {
      await _video?.seekTo(position);
    } else {
      await _audio.seek(position);
    }
    _emit('seeked');
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 1);
    if (!_muted) {
      if (_active?.kind == 'video') {
        await _video?.setVolume(_volume);
      } else {
        await _audio.setVolume(_volume);
      }
    }
    _emit('volume-change', {'volume': _volume, 'muted': _muted});
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    final effectiveVolume = muted ? 0.0 : _volume;
    if (_active?.kind == 'video') {
      await _video?.setVolume(effectiveVolume);
    } else {
      await _audio.setVolume(effectiveVolume);
    }
    _emit('volume-change', {'volume': _volume, 'muted': _muted});
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    if (_active?.kind == 'video') {
      await _video?.setPlaybackSpeed(rate);
    } else {
      await _audio.setSpeed(rate);
    }
    _emit('rate-change', {'rate': rate});
  }

  @override
  Future<void> close() async {
    final source = _active;
    _active = null;
    final video = _video;
    _video = null;
    if (video != null) {
      video.removeListener(_observeVideo);
      await video.dispose();
    }
    await _audioStateSubscription?.cancel();
    _audioStateSubscription = null;
    await _audio.stop();
    if (source != null) {
      await source.release();
    }
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await close();
    await _audio.dispose();
  }
}
