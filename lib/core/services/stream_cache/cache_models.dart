// Platform-neutral types for the local stream cache (no dart:io here, so the
// web build and the stubs can import this file).

/// One cached audio file, as recorded in the cache index.
class StreamCacheEntry {
  final String key; // "<addonId>:<trackId>"
  final String fileName; // relative to the cache directory
  final int size;
  final int createdAt; // ms since epoch
  final int lastAccess; // ms since epoch, drives LRU eviction
  final String trackId;
  final String? addonId;
  final String? addonTrackId;
  final String title;
  final String artist;
  final int? duration; // as reported by the addon (seconds or ms)
  final String? format; // as reported by the addon
  final String? quality; // as reported by the addon

  const StreamCacheEntry({
    required this.key,
    required this.fileName,
    required this.size,
    required this.createdAt,
    required this.lastAccess,
    required this.trackId,
    required this.title,
    required this.artist,
    this.addonId,
    this.addonTrackId,
    this.duration,
    this.format,
    this.quality,
  });

  StreamCacheEntry touched(int now) => StreamCacheEntry(
        key: key,
        fileName: fileName,
        size: size,
        createdAt: createdAt,
        lastAccess: now,
        trackId: trackId,
        title: title,
        artist: artist,
        addonId: addonId,
        addonTrackId: addonTrackId,
        duration: duration,
        format: format,
        quality: quality,
      );

  factory StreamCacheEntry.fromJson(Map<String, dynamic> json) {
    return StreamCacheEntry(
      key: json['key'] as String,
      fileName: json['fileName'] as String,
      size: json['size'] as int,
      createdAt: json['createdAt'] as int,
      lastAccess: json['lastAccess'] as int,
      trackId: json['trackId'] as String,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      addonId: json['addonId'] as String?,
      addonTrackId: json['addonTrackId'] as String?,
      duration: json['duration'] as int?,
      format: json['format'] as String?,
      quality: json['quality'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'fileName': fileName,
        'size': size,
        'createdAt': createdAt,
        'lastAccess': lastAccess,
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'addonId': addonId,
        'addonTrackId': addonTrackId,
        'duration': duration,
        'format': format,
        'quality': quality,
      };
}

/// A track that is currently being cached while it plays.
abstract class CacheHandle {
  /// Tells the cache how far the user got when playback of this track ended
  /// (skip, stop, or completion). Below the minimum play time the partial
  /// download is cancelled and deleted; otherwise it keeps downloading in the
  /// background until the file is complete.
  void release(Duration played);

  /// Duration reported by the player; used to sanity-check the finished file.
  void reportDuration(Duration duration);

  /// Stops the download and deletes the partial file.
  void cancel();
}

/// Cache handle backed by the local caching proxy; the player reads from
/// [playbackUrl] instead of the remote URL.
abstract class ProxyCacheHandle implements CacheHandle {
  String get playbackUrl;
}

/// Cache handle fed by the DASH proxy, which stitches segments into one
/// continuous stream and hands every chunk to [add].
abstract class CacheByteSink implements CacheHandle {
  /// False once the sink was cancelled or failed; the DASH proxy should stop
  /// fetching for it.
  bool get isActive;

  Future<void> add(List<int> bytes);

  /// All segments were written; verifies, renames and registers the file.
  Future<void> finish();

  /// The stream ended early; discards the partial file.
  Future<void> fail();
}

/// Cache-size choices offered in the settings (MB).
const List<int> kCacheSizeOptionsMb = [256, 512, 1024, 2048, 5120];
const int kDefaultCacheSizeMb = 1024;

/// Playback shorter than this does not leave a cached file behind.
const Duration kMinPlayToCache = Duration(seconds: 15);
