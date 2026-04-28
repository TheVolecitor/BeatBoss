import 'dart:async';
import 'package:flutter/foundation.dart'; // kIsWeb
import '../utils/platform_helper.dart';

import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart' as mk;


import '../models/models.dart';
import 'download_manager_service.dart';
import 'addon_service.dart';
import 'dash_service.dart';
import 'dash_native_parser.dart';
import 'dash_local_proxy_server.dart';
import 'native_player_config.dart';


/// The AudioHandler manages the audio player and the playlist.
/// It exposes the standard AudioService interface to the UI (and system).
/// Uses media_kit Player directly — no just_audio shim.
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  // Single stable media_kit Player — never recreated.
  // open() atomically replaces the current source without needing disposal.
  final mk.Player _player;
  final DownloadManagerService _downloadManager;
  final AddonService _addonService;

  // Internal Queue State
  List<Track> _internalQueue = [];
  int _currentIndex = -1;
  bool _isDashActive = false;
  Timer? _positionTimer;
  int _lastRequestId = 0;

  // Loop/Shuffle tracked internally (media_kit PlaylistMode)
  mk.PlaylistMode _currentPlaylistMode = mk.PlaylistMode.none;
  bool _shuffleEnabled = false;

  final List<StreamSubscription> _subscriptions = [];

  AppAudioHandler({
    required DownloadManagerService downloadManager,
    required AddonService addonService,
  })  : _player = mk.Player(
          configuration: mk.PlayerConfiguration(
            title: 'BeatBoss',
            logLevel: mk.MPVLogLevel.error,
            protocolWhitelist: [
              'udp', 'rtp', 'tcp', 'tls', 'data', 'file',
              'http', 'https', 'crypto', 'httpproxy',
            ],
          ),
        ),
        _downloadManager = downloadManager,
        _addonService = addonService {
    _init();
  }

  // Expose explicit state for UI polling
  Duration get currentPosition {
    if (_isDashActive) return playbackState.value.position;
    return _player.state.position;
  }

  bool get isPlayerPlaying {
    if (_isDashActive) return playbackState.value.playing;
    return _player.state.playing;
  }

  Future<void> _init() async {
    // Cleanup old temp files from previous sessions (native only)
    if (!kIsWeb) {
      _downloadManager.cleanupTemporaryFiles();
    }

    // Set mpv properties via NativePlayer API for reliable DASH playback.
    // DASH is thread-heavy (multiple segment-fetching workers). These settings
    // prevent the file-lock and thread-reaping crashes on Windows.
    if (!kIsWeb) {
      configureNativePlayer(_player);
    }


    _setupPlayerListeners();
  }

  void _setupPlayerListeners() {
    // Clear existing subscriptions
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    // Subscribe to media_kit streams and push PlaybackState to audio_service
    _subscriptions.addAll([
      _player.stream.playing.listen((_) => _broadcastState()),
      _player.stream.position.listen((_) => _broadcastState()),
      _player.stream.buffer.listen((_) => _broadcastState()),
      _player.stream.buffering.listen((_) => _broadcastState()),
      _player.stream.duration.listen((_) => _broadcastState()),
      _player.stream.completed.listen((completed) {
        if (completed) _handleTrackCompletion();
      }),
      _player.stream.error.listen((error) {
        // LOG ONLY — do NOT auto-retry.
        // Transient TCP errors (WSAECONNABORTED, TLS reconnect) are common during
        // DASH segment fetching and are non-fatal. MPV reconnects automatically.
        // The old auto-recovery here was the actual cause of the crash:
        // it called _playQueueItem → dispose → recreate → seek into unloaded DASH → crash.
        print('[AudioHandler] MPV Error (non-fatal, no auto-retry): $error');
      }),
      _player.stream.log.listen((log) {
        print('MPV: [${log.level}] ${log.prefix}: ${log.text}');
      }),
    ]);

    // Web: position polling for DASH seek bar
    if (kIsWeb) {
      _subscriptions.add(_player.stream.playing.listen((playing) {
        if (playing) _startPositionPolling();
        else _stopPositionPolling();
      }));
    }
  }

  /// Broadcasts current player state to audio_service (SMTC / Bluetooth / UI)
  void _broadcastState() {

    final isPlaying = _player.state.playing;
    final position = _player.state.position;
    final buffered = _player.state.buffer;
    final isBuffering = _player.state.buffering;
    final isCompleted = _player.state.completed;

    AudioProcessingState processingState;
    if (isCompleted) {
      processingState = AudioProcessingState.completed;
    } else if (isBuffering) {
      processingState = AudioProcessingState.buffering;
    } else if (_currentIndex < 0) {
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
      speed: _player.state.rate,
      queueIndex: _currentIndex,
      repeatMode: _mapPlaylistModeToRepeatMode(_currentPlaylistMode),
      shuffleMode: _shuffleEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  AudioServiceRepeatMode _mapPlaylistModeToRepeatMode(mk.PlaylistMode mode) {
    switch (mode) {
      case mk.PlaylistMode.none: return AudioServiceRepeatMode.none;
      case mk.PlaylistMode.single: return AudioServiceRepeatMode.one;
      case mk.PlaylistMode.loop: return AudioServiceRepeatMode.all;
    }
  }

  void _handleTrackCompletion() {
    if (_currentPlaylistMode == mk.PlaylistMode.single) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      if (_currentIndex < _internalQueue.length - 1) {
        _currentIndex++;
        _playQueueItem(_currentIndex);
      } else {
        if (_currentPlaylistMode == mk.PlaylistMode.loop) {
          _currentIndex = 0;
          _playQueueItem(0);
        } else {
          stop();
          _player.seek(Duration.zero);
        }
      }
    }
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
    if (kIsWeb) {
      DashService.stop();
      _isDashActive = false;
      _stopPositionPolling();
    }
    if (PlatformHelper.isWindows) {
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
    if (_internalQueue.isEmpty) return;
    int nextIndex = _currentIndex + 1;
    if (_currentPlaylistMode == mk.PlaylistMode.loop && nextIndex >= _internalQueue.length) {
      nextIndex = 0;
    }
    if (nextIndex < _internalQueue.length) await _playQueueItem(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_internalQueue.isEmpty) return;
    if (_player.state.position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }
    int prevIndex = _currentIndex - 1;
    if (_currentPlaylistMode == mk.PlaylistMode.loop && prevIndex < 0) {
      prevIndex = _internalQueue.length - 1;
    }
    if (prevIndex >= 0) await _playQueueItem(prevIndex);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        _currentPlaylistMode = mk.PlaylistMode.none;
        break;
      case AudioServiceRepeatMode.one:
        _currentPlaylistMode = mk.PlaylistMode.single;
        break;
      case AudioServiceRepeatMode.all:
        _currentPlaylistMode = mk.PlaylistMode.loop;
        break;
      default:
        _currentPlaylistMode = mk.PlaylistMode.none;
    }
    await _player.setPlaylistMode(_currentPlaylistMode);
    _broadcastState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    _shuffleEnabled = enabled;
    if (enabled) _shuffleQueue(); else _unshuffleQueue();
    _broadcastState();
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {}

  Future<void> setRequestQueue(List<Track> tracks, {int pendingIndex = 0}) async {
    _internalQueue = List.from(tracks);
    _currentIndex = pendingIndex;
    final items = tracks.map((t) => _toMediaItem(t)).toList();
    queue.add(items);
    if (_internalQueue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _internalQueue.length) {
      await _playQueueItem(_currentIndex);
    }
  }

  Future<void> _playQueueItem(int index, {Duration? startPosition}) async {
    if (index < 0 || index >= _internalQueue.length) return;

    _currentIndex = index;
    final track = _internalQueue[index];
    final requestId = ++_lastRequestId;

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
      // Without this, the second stream writes to memory the OS still considers
      // owned by the dying first stream's workers.
      if (!kIsWeb) {
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

      if (useLocal) {
        audioUrl = Uri.file(localPath).toString();
        print('[AudioHandler] Playing local file: $audioUrl');
      } else {
        int retries = 0;
        while (retries < 2) {
          try {
            final streamResult = await _addonService.getStreamResult(
              track.addonTrackId ?? track.id, addonId: track.addonId);
            if (requestId != _lastRequestId) return;

            final url = streamResult?.url;
            final format = streamResult?.format?.toLowerCase();
            if (url == null) throw Exception('No stream URL found');

            final bool isDash = (format == 'dash' || url.contains('<MPD') || url.contains('.mpd'));

            if (isDash) {
              if (requestId != _lastRequestId) return;

              const String proxy = 'https://webdownloadproxy.thevolecitor.workers.dev/?url=';

              if (kIsWeb || PlatformHelper.isWindows) {
                if (kIsWeb) {
                  final manifestUri = await DashService.getManifestUri(url, proxy: proxy, trackId: track.id);
                  DashService.init(manifestUri, proxy);
                  _isDashActive = true;
                  _startPositionPolling();

                  final item = _toMediaItem(track);
                  mediaItem.add(item);
                  playbackState.add(playbackState.value.copyWith(
                    playing: true,
                    speed: 1.0,
                    processingState: AudioProcessingState.ready,
                    controls: [MediaControl.skipToPrevious, MediaControl.pause, MediaControl.stop, MediaControl.skipToNext],
                  ));
                  return;
                } else {
                  DashLocalProxyServer.stop();
                  final manifest = await DashNativeParser.parse(url);
                  audioUrl = await DashLocalProxyServer.start(
                    manifest,
                    proxyUrl: null, // As requested, do NOT use Cloudflare worker
                    getPosition: () => _player.state.position.inSeconds.toDouble(),
                  );
                  break;
                }
              } else {
                audioUrl = url;
                break;
              }
            } else {
              if (kIsWeb) DashService.stop();
              audioUrl = url;
              break;
            }
          } catch (e) {
            print('[AudioHandler] Stream fetch retry $retries: $e');
          }
          retries++;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (audioUrl != null && requestId == _lastRequestId) {
        print('[AudioHandler] Opening media: $audioUrl');
        final item = _toMediaItem(track);
        // media_kit: open() replaces the current source cleanly
        await _player.open(mk.Media(audioUrl), play: false);
        if (requestId != _lastRequestId) return;
        if (startPosition != null) await _player.seek(startPosition);
        if (requestId != _lastRequestId) return;
        mediaItem.add(item);
        _player.play();
      }
    } catch (e, st) {
      print('[AudioHandler] CRITICAL PLAYBACK ERROR: $e');
      print(st);
    } finally {
      print('[AudioHandler] --- Playback Init Complete [ID: $requestId] ---');
    }
  }

  MediaItem _toMediaItem(Track track) {
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
      extras: {'track': track.toJson()},
    );
  }

  void _shuffleQueue() {
    if (_internalQueue.isEmpty) return;
    final currentTrack = _currentIndex >= 0 ? _internalQueue[_currentIndex] : null;
    _internalQueue.shuffle();
    if (currentTrack != null) {
      _internalQueue.removeWhere((t) => t.id == currentTrack.id);
      _internalQueue.insert(0, currentTrack);
      _currentIndex = 0;
    }
    queue.add(_internalQueue.map(_toMediaItem).toList());
  }

  void _unshuffleQueue() {
    // No-op — we don't store the original order
  }

  /// Volume: media_kit uses 0–100, callers pass 0.0–1.0
  Future<void> setVolume(double volume) async {
    await _player.setVolume((volume * 100).clamp(0.0, 100.0));
  }

  @override
  Future<void> skipToQueueItem(int index) async => await _playQueueItem(index);

  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _internalQueue.length) {
      bool isCurrent = index == _currentIndex;
      _internalQueue.removeAt(index);
      queue.add(_internalQueue.map(_toMediaItem).toList());
      if (index < _currentIndex) _currentIndex--;
      if (isCurrent) {
        if (_internalQueue.isEmpty) {
          stop();
        } else {
          if (_currentIndex >= _internalQueue.length) _currentIndex = 0;
          _playQueueItem(_currentIndex);
        }
      }
    }
  }

  Future<void> insertNext(Track track) async {
    if (_internalQueue.isEmpty) {
      await setRequestQueue([track]);
      return;
    }
    _internalQueue.insert(_currentIndex + 1, track);
    queue.add(_internalQueue.map(_toMediaItem).toList());
  }

  Future<void> addTrackToQueue(Track track) async {
    if (_internalQueue.isEmpty) {
      await setRequestQueue([track]);
      return;
    }
    _internalQueue.add(track);
    queue.add(_internalQueue.map(_toMediaItem).toList());
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
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      await _player.dispose();
      DashLocalProxyServer.stop();
    }
  }
}
