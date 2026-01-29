import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:async';

import '../models/models.dart';
import 'dab_api_service.dart';
import 'audio_handler.dart';
import 'history_service.dart';
import 'last_fm_service.dart';

class AudioPlayerService with ChangeNotifier {
  final AppAudioHandler _handler;
  final DabApiService _dabApiService;

  // Local state mirrored from Handler
  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero; // Added
  double _volume = 0.8;

  List<Track> _queue = [];
  int _currentIndex = -1;

  // Custom LoopMode mirroring AudioService RepeatMode
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;

  // Lyrics
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  bool _isFetchingLyrics = false;

  // Getters
  List<Track> get queue => _queue;
  List<Track> get internalQueue => _queue;
  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition; // Added
  // Note: AudioHandler doesn't expose volume in state usually,
  // but we can manage it somewhat or just assume system volume + local override?
  // We'll trust the stored _volume and re-apply if needed, but JustAudio handles it.
  double get volume => _volume;
  int get currentIndex => _currentIndex;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;
  List<LyricLine> get lyrics => _lyrics;
  int get currentLyricIndex => _currentLyricIndex;
  bool get isFetchingLyrics => _isFetchingLyrics;

  int get sliderValue {
    if (_duration.inMilliseconds > 0) {
      final val = (_position.inMilliseconds * 1000 ~/ _duration.inMilliseconds);
      return val > 1000 ? 1000 : (val < 0 ? 0 : val);
    }
    return 0;
  }

  // Added buffered value for UI
  int get bufferedSliderValue {
    if (_duration.inMilliseconds > 0) {
      final val =
          (_bufferedPosition.inMilliseconds * 1000 ~/ _duration.inMilliseconds);
      return val > 1000 ? 1000 : (val < 0 ? 0 : val);
    }
    return 0;
  }

  final HistoryService _historyService;
  final LastFmService _lastFmService;
  bool _hasScrobbled = false;

  AudioPlayerService({
    required AppAudioHandler handler,
    required DabApiService dabApiService,
    required HistoryService historyService,
    required LastFmService lastFmService,
  })  : _handler = handler,
        _dabApiService = dabApiService,
        _historyService = historyService,
        _lastFmService = lastFmService {
    _init();
  }

  void _init() {
    // Always start ticker for robust polling on Windows
    _startTicker();

    // Listen to Playback State
    _handler.playbackState.listen((state) {
      _position = state.position;
      _bufferedPosition = state.bufferedPosition; // Added

      switch (state.repeatMode) {
        case AudioServiceRepeatMode.none:
          _loopMode = LoopMode.off;
          break;
        case AudioServiceRepeatMode.one:
          _loopMode = LoopMode.one;
          break;
        case AudioServiceRepeatMode.all:
          _loopMode = LoopMode.all;
          break;
        default:
          _loopMode = LoopMode.off;
      }

      _shuffleEnabled = (state.shuffleMode == AudioServiceShuffleMode.all);

      if (state.queueIndex != null) {
        _currentIndex = state.queueIndex!;
      }

      notifyListeners();
    });

    // Listen to MediaItem (Current Track)
    _handler.mediaItem.listen((item) {
      if (item != null) {
        if (item.extras != null && item.extras!.containsKey('track')) {
          _currentTrack =
              Track.fromJson(Map<String, dynamic>.from(item.extras!['track']));
        } else {
          _currentTrack = Track(
              id: item.id,
              title: item.title,
              artist: item.artist ?? 'Unknown',
              albumCover: item.artUri?.toString(),
              duration: item.duration?.inSeconds);
        }
        _duration = item.duration ?? Duration.zero;

        // New Track Logic
        if (_currentTrack != null) {
          _fetchLyrics(_currentTrack!);
          _historyService.addPlayed(_currentTrack!);

          // Last.fm: Update Now Playing & Reset Scrobble
          _hasScrobbled = false;
          _lastFmService.updateNowPlaying(_currentTrack!);
        }
        notifyListeners();
      }
    });

    // Listen to Queue
    _handler.queue.listen((items) {
      _queue = items.map((item) {
        if (item.extras != null && item.extras!.containsKey('track')) {
          return Track.fromJson(
              Map<String, dynamic>.from(item.extras!['track']));
        }
        return Track(
            id: item.id, title: item.title, artist: item.artist ?? 'Unknown');
      }).toList();
      notifyListeners();
    });

    AudioService.position.listen((pos) {
      _position = pos;
      _updateCurrentLyric();

      // Last.fm Scrobble Logic
      // Rule: Played for 50% OR 4 minutes (240 seconds)
      if (!_hasScrobbled && _currentTrack != null && _duration.inSeconds > 30) {
        final thresholdSeconds =
            (_duration.inSeconds / 2).clamp(0, 240).toDouble();

        if (pos.inSeconds >= thresholdSeconds) {
          _hasScrobbled = true;
          _lastFmService.scrobble(_currentTrack!, timestamp: DateTime.now());
          print('Scrobble triggered for: ${_currentTrack!.title}');
        }
      }

      notifyListeners();
    });
  }

  Timer? _ticker;

  void _startTicker() {
    _ticker?.cancel();
    // Poll frequently (200ms) to catch play state changes and position
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      try {
        final pos = _handler.currentPosition;
        final playing = _handler.isPlayerPlaying;

        bool notify = false;

        if (pos != _position) {
          _position = pos;
          _updateCurrentLyric();
          notify = true;
        }

        if (playing != _isPlaying) {
          _isPlaying = playing;
          notify = true;
        }

        if (notify) {
          notifyListeners();
        }
      } catch (e) {
        // Suppress errors
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // Controls

  Future<void> playTrack(Track track) async {
    await _handler.setRequestQueue([track]);
  }

  Future<void> playFromQueue(int index) async {
    // We can invoke custom action or skip
    await _handler.skipToQueueItem(index);
  }

  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    await _handler.setRequestQueue(tracks, pendingIndex: startIndex);
  }

  void addToQueue(Track track) {
    // Append to current queue
    // Since _queue is a getter, we modify handler
    // But BaseAudioHandler queue is a stream.
    // We invoke 'addQueueItem'
    // We need to pass MediaItem
    // Implementation detail for AppAudioHandler.addQueueItem
    // For now, simpler:
    final currentQ = List<Track>.from(_queue);
    currentQ.add(track);
    _handler.setRequestQueue(currentQ,
        pendingIndex: _currentIndex); // Inefficient but works
  }

  // ... (Other queue methods similarly simplified or proxied)
  void clearQueue() {
    _handler.stop();
    _handler.setRequestQueue([]);
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> pause() => _handler.pause();
  Future<void> resume() => _handler.play();
  Future<void> stop() => _handler.stop();

  Future<void> seekToSlider(int value) async {
    if (_duration.inMilliseconds > 0) {
      final position = Duration(
          milliseconds: (value / 1000 * _duration.inMilliseconds).round());
      await _handler.seek(position);
    }
  }

  Future<void> seekTo(Duration position) => _handler.seek(position);

  Future<void> nextTrack() => _handler.skipToNext();
  Future<void> previousTrack() => _handler.skipToPrevious();

  Future<void> toggleShuffle() async {
    final newMode = _shuffleEnabled
        ? AudioServiceShuffleMode.none
        : AudioServiceShuffleMode.all;
    await _handler.setShuffleMode(newMode);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _handler.setVolume(volume);
    notifyListeners();
  }

  Future<void> playSingleTrack(Track track) async {
    await playTrack(track);
  }

  Future<void> playNext(Track track) async {
    await _handler.insertNext(track);
  }

  Future<void> removeFromQueue(int index) async {
    await _handler.removeFromQueue(index);
  }

  // Previous methods...
  Future<void> toggleLoop() async {
    var newMode = AudioServiceRepeatMode.none;
    switch (_loopMode) {
      case LoopMode.off:
        newMode = AudioServiceRepeatMode.all;
        break; // Toggle sequence: Off -> All -> One
      case LoopMode.all:
        newMode = AudioServiceRepeatMode.one;
        break;
      case LoopMode.one:
        newMode = AudioServiceRepeatMode.none;
        break;
    }
    await _handler.setRepeatMode(newMode);
  }

  // Lyrics Logic (Kept here as it's UI/API specific, not core player)
  Future<void> _fetchLyrics(Track track) async {
    _isFetchingLyrics = true;
    _lyrics = [];
    _currentLyricIndex = -1;
    notifyListeners();

    try {
      final lrcText = await _dabApiService.getLyrics(track.artist, track.title);
      if (lrcText != null) {
        _lyrics = _parseLrc(lrcText);
      } else {
        _lyrics = [
          LyricLine(timestamp: Duration.zero, text: 'Lyrics not available.')
        ];
      }
    } catch (e) {
      print('[Player] Lyrics fetch error: $e');
      _lyrics = [
        LyricLine(timestamp: Duration.zero, text: 'Failed to load lyrics.')
      ];
    }

    _isFetchingLyrics = false;
    notifyListeners();
  }

  List<LyricLine> _parseLrc(String lrcText) {
    // Same parsing logic...
    final List<LyricLine> result = [];
    final pattern = RegExp(r'\[(\d+):(\d+\.?\d*)\](.*)');

    for (final line in lrcText.split('\n')) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = double.parse(match.group(2)!);
        final text = match.group(3)!.trim();

        final timestamp = Duration(
          minutes: minutes,
          milliseconds: (seconds * 1000).round(),
        );

        result.add(LyricLine(timestamp: timestamp, text: text));
      }
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  void _updateCurrentLyric() {
    if (_lyrics.isEmpty) return;
    int newIndex = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      // Small offset for better sync visual
      if (_position >= _lyrics[i].timestamp) {
        newIndex = i;
      } else {
        break;
      }
    }
    if (newIndex != _currentLyricIndex) {
      _currentLyricIndex = newIndex;
      // notifyListeners() is called in position stream listener
    }
  }

  Future<void> seekToLyric(int index) async {
    if (index >= 0 && index < _lyrics.length) {
      await seekTo(_lyrics[index].timestamp);
    }
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}

enum LoopMode { off, all, one }
