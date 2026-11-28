import 'dart:async';
import 'package:flutter/foundation.dart'; // kIsWeb
import '../utils/platform_helper.dart';

import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import '../models/addon_models.dart';
import '../recommendations/track_matching.dart';
import 'download_manager_service.dart';
import 'addon_service.dart';
import 'settings_service.dart';
import 'dash_service.dart';
import 'dash_native_parser.dart';
import 'dash_local_proxy_server.dart';
import 'native_player_config.dart';
import 'stream_cache_service.dart';
import 'queue_model.dart';

/// Finds tracks similar to [seeds] (songs the user chose) that are not in
/// [queue] yet. Provided by the recommendations layer; null disables autoplay.
typedef AutoplaySupplier = Future<List<Track>> Function(
    List<Track> seeds, List<Track> queue);

/// The AudioHandler manages the audio player and the playlist.
/// It exposes the standard AudioService interface to the UI (and system).
/// Uses just_audio Player directly.
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayer? _playerInstance;
  AudioPlayer get _player {
    if (_playerInstance == null) {
      _playerInstance = AudioPlayer();
      _setupPlayerListeners();
    }
    return _playerInstance!;
  }
  final DownloadManagerService _downloadManager;
  final AddonService _addonService;
  final SettingsService _settingsService;
  final StreamCacheService _streamCache;

  // Cache download of the track that is currently streaming (if any)
  CacheHandle? _cacheHandle;

  // Internal Queue State (tracks, current index, autoplay section, shuffle)
  final QueueModel _q = QueueModel();

  // Autoplay: appends similar songs when the queue is about to run out.
  AutoplaySupplier? autoplaySupplier;
  Future<void>? _pendingAutoplay;
  int _queueGeneration = 0; // bumped per new queue so stale batches are dropped
  final List<Track> _userSeeds = []; // last songs the user picked themselves
  int _batchCount = 0; // batches requested for this queue (rotates the seeds)
  bool _radioActive = false; // radio keeps going even with autoplay switched off
  DateTime? _autoplayRetryAfter; // set when a batch found nothing: back off
  bool _lastAutoplaySetting = true;
  bool _isAdvancing = false;

  int _failureStreak = 0; // unplayable tracks skipped in a row
  static const _maxFailureSkips = 3;

  static const _autoplayBackoff = Duration(seconds: 20);
  static const _autoplayWait = Duration(seconds: 40);

  bool _isDashActive = false;
  Timer? _positionTimer;
  int _lastRequestId = 0;
  bool _isSwitchingTrack = false;
  AddonStreamResult? _currentStreamResult;

  AddonStreamResult? get currentStreamResult => _currentStreamResult;
  
  // Prefetch Cache
  final Map<String, AddonStreamResult> _prefetchCache = {};
  ProxyCacheHandle? _prefetchedHandle;
  String? _prefetchedHandleTrackId;
  bool _isPrefetching = false;

  final List<StreamSubscription> _subscriptions = [];

  AppAudioHandler({
    required DownloadManagerService downloadManager,
    required AddonService addonService,
    required SettingsService settingsService,
    required StreamCacheService streamCache,
  })  : _downloadManager = downloadManager,
        _addonService = addonService,
        _settingsService = settingsService,
        _streamCache = streamCache {
    _init();
    _lastAutoplaySetting = _settingsService.autoplayActive;
    _settingsService.addListener(_onSettingsChanged);
  }

  /// Switching autoplay on while something plays starts looking right away;
  /// switching it off drops a batch that is still on its way. Turning the
  /// recommendation source off stops a running radio too.
  void _onSettingsChanged() {
    if (!_settingsService.recSourceEnabled && _radioActive) {
      _radioActive = false;
      _dropAutoplayTracks();
    }
    final now = _settingsService.autoplayActive;
    if (now == _lastAutoplaySetting) return;
    _lastAutoplaySetting = now;
    if (now) {
      _autoplayRetryAfter = null;
      _maybeTopUp();
    } else if (!_radioActive) {
      _dropAutoplayTracks();
    }
  }

  /// Autoplay is off: forget a batch that is on its way and take the autoplay
  /// tracks that have not played yet out of the queue.
  void _dropAutoplayTracks() {
    _queueGeneration++;
    _pendingAutoplay = null;
    if (_q.removeUpcomingAutoplay() > 0) _broadcastQueue();
  }

  /// Tells the stream cache how far the current track got, so a track that
  /// was skipped within seconds is not left behind in the cache.
  void _releaseCacheHandle() {
    final handle = _cacheHandle;
    _cacheHandle = null;
    handle?.release(_playerInstance?.position ?? Duration.zero);
    _streamCache.clearPlaying();
  }

  // Expose explicit state for UI polling
  Duration get currentPosition {
    if (_isDashActive) return playbackState.value.position;
    return _playerInstance?.position ?? Duration.zero;
  }

  bool get isPlayerPlaying {
    if (_isDashActive) return playbackState.value.playing;
    return _playerInstance?.playing ?? false;
  }

  Future<void> _init() async {
    if (!kIsWeb) {
      _downloadManager.cleanupTemporaryFiles();
    }
  }

  void _setupPlayerListeners() {
    // Clear existing subscriptions
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    DateTime lastPositionBroadcast = DateTime.now();
    DateTime lastBufferedBroadcast = DateTime.now();

    // Subscribe to media_kit streams and push PlaybackState to audio_service
    _subscriptions.addAll([
      _playerInstance!.playingStream.listen((_) => _broadcastState()),
      _playerInstance!.positionStream.listen((pos) {
        if (DateTime.now().difference(lastPositionBroadcast).inMilliseconds > 500) {
          _broadcastState();
          lastPositionBroadcast = DateTime.now();
        }
        _checkPrefetch(pos);
      }),
      _playerInstance!.bufferedPositionStream.listen((_) {
        if (DateTime.now().difference(lastBufferedBroadcast).inMilliseconds > 500) {
          _broadcastState();
          lastBufferedBroadcast = DateTime.now();
        }
      }),
      _playerInstance!.playerStateStream.listen((state) {
        // Note: _isSwitchingTrack is NOT cleared here. A late "ready" from the
        // previous song (e.g. a buffering/ready flap right after Next) would
        // end the loading phase too early and put the old position back on
        // screen. _playQueueItem clears it once the new source is loaded.
        _broadcastState();
        if (state.processingState == ProcessingState.completed) {
          _handleTrackCompletion();
        }
      }),
      _playerInstance!.durationStream.listen((duration) {
        if (duration != null) {
          _cacheHandle?.reportDuration(duration);
          final current = mediaItem.value;
          if (current != null &&
              duration > Duration.zero &&
              (current.duration == null || current.duration == Duration.zero)) {
            mediaItem.add(current.copyWith(duration: duration));
          }
        }
        _broadcastState();
      }),
    ]);

    if (kIsWeb) {
      _subscriptions.add(_playerInstance!.playingStream.listen((playing) {
        if (playing) _startPositionPolling();
        else _stopPositionPolling();
      }));
    }
  }

  /// Broadcasts current player state to audio_service (SMTC / Bluetooth / UI)
  void _checkPrefetch(Duration position) async {
    if (!_settingsService.enablePrefetch) return;
    if (_player.duration == null || _player.duration!.inSeconds == 0) return;
    if (_q.isEmpty || _q.currentIndex < 0 || !_q.hasNext) return;
    if (_isPrefetching) return;

    final timeLeft = _player.duration! - position;
    final triggerSeconds = _settingsService.prefetchDuration > 0
        ? _settingsService.prefetchDuration
        : 5;
    if (timeLeft.inSeconds <= triggerSeconds) {
      final nextTrack = _q.tracks[_q.currentIndex + 1];
      if (_prefetchCache.containsKey(nextTrack.id)) return;
      if (_downloadManager.isDownloaded(nextTrack.id)) return; // No need to prefetch local

      _isPrefetching = true;
      try {
        print('[AudioHandler] Prefetching next track: ${nextTrack.title}');
        final streamResult = await _addonService.getStreamResult(
          nextTrack.addonTrackId ?? nextTrack.id,
          addonId: nextTrack.addonId,
          isrc: nextTrack.isrc,
          title: nextTrack.title,
          artist: nextTrack.artist,
        );
        if (streamResult != null && streamResult.url.isNotEmpty) {
          _prefetchCache[nextTrack.id] = streamResult;

          // Pre-fetch audio bytes in the background so transition is gapless.
          final fmt = streamResult.format?.toLowerCase();
          final man = streamResult.manifest?.toLowerCase();
          final isDash = man == 'dash' ||
              fmt == 'dash' ||
              streamResult.url.contains('<MPD') ||
              streamResult.url.contains('.mpd');
          if (!kIsWeb && !isDash) {
            if (_streamCache.isEnabled &&
                _streamCache.lookup(nextTrack) == null) {
              _prefetchedHandle?.cancel();
              _prefetchedHandle = null;
              _prefetchedHandleTrackId = null;
              final handle = await _streamCache.open(
                nextTrack,
                streamResult.url,
                format: fmt,
                quality: streamResult.quality,
                headers: const {'User-Agent': 'BeatBoss/1.0 (Flutter)'},
              );
              if (handle != null) {
                _prefetchedHandle = handle;
                _prefetchedHandleTrackId = nextTrack.id;
              }
            } else {
              // Warm TCP/TLS + CDN edge cache with a small range fetch.
              unawaited(() async {
                try {
                  final client = HttpClient();
                  final req = await client.getUrl(Uri.parse(streamResult.url));
                  req.headers.set('User-Agent', 'BeatBoss/1.0 (Flutter)');
                  req.headers.set('Range', 'bytes=0-262143');
                  final resp = await req.close();
                  await resp.drain<void>();
                  client.close();
                } catch (_) {}
              }());
            }
          }
          print('[AudioHandler] Prefetch complete for: ${nextTrack.title}');
        }
      } catch (e) {
        print('[AudioHandler] Prefetch failed: $e');
      } finally {
        _isPrefetching = false;
      }
    }
  }

  void _broadcastState() {
    final isPlaying = _playerInstance?.playing ?? false;
    // While a new track loads, report it from the start: the old track's
    // position would otherwise carry over and the progress bar would jump.
    final position = _isSwitchingTrack
        ? Duration.zero
        : (_playerInstance?.position ?? Duration.zero);
    final buffered = _isSwitchingTrack
        ? Duration.zero
        : (_playerInstance?.bufferedPosition ?? Duration.zero);
    final isBuffering = _playerInstance?.playerState.processingState == ProcessingState.buffering;
    final isLoading = _playerInstance?.playerState.processingState == ProcessingState.loading;
    final isCompleted = _playerInstance?.playerState.processingState == ProcessingState.completed;

    AudioProcessingState processingState;
    if (_isSwitchingTrack) {
      processingState = AudioProcessingState.loading;
    } else if (isCompleted) {
      processingState = AudioProcessingState.completed;
    } else if (isBuffering) {
      processingState = AudioProcessingState.buffering;
    } else if (isLoading) {
      processingState = AudioProcessingState.loading;
    } else if (_q.currentIndex < 0) {
      processingState = AudioProcessingState.idle;
    } else {
      processingState = AudioProcessingState.ready;
    }

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: processingState,
      playing: isPlaying,
      updatePosition: position,
      bufferedPosition: buffered,
      // Speed 0 stops the position from being extrapolated while loading.
      speed: _isSwitchingTrack ? 0.0 : (_playerInstance?.speed ?? 1.0),
      queueIndex: _q.currentIndex,
      repeatMode: _mapLoopModeToRepeatMode(_playerInstance?.loopMode ?? LoopMode.off),
      shuffleMode: (_playerInstance?.shuffleModeEnabled ?? false)
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  AudioServiceRepeatMode _mapLoopModeToRepeatMode(LoopMode mode) {
    switch (mode) {
      case LoopMode.off: return AudioServiceRepeatMode.none;
      case LoopMode.one: return AudioServiceRepeatMode.one;
      case LoopMode.all: return AudioServiceRepeatMode.all;
    }
  }

  void _handleTrackCompletion() {
    if (_isSwitchingTrack || _isAdvancing) return;
    if (_player.loopMode == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    _isAdvancing = true;
    _advanceAfterCompletion().whenComplete(() => _isAdvancing = false);
  }

  Future<void> _advanceAfterCompletion() async {
    final requestId = _lastRequestId;

    // End of the queue: give autoplay a chance to supply more tracks first.
    if (!_q.hasNext && _player.loopMode != LoopMode.all) {
      await _ensureUpcoming();
      if (requestId != _lastRequestId) return; // the user moved on meanwhile
    }

    if (_q.hasNext) {
      _q.currentIndex++;
      _playQueueItem(_q.currentIndex);
    } else if (_player.loopMode == LoopMode.all) {
      _q.currentIndex = 0;
      _playQueueItem(0);
    } else {
      stop();
      _player.seek(Duration.zero);
      _q.clear();
      queue.add([]);
      mediaItem.add(null);
      _broadcastState();
    }
  }

  // ========== AUTOPLAY ==========

  /// A radio the user started always keeps going. Plain autoplay follows the
  /// setting and stays out of the way while repeat is on.
  bool get _autoplayAllowed =>
      autoplaySupplier != null &&
      _settingsService.recSourceEnabled && // "Off" switches radio off too
      (_radioActive ||
          (_settingsService.autoplaySimilar &&
              _player.loopMode == LoopMode.off));

  /// Whether a radio started by the user is running.
  bool get isRadioActive => _radioActive;

  /// Starts fetching similar songs when fewer than two tracks are left.
  /// Fire and forget: the batch is appended when it arrives, unless the user
  /// started a different queue in the meantime.
  void _maybeTopUp() {
    if (autoplaySupplier == null) {
      print('[Autoplay] not available: no supplier is wired up '
          '(after a code change, restart the app instead of hot reloading)');
      return;
    }
    if (!_autoplayAllowed || _pendingAutoplay != null) return;
    final retryAfter = _autoplayRetryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) return;
    if (_q.currentIndex < 0 || _q.upcomingCount >= 2 || _userSeeds.isEmpty) {
      return;
    }

    print('[Autoplay] looking for songs similar to '
        '"${_userSeeds.last.title}" (${_q.upcomingCount} left in the queue)');
    final generation = _queueGeneration;
    late final Future<void> pending;
    pending = autoplaySupplier!(_seedsForBatch(), List.of(_q.tracks))
        .then((tracks) {
      if (generation != _queueGeneration || !_autoplayAllowed) {
        print('[Autoplay] dropped a batch: the queue or repeat mode changed meanwhile');
        return;
      }
      final existing = {
        for (final t in _q.tracks) matchKey(t.artist, t.title),
      };
      final fresh = tracks
          .where((t) => existing.add(matchKey(t.artist, t.title)))
          .toList();
      if (fresh.isEmpty) {
        _autoplayRetryAfter = DateTime.now().add(_autoplayBackoff);
        print('[Autoplay] found no new playable similar songs');
        return;
      }
      _autoplayRetryAfter = null;
      _q.appendAutoplay(fresh);
      _broadcastQueue();
      print('[Autoplay] added ${fresh.length} tracks to the queue');
    }).catchError((Object e) {
      _autoplayRetryAfter = DateTime.now().add(_autoplayBackoff);
      print('[Autoplay] failed: $e');
    }).whenComplete(() {
      if (identical(_pendingAutoplay, pending)) _pendingAutoplay = null;
    });
    _pendingAutoplay = pending;
  }

  /// The seeds to build the next batch from, in the order to try them. The
  /// first batch of a queue follows the song the user just chose (newest
  /// first); later batches start from the next older one, so a long radio
  /// doesn't drift away from the songs the user picked.
  List<Track> _seedsForBatch() {
    final newestFirst = _userSeeds.reversed.toList();
    final shift = _batchCount++ % newestFirst.length;
    return [...newestFirst.skip(shift), ...newestFirst.take(shift)];
  }

  /// Waits for a batch that is on its way, but never longer than
  /// [_autoplayWait], so a stuck search can't freeze playback.
  Future<void> _awaitPendingAutoplay() async {
    final pending = _pendingAutoplay;
    if (pending == null) return;
    try {
      await pending.timeout(_autoplayWait);
    } on TimeoutException {
      print('[Autoplay] gave up waiting for similar songs');
    }
  }

  /// At the end of the queue, waits (if needed) for autoplay to add tracks.
  Future<void> _ensureUpcoming() async {
    if (_q.hasNext) return;
    _maybeTopUp();
    await _awaitPendingAutoplay();
  }

  void _broadcastQueue() {
    final tracks = _q.tracks;
    final start = _q.autoplayStart;
    queue.add([
      for (var i = 0; i < tracks.length; i++)
        _toMediaItem(
          tracks[i],
          autoplay: start != null && i >= start,
          queueEntryId: i < _q.ids.length ? _q.ids[i] : null,
        ),
    ]);
  }

  // ========== ACTIONS ==========

  @override
  Future<void> play() async {
    if (_isDashActive && kIsWeb) {
      DashService.resume();
      playbackState.add(playbackState.value.copyWith(playing: true, speed: 1.0));
      return;
    }
    _player.play();
  }

  @override
  Future<void> pause() async {
    if (_isDashActive && kIsWeb) {
      DashService.pause();
      playbackState.add(playbackState.value.copyWith(playing: false, speed: 0.0));
      return;
    }
    _player.pause();
  }

  @override
  Future<void> stop() async {
    _lastRequestId++;
    _queueGeneration++;
    _pendingAutoplay = null;
    _isSwitchingTrack = false; // nothing is loading any more
    _releaseCacheHandle();
    if (kIsWeb) {
      DashService.stop();
      _isDashActive = false;
      _stopPositionPolling();
    }
    if (!kIsWeb && (PlatformHelper.isWindows || PlatformHelper.isLinux)) {
      DashLocalProxyServer.stop();
    }
    await _player.stop();
    _stopPositionPolling();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isDashActive && kIsWeb) {
      DashService.seek(position.inSeconds.toDouble());
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
      return;
    }
    return _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_q.isEmpty) return;
    final requestId = _lastRequestId;
    // On the last track, wait for autoplay to supply more. Ignore extra taps
    // while waiting so they don't skip twice.
    if (!_q.hasNext && _player.loopMode != LoopMode.all) {
      if (_isAdvancing) return;
      _isAdvancing = true;
      try {
        await _ensureUpcoming();
      } finally {
        _isAdvancing = false;
      }
      if (requestId != _lastRequestId || _q.isEmpty) return;
    }
    int nextIndex = _q.currentIndex + 1;
    if (_player.loopMode == LoopMode.all && nextIndex >= _q.length) {
      nextIndex = 0;
    }
    _failureStreak = 0;
    if (nextIndex < _q.length) await _playQueueItem(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_q.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }
    int prevIndex = _q.currentIndex - 1;
    if (_player.loopMode == LoopMode.all && prevIndex < 0) {
      prevIndex = _q.length - 1;
    }
    _failureStreak = 0;
    if (prevIndex >= 0) await _playQueueItem(prevIndex, direction: -1);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
        break;
      default:
        await _player.setLoopMode(LoopMode.off);
    }
    _broadcastState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    // The player only ever holds one source, so shuffling is done on our own
    // queue: the upcoming tracks are reordered, played ones stay put.
    if (enabled) {
      _q.shuffleUpcoming();
    } else {
      _q.unshuffle();
    }
    await _player.setShuffleModeEnabled(enabled);
    _broadcastQueue();
    _broadcastState();
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {}

  /// Starts a new queue. With [radio], autoplay keeps adding similar songs
  /// even when the autoplay setting is off, and only [tracks][pendingIndex]
  /// is used as the seed.
  Future<void> setRequestQueue(List<Track> tracks,
      {int pendingIndex = 0, bool radio = false}) async {
    // A new queue invalidates any autoplay batch still on its way.
    _queueGeneration++;
    _pendingAutoplay = null;
    _autoplayRetryAfter = null;
    _failureStreak = 0;
    _batchCount = 0;
    _radioActive = radio;

    if (tracks.isNotEmpty && pendingIndex >= 0 && pendingIndex < tracks.length) {
      final seed = tracks[pendingIndex];
      if (radio) _userSeeds.clear();
      _userSeeds.add(seed);
      while (_userSeeds.length > 3) {
        _userSeeds.removeAt(0);
      }
    }

    _q.replace(
      tracks,
      index: pendingIndex,
      shuffled: _playerInstance?.shuffleModeEnabled ?? false,
    );
    _broadcastQueue();
    if (_q.isNotEmpty && _q.currentIndex >= 0 && _q.currentIndex < _q.length) {
      await _playQueueItem(_q.currentIndex);
    }
  }

  /// Plays [seed] and keeps adding similar songs after it. If [seed] is the
  /// track already playing, it keeps playing and only the upcoming queue is
  /// replaced by the radio.
  ///
  /// Returns how many tracks are queued after the current one once the first
  /// batch has arrived (0 means no similar songs were found).
  Future<int> startRadio(Track seed) async {
    final current = _q.current;
    if (current == null || current.id != seed.id) {
      await setRequestQueue([seed], radio: true);
    } else {
      _queueGeneration++;
      _pendingAutoplay = null;
      _autoplayRetryAfter = null;
      _batchCount = 0;
      _radioActive = true;
      _userSeeds
        ..clear()
        ..add(current);
      _q.removeUpcoming();
      _broadcastQueue();
      _maybeTopUp();
    }
    await _awaitPendingAutoplay();
    return _q.upcomingCount;
  }

  /// Stops a radio from adding more songs. What is already queued stays.
  void stopRadio() {
    _radioActive = false;
    // With plain autoplay off too, nothing should keep feeding the queue, so
    // the radio's songs that haven't played yet go as well.
    if (!_settingsService.autoplayActive) _dropAutoplayTracks();
  }

  /// "Clear queue": keeps the song that is playing and removes everything
  /// else. Playback is not interrupted.
  void clearQueueKeepCurrent() {
    _queueGeneration++; // a batch on its way must not refill the queue
    _pendingAutoplay = null;
    _q.keepOnlyCurrent();
    _broadcastQueue();
    _broadcastState(); // the current index changed
  }

  /// Loads and plays the track at [index]. [direction] (+1 next, -1 previous)
  /// says which way to move on if that track turns out to be unplayable.
  Future<void> _playQueueItem(int index,
      {Duration? startPosition,
      bool skipCache = false,
      int direction = 1}) async {
    if (index < 0 || index >= _q.length) return;

    _q.currentIndex = index;
    final track = _q.tracks[index];
    final requestId = ++_lastRequestId;
    _isSwitchingTrack = true;
    _currentStreamResult = null;
    _releaseCacheHandle();

    // Instantly update UI metadata and set to buffering while we fetch the stream
    final item = _toMediaItem(track);
    mediaItem.add(item);
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.buffering,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 0.0,
      queueIndex: _q.currentIndex,
    ));

    // Running low on tracks? Start looking for similar songs now, so they are
    // ready well before this track ends.
    _maybeTopUp();

    // "Idle Reset" pattern for DASH thread safety:
    // Instead of disposing/recreating the player (which leaves zombie threads in
    // ntdll.dll), we stop + set idle + wait for the OS to reap the DASH demuxer
    // worker threads before handing it a new source.
    if (kIsWeb) {
      DashService.stop();
    }
    try {
      await _player.stop();
      // Crucial 500ms delay: allows ntdll.dll to fully reap the DASH segment-
      // fetching threads and release WASAPI handles + file cache locks.
      if (!kIsWeb && _isDashActive) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      print('[AudioHandler] Stop error (ignored): $e');
    }

    if (requestId != _lastRequestId) return;
    _isDashActive = false;

    try {
      final isDownloaded = _downloadManager.isDownloaded(track.id);
      final localPath = _downloadManager.getLocalPath(track.id);
      final bool useLocal = !kIsWeb && isDownloaded && localPath != null && PlatformHelper.fileExists(localPath);

      String? audioUrl;
      String? directUrl; // remote URL to fall back to if the cache proxy fails
      bool usedCache = false;

      // Order: downloaded file, then cached file, then stream (and cache it).
      final cachedPath =
          (useLocal || skipCache || kIsWeb) ? null : _streamCache.lookup(track);

      if (useLocal) {
        audioUrl = Uri.file(localPath).toString();
        print('[AudioHandler] Playing local file: $audioUrl');
      } else if (cachedPath != null) {
        audioUrl = Uri.file(cachedPath).toString();
        usedCache = true;
        print('[AudioHandler] Playing cached file: $audioUrl');
      } else {
        int retries = 0;
        while (retries < 2) {
          try {
            AddonStreamResult? streamResult;
            // Check cache first
            if (_prefetchCache.containsKey(track.id)) {
               streamResult = _prefetchCache.remove(track.id);
               audioUrl = streamResult?.url;
            } else {
               streamResult = await _addonService.getStreamResult(
                 track.addonTrackId ?? track.id,
                 addonId: track.addonId,
                 isrc: track.isrc,
                 title: track.title,
                 artist: track.artist,
               );
               audioUrl = streamResult?.url;
            }
            if (requestId != _lastRequestId) return;
            _currentStreamResult = streamResult;

            String? url = streamResult?.url;
            final format = streamResult?.format?.toLowerCase();
            final manifestType = streamResult?.manifest?.toLowerCase();
            if (url == null || url.trim().isEmpty) throw Exception('No stream URL found');

            // Native redirect resolution
            if (!kIsWeb &&
                url.startsWith('http') &&
                manifestType != 'dash' &&
                format != 'dash' &&
                !url.contains('.mpd')) {
              try {
                final client = HttpClient();
                final request = await client.headUrl(Uri.parse(url));
                request.followRedirects = true;
                final response = await request.close();
                if (response.redirects.isNotEmpty) {
                  url = response.redirects.last.location.toString();
                  print('[AudioHandler] Resolved redirect to: $url');
                }
              } catch (e) {
                print('[AudioHandler] Redirect resolution skipped/failed: $e');
              }
            }

            final String finalUrl = url!;
            final bool isDash = (manifestType == 'dash' ||
                format == 'dash' ||
                finalUrl.contains('<MPD') ||
                finalUrl.contains('.mpd'));

            if (isDash) {
              if (requestId != _lastRequestId) return;

              const String proxy = 'https://webdownloadproxy.thevolecitor.workers.dev/?url=';

              if (kIsWeb || PlatformHelper.isWindows || PlatformHelper.isLinux) {
                if (kIsWeb) {
                  final manifestUri = await DashService.getManifestUri(finalUrl, proxy: proxy, trackId: track.id);
                  DashService.init(manifestUri, proxy);
                  _isDashActive = true;
                  _isSwitchingTrack = false; // web DASH has no just_audio load
                  _startPositionPolling();

                  playbackState.add(playbackState.value.copyWith(
                    playing: true,
                    speed: 1.0,
                    processingState: AudioProcessingState.ready,
                    controls: [MediaControl.skipToPrevious, MediaControl.pause, MediaControl.stop, MediaControl.skipToNext],
                  ));
                  return;
                } else {
                  DashLocalProxyServer.stop();
                  final manifest = await DashNativeParser.parse(finalUrl);
                  final sink = skipCache
                      ? null
                      : _streamCache.openDashSink(track,
                          quality: streamResult?.quality);
                  if (requestId != _lastRequestId) {
                    sink?.cancel();
                    return;
                  }
                  _cacheHandle = sink;
                  audioUrl = await DashLocalProxyServer.start(
                    manifest,
                    proxyUrl: null, // As requested, do NOT use Cloudflare worker
                    getPosition: () => _player.position.inSeconds.toDouble(),
                    sink: sink,
                  );
                  break;
                }
              } else {
                audioUrl = finalUrl;
                break;
              }
            } else {
              if (kIsWeb) DashService.stop();
              audioUrl = finalUrl;
              if (!kIsWeb && !skipCache) {
                if (_prefetchedHandleTrackId == track.id &&
                    _prefetchedHandle != null) {
                  _cacheHandle = _prefetchedHandle;
                  directUrl = finalUrl;
                  audioUrl = _prefetchedHandle!.playbackUrl;
                  _prefetchedHandle = null;
                  _prefetchedHandleTrackId = null;
                  break;
                }
                // Route the stream through the local cache proxy; any failure
                // here just means this track plays uncached.
                try {
                  final handle = await _streamCache.open(
                    track,
                    finalUrl,
                    format: format,
                    quality: streamResult?.quality,
                    headers: const {'User-Agent': 'BeatBoss/1.0 (Flutter)'},
                  );
                  if (requestId != _lastRequestId) {
                    handle?.cancel();
                    return;
                  }
                  if (handle != null) {
                    _cacheHandle = handle;
                    directUrl = finalUrl;
                    audioUrl = handle.playbackUrl;
                  }
                } catch (e) {
                  print('[AudioHandler] Stream cache unavailable: $e');
                }
              }
              break;
            }
          } catch (e) {
            print('[AudioHandler] Stream fetch retry $retries: $e');
          }
          retries++;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (audioUrl != null && audioUrl.trim().isNotEmpty && requestId == _lastRequestId) {
        print('[AudioHandler] Opening media: $audioUrl');
        final item = _toMediaItem(track);

        final source = AudioSource.uri(
          Uri.parse(audioUrl),
          headers: {'User-Agent': 'BeatBoss/1.0 (Flutter)'},
          tag: item,
        );

        try {
          await _player.setAudioSource(source, initialPosition: startPosition);
        } catch (e) {
          if (usedCache) {
            // A cached file that will not open is dropped; stream instead.
            print('[AudioHandler] Cached file failed to open ($e), streaming instead.');
            _streamCache.invalidate(track);
            if (requestId == _lastRequestId) {
              final liveIndex = _q.tracks.indexWhere((t) => identical(t, track));
              if (liveIndex >= 0) {
                await _playQueueItem(liveIndex,
                    startPosition: startPosition,
                    skipCache: true,
                    direction: direction);
              }
            }
            return;
          }
          if (directUrl == null) rethrow;
          // The cache proxy failed: drop it and open the remote URL directly.
          print('[AudioHandler] Cache proxy failed ($e), opening the stream directly.');
          _cacheHandle?.cancel();
          _cacheHandle = null;
          await _player.setAudioSource(
            AudioSource.uri(
              Uri.parse(directUrl),
              headers: {'User-Agent': 'BeatBoss/1.0 (Flutter)'},
              tag: item,
            ),
            initialPosition: startPosition,
          );
        }
        if (requestId != _lastRequestId) return;
        // The new source is loaded: from here on the player's position is the
        // new track's, so report it (it was held at zero while loading).
        _isSwitchingTrack = false;
        _broadcastState();
        _player.play();
        _failureStreak = 0;
      } else if (requestId == _lastRequestId) {
        print('[AudioHandler] Failed to resolve playable audio URL for track: ${track.title}');
        await _handleLoadFailure(track, index, direction, requestId);
      }
    } catch (e, st) {
      if (requestId != _lastRequestId) {
        // A newer request interrupted this one (e.g. Next tapped again while
        // loading). It owns the player now, so don't touch the state.
        print('[AudioHandler] Load of "${track.title}" was superseded');
      } else {
        print('[AudioHandler] CRITICAL PLAYBACK ERROR: $e');
        print(st);
        await _handleLoadFailure(track, index, direction, requestId);
      }
    } finally {
      print('[AudioHandler] --- Playback Init Complete [ID: $requestId] ---');
    }
  }

  /// The [failedTrack] at [fallbackIndex] could not be loaded. If it is still
  /// the latest request, move on to the next track in the same [direction]
  /// (at most 3 in a row), otherwise stop cleanly instead of sitting in
  /// "buffering" forever.
  Future<void> _handleLoadFailure(
      Track failedTrack, int fallbackIndex, int direction, int requestId) async {
    if (requestId != _lastRequestId) return; // a newer request owns the player
    _isSwitchingTrack = false;
    _failureStreak++;
    final currentPos = _q.tracks.indexWhere((t) => identical(t, failedTrack));
    final baseIndex = currentPos >= 0 ? currentPos : fallbackIndex;
    var next = baseIndex + direction;
    if (_failureStreak <= _maxFailureSkips &&
        direction > 0 &&
        next >= _q.length &&
        _pendingAutoplay != null) {
      await _awaitPendingAutoplay();
      if (requestId != _lastRequestId) return;
      final refreshedPos =
          _q.tracks.indexWhere((t) => identical(t, failedTrack));
      next = (refreshedPos >= 0 ? refreshedPos : baseIndex) + direction;
    }
    if (_failureStreak <= _maxFailureSkips && next >= 0 && next < _q.length) {
      print('[AudioHandler] Skipping an unplayable track, trying #$next');
      _playQueueItem(next, direction: direction);
    } else {
      print('[AudioHandler] Giving up after $_failureStreak unplayable tracks');
      _failureStreak = 0;
      await stop();
    }
  }

  /// [autoplay] marks tracks that autoplay added, so the UI can show them in
  /// their own section.
  MediaItem _toMediaItem(Track track, {bool autoplay = false, int? queueEntryId}) {
    Uri? artUri;

    // ON WINDOWS: The SMTC WinRT bridge throws a C++ exception
    // (0x80070057: 'null is not a valid absolute URI') if artUri is null.
    // Always provide a valid HTTPS URI on Windows/Desktop.
    const winPlaceholderArt =
        'https://raw.githubusercontent.com/google/material-design-icons/master/png/av/music_note/materialiconsoutlined/48dp/2x/outline_music_note_black_48dp.png';

    if (!kIsWeb && !PlatformHelper.isAndroid) {
      if (track.albumCover != null &&
          track.albumCover!.isNotEmpty &&
          track.albumCover!.startsWith('http')) {
        artUri = Uri.parse(track.albumCover!);
      } else {
        artUri = Uri.parse(winPlaceholderArt);
      }
    } else {
      if (track.albumCover != null && track.albumCover!.isNotEmpty) {
        artUri = track.albumCover!.startsWith('http')
            ? Uri.parse(track.albumCover!)
            : Uri.file(track.albumCover!);
      }
    }

    return MediaItem(
      id: track.id,
      album: track.albumTitle ?? '',
      title: track.title,
      artist: track.artist,
      duration: track.duration != null
          ? (track.duration! > 10000
              ? Duration(milliseconds: track.duration!)
              : Duration(seconds: track.duration!))
          : null,
      artUri: artUri,
      extras: {
        'track': track.toJson(),
        if (autoplay) 'autoplay': true,
        if (queueEntryId != null) 'queueEntryId': queueEntryId,
      },
    );
  }

  /// Volume: callers pass 0.0–1.0
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _failureStreak = 0;
    await _playQueueItem(index);
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _q.length) return;
    final wasCurrent = _q.removeAt(index);
    _broadcastQueue();
    if (wasCurrent) {
      if (_q.isEmpty) {
        stop();
      } else {
        if (_q.currentIndex >= _q.length) _q.currentIndex = 0;
        _playQueueItem(_q.currentIndex);
      }
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    _q.reorder(oldIndex, newIndex);
    _broadcastQueue();
    _broadcastState();
  }

  Future<void> insertNext(Track track) async {
    if (_q.isEmpty) {
      await setRequestQueue([track]);
      return;
    }
    _q.insertNext(track);
    _broadcastQueue();
  }

  /// Adds [track] after the user's own tracks, ahead of any autoplay ones.
  Future<void> addTrackToQueue(Track track) async {
    if (_q.isEmpty) {
      await setRequestQueue([track]);
      return;
    }
    _q.addToEnd(track);
    _broadcastQueue();
  }

  @override
  Future<void> onTaskRemoved() async => await stop();

  void _startPositionPolling() {
    if (!kIsWeb) return;
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isDashActive) {
        final pos = DashService.getPosition();
        final dur = DashService.getDuration();
        playbackState.add(playbackState.value.copyWith(
          updatePosition: Duration(seconds: pos.toInt()),
          speed: 1.0,
          bufferedPosition: Duration(seconds: pos.toInt() + 10),
        ));
        if (dur > 0 && pos >= dur - 0.5) {
          timer.cancel();
          skipToNext();
        }
      } else {
        _broadcastState();
      }
    });
  }

  void _stopPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      _settingsService.removeListener(_onSettingsChanged);
      _prefetchedHandle?.cancel();
      _prefetchedHandle = null;
      _prefetchedHandleTrackId = null;
      _releaseCacheHandle();
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      await _player.dispose();
      DashLocalProxyServer.stop();
    }
  }
}
