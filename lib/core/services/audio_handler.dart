import 'dart:async';
import 'package:flutter/foundation.dart'; // kIsWeb
import '../utils/platform_helper.dart';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import 'download_manager_service.dart';
import 'addon_service.dart';
import 'dash_service.dart';
import 'dash_native_parser.dart';
import 'dash_local_proxy_server.dart';
import 'native_player_config.dart';

/// The AudioHandler manages the audio player and the playlist.
/// It exposes the standard AudioService interface to the UI (and system).
/// Uses just_audio Player directly.
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  late final AudioPlayer _player;
  final DownloadManagerService _downloadManager;
  final AddonService _addonService;

  // Internal Queue State
  List<Track> _internalQueue = [];
  int _currentIndex = -1;
  bool _isDashActive = false;
  Timer? _positionTimer;
  int _lastRequestId = 0;
  bool _isSwitchingTrack = false;

  final List<StreamSubscription> _subscriptions = [];

  AppAudioHandler({
    required DownloadManagerService downloadManager,
    required AddonService addonService,
  })  : _downloadManager = downloadManager,
        _addonService = addonService {
    _init();
  }

  // Expose explicit state for UI polling
  Duration get currentPosition {
    if (_isDashActive) return playbackState.value.position;
    return _player.position;
  }

  bool get isPlayerPlaying {
    if (_isDashActive) return playbackState.value.playing;
    return _player.playing;
  }

  Future<void> _init() async {
    _player = AudioPlayer();
    
    if (!kIsWeb) {
      _downloadManager.cleanupTemporaryFiles();
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
      _player.playingStream.listen((_) => _broadcastState()),
      _player.positionStream.listen((_) => _broadcastState()),
      _player.bufferedPositionStream.listen((_) => _broadcastState()),
      _player.playerStateStream.listen((state) {
        _broadcastState();
        if (state.processingState == ProcessingState.ready) {
          _isSwitchingTrack = false;
        }
        if (state.processingState == ProcessingState.completed) {
          _handleTrackCompletion();
        }
      }),
      _player.durationStream.listen((_) => _broadcastState()),
    ]);

    if (kIsWeb) {
      _subscriptions.add(_player.playingStream.listen((playing) {
        if (playing) _startPositionPolling();
        else _stopPositionPolling();
      }));
    }
  }

  /// Broadcasts current player state to audio_service (SMTC / Bluetooth / UI)
  void _broadcastState() {
    final isPlaying = _player.playing;
    final position = _player.position;
    final buffered = _player.bufferedPosition;
    final isBuffering = _player.playerState.processingState == ProcessingState.buffering;
    final isCompleted = _player.playerState.processingState == ProcessingState.completed;

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
      speed: _player.speed,
      queueIndex: _currentIndex,
      repeatMode: _mapLoopModeToRepeatMode(_player.loopMode),
      shuffleMode: _player.shuffleModeEnabled
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
    if (_isSwitchingTrack) return;
    if (_player.loopMode == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      if (_currentIndex < _internalQueue.length - 1) {
        _currentIndex++;
        _playQueueItem(_currentIndex);
      } else {
        if (_player.loopMode == LoopMode.all) {
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
    if (_internalQueue.isEmpty) return;
    int nextIndex = _currentIndex + 1;
    if (_player.loopMode == LoopMode.all && nextIndex >= _internalQueue.length) {
      nextIndex = 0;
    }
    if (nextIndex < _internalQueue.length) await _playQueueItem(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_internalQueue.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }
    int prevIndex = _currentIndex - 1;
    if (_player.loopMode == LoopMode.all && prevIndex < 0) {
      prevIndex = _internalQueue.length - 1;
    }
    if (prevIndex >= 0) await _playQueueItem(prevIndex);
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
    await _player.setShuffleModeEnabled(enabled);
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
    _isSwitchingTrack = true;

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

              if (kIsWeb || PlatformHelper.isWindows || PlatformHelper.isLinux) {
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
                    getPosition: () => _player.position.inSeconds.toDouble(),
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

        final source = AudioSource.uri(
          Uri.parse(audioUrl),
          headers: {'User-Agent': 'BeatBoss/1.0 (Flutter)'},
          tag: item,
        );

        await _player.setAudioSource(source, initialPosition: startPosition);
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

  /// Volume: callers pass 0.0–1.0
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
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
