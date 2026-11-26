import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:async';

import '../models/models.dart';
import 'addon_service.dart';
import 'audio_handler.dart';
import 'history_service.dart';
import 'last_fm_service.dart';

import 'discord_rpc_service.dart';

class AudioPlayerService with ChangeNotifier {
  final AppAudioHandler _handler;
  final AddonService _addonService;

  // Local state mirrored from Handler
  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero; // Added

  /// True from the moment the track changes until the player reports the new
  /// track as ready. The new track's length is known immediately (from its
  /// metadata), but the player's position still belongs to the old track, so it
  /// is ignored until then. Otherwise the progress bar jumps (2:00 of the old
  /// song shows as 67% of a 3:00 song) and then falls back to zero.
  bool _loadingNewTrack = false;
  double _volume = 0.8;
  bool _isBuffering = false;

  List<Track> _queue = [];
  int _currentIndex = -1;

  // Autoplay / radio: where the autoplay section of the queue starts, the song
  // it follows, and whether the user started a radio from a song.
  int? _autoplayStartIndex;
  Track? _autoplaySeed;
  Track? _radioSeed;

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

  /// Index in [queue] of the first track autoplay added, or null if none.
  int? get autoplayStartIndex => _autoplayStartIndex;

  /// The song autoplay is following (the last one the user chose).
  Track? get autoplaySeed => _autoplaySeed;

  /// The song a radio was started from, or null when no radio is active (the
  /// handler ends a radio by itself, e.g. when the recommendation source is
  /// switched off).
  Track? get radioSeed => _handler.isRadioActive ? _radioSeed : null;
  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition; // Added
  bool get isBuffering => _isBuffering;
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
  final DiscordRpcService _discordRpcService; // Discord
  bool _hasScrobbled = false;

  AudioPlayerService({
    required AppAudioHandler handler,
    required AddonService addonService,
    required HistoryService historyService,
    required LastFmService lastFmService,
    required DiscordRpcService discordRpcService,
  })  : _handler = handler,
        _addonService = addonService,
        _historyService = historyService,
        _lastFmService = lastFmService,
        _discordRpcService = discordRpcService {
    _init();
  }

  void _init() {
    // Init Audio Effects with the underlying player
    _lastFmService.init(); // Last.fm init

    // Pass the player from handlers to effects service
    // We access AudioEffectsService via context usually, but here strict injection is better.
    // However, AudioPlayerService doesn't have AudioEffectsService injected in constructor.
    // We should probably rely on main.dart to call init(), OR add it to constructor.
    // Let's assume we need to update constructor.
    // For now, let's keep it simple: Main.dart calls audioEffectsService.init(audioHandler.player)

    // Initialize Discord RPC if enabled

    // Listen to Playback State
    _handler.playbackState.listen((state) {
      if (state.processingState == AudioProcessingState.ready ||
          state.processingState == AudioProcessingState.idle) {
        _loadingNewTrack = false; // the new track is up (or nothing is loading)
      }
      _position = _loadingNewTrack ? Duration.zero : state.position;
      _bufferedPosition =
          _loadingNewTrack ? Duration.zero : state.bufferedPosition;
      _isBuffering = state.processingState == AudioProcessingState.buffering || 
                     state.processingState == AudioProcessingState.loading;
      _updateCurrentLyric(); // Keep lyrics in sync with position

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

      if (_isPlaying != state.playing) {
        _isPlaying = state.playing;
        _updateDiscordPresence(debounced: true); // Update Discord on Play/Pause
      }

      notifyListeners();
    });

    // Listen to MediaItem (Current Track)
    _handler.mediaItem.listen((item) {
      if (item != null) {
        final previousId = _currentTrack?.id;
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
        // A different track starts from the beginning: drop the old track's
        // position so the progress bar doesn't jump while the new one loads.
        if (_currentTrack?.id != previousId) {
          _loadingNewTrack = true;
          _position = Duration.zero;
          _bufferedPosition = Duration.zero;
        }

        // New Track Logic
        if (_currentTrack != null) {
          _fetchLyrics(_currentTrack!);
          _historyService.addPlayed(_currentTrack!);

          // Last.fm: Update Now Playing & Reset Scrobble
          _hasScrobbled = false;
          _lastFmService.updateNowPlaying(_currentTrack!);
          _updateDiscordPresence(debounced: true);
        }
      } else {
        _currentTrack = null;
        _loadingNewTrack = false;
        _duration = Duration.zero;
        _position = Duration.zero;
        _bufferedPosition = Duration.zero;
      }
      notifyListeners();
    });

    // Listen to Queue
    _handler.queue.listen((items) {
      _autoplayStartIndex = null;
      _queue = [
        for (var i = 0; i < items.length; i++)
          () {
            final item = items[i];
            // The handler flags tracks that autoplay added.
            if (_autoplayStartIndex == null &&
                item.extras?['autoplay'] == true) {
              _autoplayStartIndex = i;
            }
            if (item.extras != null && item.extras!.containsKey('track')) {
              return Track.fromJson(
                  Map<String, dynamic>.from(item.extras!['track']));
            }
            return Track(
                id: item.id,
                title: item.title,
                artist: item.artist ?? 'Unknown');
          }(),
      ];
      notifyListeners();
    });

    // Throttle position updates to 200ms to reduce bridge pressure on Windows
    DateTime _lastNotify = DateTime.now();
    AudioService.position.listen((pos) {
      _position = _loadingNewTrack ? Duration.zero : pos;
      _updateCurrentLyric();

      // Last.fm Scrobble Logic
      if (!_hasScrobbled && _currentTrack != null && _duration.inSeconds > 30) {
        final thresholdSeconds = (_duration.inSeconds / 2).clamp(0, 240).toDouble();
        if (pos.inSeconds >= thresholdSeconds) {
          _hasScrobbled = true;
          _lastFmService.scrobble(_currentTrack!, timestamp: DateTime.now());
        }
      }

      if (DateTime.now().difference(_lastNotify).inMilliseconds > 200) {
        _lastNotify = DateTime.now();
        notifyListeners();
      }
    });

    // Optimization: Listen to shuffle/repeat changes directly or via streams.

    // Update Discord on track changes, state changes, or seeks.
  }

  // Logic refactored into stream listeners for performance.

  void _stopTicker() {
    // Ticker removed
  }

  // Controls

  Future<void> playTrack(Track track) async {
    _radioSeed = null;
    _autoplaySeed = track;
    await _handler.setRequestQueue([track]);
  }

  /// Plays [seed] and keeps adding similar songs after it (a "song radio").
  /// Returns how many songs are queued after it; 0 means none were found.
  Future<int> startRadio(Track seed) async {
    _radioSeed = seed;
    _autoplaySeed = seed;
    notifyListeners();
    final queued = await _handler.startRadio(seed);
    if (queued == 0) {
      // Nothing found: don't leave the radio showing as active.
      _radioSeed = null;
      _handler.stopRadio();
      notifyListeners();
    }
    return queued;
  }

  /// Turns the radio off. What is already in the queue stays.
  void stopRadio() {
    _radioSeed = null;
    _handler.stopRadio();
    notifyListeners();
  }

  Future<void> playFromQueue(int index) async {
    // We can invoke custom action or skip
    await _handler.skipToQueueItem(index);
  }

  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    _radioSeed = null;
    if (startIndex >= 0 && startIndex < tracks.length) {
      _autoplaySeed = tracks[startIndex];
    }
    await _handler.setRequestQueue(tracks, pendingIndex: startIndex);
  }

  /// Plays [tracks] in a random order and leaves shuffle switched on.
  Future<void> playAllShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final order = List.of(tracks)..shuffle();
    await playAll(order);
    if (!_shuffleEnabled) await toggleShuffle();
  }

  Future<void> addToQueue(Track track) async {
    // On an empty queue this starts a new one.
    if (_queue.isEmpty) {
      _radioSeed = null;
      _autoplaySeed = track;
    }
    await _handler.addTrackToQueue(track);
  }

  /// "Clear queue": the song that is playing stays and keeps playing; every
  /// other track is removed.
  void clearQueueKeepCurrent() => _handler.clearQueueKeepCurrent();

  // ... (Other queue methods similarly simplified or proxied)

  /// Stops playback and empties the queue (used when the mini player is
  /// dismissed).
  void clearQueue() {
    _radioSeed = null;
    _autoplaySeed = null;
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
      _updateDiscordPresence();
    }
  }

  Future<void> seekTo(Duration position) async {
    await _handler.seek(position);
    _updateDiscordPresence();
  }

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
    // On an empty queue this starts a new one.
    if (_queue.isEmpty) {
      _radioSeed = null;
      _autoplaySeed = track;
    }
    await _handler.insertNext(track);
  }

  Future<void> removeFromQueue(int index) async {
    await _handler.removeFromQueue(index);
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    await _handler.reorderQueue(oldIndex, newIndex);
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
      final lrcText = await _addonService.getLyrics(
        track.artist, 
        track.title, 
        album: track.albumTitle,
        duration: track.duration,
        addonId: track.addonId ?? 'net.lrclib',


      );

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

  Timer? _discordDebounceTimer;

  void _updateDiscordPresence({bool debounced = false}) {
    if (debounced) {
      _discordDebounceTimer?.cancel();
      _discordDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        _performDiscordUpdate();
      });
    } else {
      _performDiscordUpdate();
    }
  }

  void _performDiscordUpdate() {
    if (_currentTrack == null) {
      _discordRpcService.clearPresence();
      return;
    }
    try {
      _discordRpcService.updatePresence(
        track: _currentTrack!,
        isPlaying: _isPlaying,
        position: _position,
        duration: _duration,
      );
    } catch (e) {
      print('[DiscordRPC] Update error: $e');
    }
  }

  @override
  void dispose() {
    _discordDebounceTimer?.cancel();
    _stopTicker();
    _discordRpcService.dispose();
    super.dispose();
  }
}

enum LoopMode { off, all, one }
