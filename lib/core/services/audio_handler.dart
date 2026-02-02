import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart'
    as mk; // Alias to avoid conflicts with just_audio
import 'package:audio_session/audio_session.dart';

import '../models/models.dart';
import 'download_manager_service.dart';
import 'dab_api_service.dart';

/// The AudioHandler manages the audio player and the playlist.
/// It exposes the standard AudioService interface to the UI (and system).
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  // Android Equalizer instance - created here to be part of the pipeline
  // accessible via getter for AudioEffectsService
  AndroidEqualizer? _androidEqualizer;
  AndroidEqualizer? get androidEqualizer => _androidEqualizer;

  late final AudioPlayer _player;
  final DownloadManagerService _downloadManager;
  final DabApiService _dabApiService;

  // Internal Queue State
  // We mirror the queue in AudioService's queue stream (List<MediaItem>)
  List<Track> _internalQueue = [];
  int _currentIndex = -1;

  // Custom State initialized

  AppAudioHandler({
    required DownloadManagerService downloadManager,
    required DabApiService dabApiService,
  })  : _downloadManager = downloadManager,
        _dabApiService = dabApiService {
    // Initialize Pipeline
    if (Platform.isAndroid) {
      _androidEqualizer = AndroidEqualizer();
      _player = AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: [_androidEqualizer!],
        ),
      );
    } else {
      _player = AudioPlayer();
    }

    _init();
  }

  // Expose explicit state for polling
  Duration get currentPosition => _player.position;
  bool get isPlayerPlaying => _player.playing;
  int? _audioSessionId;
  int? get audioSessionId => _audioSessionId;

  // Expose internal player for AudioEffectsService (EQ)
  AudioPlayer get player => _player;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Android specfic: get session ID for EQ
    if (Platform.isAndroid) {
      // just_audio exposes androidAudioSessionId via player
      // But we need to wait for player to initialize?
      // JustAudio doc says androidAudioSessionId is available after setting source?
      // Let's defer or poll.
      // Actually `player.androidAudioSessionId` is a property.
    }

    // Broadcast playback state via pipe (Standard SMTC procedure)
    // This transforms just_audio events into audio_service PlaybackState
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Listen to Processing State for track completion to handle auto-advance
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // Check for premature completion (Stream Drop)
        // If we consistently stop 5s before end, it's a drop.
        final duration = _player.duration;
        final position = _player.position;

        if (duration != null &&
            duration.inSeconds > 30 && // Only for substantial tracks
            position.inSeconds > 5 && // Ensure we actually played something
            position.inSeconds < duration.inSeconds - 10) {
          // Dropped more than 10s before end

          print(
              "[AudioHandler] Premature stop detected at ${position.inSeconds}s. Attempting auto-recovery...");
          _playQueueItem(_currentIndex, startPosition: position);
        } else {
          _handleTrackCompletion();
        }
      }
    });

    _setupErrorListeners();
  }

  // Error listener
  void _setupErrorListeners() {
    // just_audio emits errors sometimes via playbackEventStream
    _player.playbackEventStream.listen((event) {},
        onError: (Object e, StackTrace st) {
      print("[AudioHandler] Playback Error: $e");

      // Attempt recovery on error if we were playing or expecting to play
      if (_currentIndex >= 0 && _currentIndex < _internalQueue.length) {
        print("[AudioHandler] Attempting recovery from error...");
        // Wait a bit before retrying to avoid loop
        Future.delayed(const Duration(seconds: 1), () {
          final pos = _player.position;
          _playQueueItem(_currentIndex, startPosition: pos);
        });
      }
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex, // Use our tracked index
      repeatMode: _mapRepeatMode(_player.loopMode),
      shuffleMode: _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
  }

  AudioServiceRepeatMode _mapRepeatMode(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return AudioServiceRepeatMode.none;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  void _handleTrackCompletion() {
    print(
        "DEBUG: _handleTrackCompletion called. LoopMode: ${_player.loopMode}, QueueLen: ${_internalQueue.length}, Index: $_currentIndex");

    // Loop/Next Logic
    // If repeat mode is ONE, replay
    if (_player.loopMode == LoopMode.one) {
      print("DEBUG: LoopMode is ONE. Replaying.");
      _player.seek(Duration.zero);
      _player.play();
    } else {
      // Consume Queue: Remove the track that just finished
      if (_internalQueue.isNotEmpty &&
          _currentIndex >= 0 &&
          _currentIndex < _internalQueue.length) {
        final removed = _internalQueue.removeAt(_currentIndex);
        print(
            "DEBUG: Removed track '${removed.title}' from queue. New Len: ${_internalQueue.length}");

        // Update AudioService queue
        queue.add(_internalQueue.map(_toMediaItem).toList());

        // If queue is empty after removal, stop
        if (_internalQueue.isEmpty) {
          print("DEBUG: Queue empty. Stopping.");
          stop();
          _currentIndex = -1;
        } else {
          // If queue still has items, play the item that is now at _currentIndex
          if (_currentIndex >= _internalQueue.length) {
            print("DEBUG: Index $_currentIndex >= Length. Resetting to 0.");
            _currentIndex = 0;
          }

          print(
              "DEBUG: Playing next item at index $_currentIndex: ${_internalQueue[_currentIndex].title}");
          _playQueueItem(_currentIndex);
        }
      } else {
        print("DEBUG: Queue empty or index invalid. Stopping.");
        stop();
      }
    }
  }

  // ========== ACTIONS ==========

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_internalQueue.isEmpty) return;

    int nextIndex = _currentIndex + 1;
    // Handle repeat all
    if (_player.loopMode == LoopMode.all) {
      if (nextIndex >= _internalQueue.length) nextIndex = 0;
    }

    if (nextIndex < _internalQueue.length) {
      await _playQueueItem(nextIndex);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_internalQueue.isEmpty) return;

    // If played more than 3 sec, restart
    if (_player.position.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }

    int prevIndex = _currentIndex - 1;
    if (_player.loopMode == LoopMode.all) {
      if (prevIndex < 0) prevIndex = _internalQueue.length - 1;
    }

    if (prevIndex >= 0) {
      await _playQueueItem(prevIndex);
    }
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
        break;
    }
    // _transformEvent picks up the change via stream
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    if (enabled) {
      _shuffleQueue();
    } else {
      _unshuffleQueue();
    }
    await _player.setShuffleModeEnabled(enabled);
  }

  // Custom action to set the entire queue
  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    // Left empty as we use setRequestQueue
  }

  // Custom method exposed via dynamic calls or extension
  Future<void> setRequestQueue(List<Track> tracks,
      {int pendingIndex = 0}) async {
    _internalQueue = List.from(tracks);
    _currentIndex = pendingIndex;

    // Update AudioService queue (metadata only)
    final items = tracks.map((t) => _toMediaItem(t)).toList();
    queue.add(items);

    if (_internalQueue.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _internalQueue.length) {
      await _playQueueItem(_currentIndex);
    }
  }

  // Play a specific index
  Future<void> _playQueueItem(int index, {Duration? startPosition}) async {
    if (index < 0 || index >= _internalQueue.length) return;

    _currentIndex = index;
    final track = _internalQueue[index];

    // Broadcast MediaItem - explicit update
    final item = _toMediaItem(track);
    mediaItem.add(item);

    // actually play
    try {
      // Check local download
      final isDownloaded = _downloadManager.isDownloaded(track.id);
      final localPath = _downloadManager.getLocalPath(track.id);

      Uri? audioUri;

      if (isDownloaded && localPath != null && File(localPath).existsSync()) {
        audioUri = Uri.file(localPath);
      } else {
        // Fetch Stream URL with Retry
        int retries = 0;
        while (retries < 2) {
          try {
            final url = await _dabApiService.getStreamUrl(track.id);
            if (url != null) {
              audioUri = Uri.parse(url);
              break;
            }
          } catch (e) {
            print("Stream fetch retry $retries error: $e");
          }
          retries++;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (audioUri != null) {
        // Revert to standard AudioSource.uri to avoid Windows file lock crashes (errno 32) behavior with LockCachingAudioSource
        final source = AudioSource.uri(
          audioUri,
          headers: {'User-Agent': 'BeatBoss/1.0 (Flutter)'},
          tag: item, // Pass MediaItem as tag
        );

        await _player.setAudioSource(source, initialPosition: startPosition);

        if (Platform.isAndroid) {
          _audioSessionId = _player.androidAudioSessionId;
          print("Android Audio Session ID: $_audioSessionId");
        }

        _player.play();
      } else {
        print("Error: Failed to get audio URI for track ${track.title}");
        // Ideally show toast or skip to next?
      }
    } catch (e) {
      print("Playback error: $e");
    }
  }

  MediaItem _toMediaItem(Track track) {
    Uri? artUri;
    if (track.albumCover != null && track.albumCover!.isNotEmpty) {
      if (track.albumCover!.startsWith('http')) {
        artUri = Uri.parse(track.albumCover!);
      } else {
        // Assume local file path or asset
        artUri = Uri.file(track.albumCover!);
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
      extras: {'track': track.toJson()}, // Keep full track data
    );
  }

  void _shuffleQueue() {
    if (_internalQueue.isEmpty) return;

    final currentTrack =
        _currentIndex >= 0 ? _internalQueue[_currentIndex] : null;
    _internalQueue.shuffle();

    if (currentTrack != null) {
      _internalQueue.removeWhere((t) => t.id == currentTrack.id);
      _internalQueue.insert(0, currentTrack);
      _currentIndex = 0;
    }

    // Update Queue Stream
    queue.add(_internalQueue.map(_toMediaItem).toList());
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _playQueueItem(index);
  }

  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _internalQueue.length) {
      bool isCurrent = index == _currentIndex;
      _internalQueue.removeAt(index);
      // Update AudioService queue
      queue.add(_internalQueue.map(_toMediaItem).toList());

      if (index < _currentIndex) {
        _currentIndex--;
      }

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

    final insertIndex = _currentIndex + 1;
    // Insert after current
    _internalQueue.insert(insertIndex, track);

    // Update Queue Stream
    queue.add(_internalQueue.map(_toMediaItem).toList());
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  void _unshuffleQueue() {
    // Restore logic if we had original queue
  }
}
