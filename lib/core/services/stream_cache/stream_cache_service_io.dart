import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/models.dart';
import '../settings_service.dart';
import 'cache_models.dart';
import 'caching_stream_server.dart';

/// Local cache for streamed tracks (native targets).
///
/// Files live in `<app support dir>/stream_cache`, named
/// `<addonId>_<trackId>.<ext>`, with the metadata kept in an index inside the
/// settings box. The cache is keyed by the addon's own track id, never by
/// title and artist, which are not unique (remasters, live versions, covers).
class StreamCacheService extends ChangeNotifier {
  StreamCacheService({
    required SettingsService settingsService,
    Directory? cacheDirectory,
    CachingStreamServer? server,
  })  : _settings = settingsService,
        _dir = cacheDirectory,
        _server = server;

  /// How many background downloads may run after the player moved on.
  static const int _maxDetachedDownloads = 3;

  final SettingsService _settings;
  Directory? _dir;
  CachingStreamServer? _server;

  final Map<String, StreamCacheEntry> _index = {};
  final List<_Job> _jobs = [];
  final List<_DashSink> _sinks = [];
  String? _playingKey;
  bool _initialized = false;
  bool _lastEnabled = false;
  int _lastMaxMb = kDefaultCacheSizeMb;

  bool get isSupported => true;
  bool get isEnabled => _initialized && _settings.localCacheEnabled;
  int get maxBytes => _settings.localCacheMaxMb * 1024 * 1024;
  int get usedBytes => _index.values.fold(0, (sum, e) => sum + e.size);
  int get entryCount => _index.length;

  static String keyFor(Track track) =>
      '${track.addonId ?? 'none'}:${track.addonTrackId ?? track.id}';

  String get _sep => Platform.pathSeparator;

  String _pathOf(StreamCacheEntry e) => '${_dir!.path}$_sep${e.fileName}';

  /// Readable, filesystem-safe base name. Falls back to a hash suffix when
  /// the ids contain characters that would collide after sanitizing.
  String _fileBase(Track track) {
    final addon = track.addonId ?? 'none';
    final id = track.addonTrackId ?? track.id;
    final safe = RegExp(r'^[A-Za-z0-9._-]+$');
    if (safe.hasMatch(addon) && safe.hasMatch(id) && addon.length + id.length < 100) {
      return '${addon}_$id';
    }
    String clean(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
    final hash = sha1.convert(utf8.encode('$addon:$id')).toString().substring(0, 8);
    return '${cut(clean(addon), 30)}_${cut(clean(id), 50)}_$hash';
  }

  // ---- lifecycle --------------------------------------------------------

  Future<void> init() async {
    _dir ??= Directory(
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}stream_cache');
    await _dir!.create(recursive: true);

    _index.clear();
    _settings.getStreamCacheIndex().forEach((key, value) {
      try {
        _index[key] =
            StreamCacheEntry.fromJson(Map<String, dynamic>.from(value as Map));
      } catch (_) {}
    });

    // Drop entries whose file is gone or has the wrong size.
    _index.removeWhere((key, e) {
      final f = File(_pathOf(e));
      return !f.existsSync() || f.lengthSync() != e.size;
    });

    // Remove leftovers: partial downloads from a previous run and files the
    // index does not know about.
    final known = _index.values.map((e) => e.fileName).toSet();
    for (final entity in _dir!.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.part') || !known.contains(name)) {
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    }

    _lastEnabled = _settings.localCacheEnabled;
    _lastMaxMb = _settings.localCacheMaxMb;
    _initialized = true;
    _evictToFit();
    await _saveIndex();
    _settings.addListener(_onSettingsChanged);
    notifyListeners();
  }

  void _onSettingsChanged() {
    final enabled = _settings.localCacheEnabled;
    final maxMb = _settings.localCacheMaxMb;
    if (enabled == _lastEnabled && maxMb == _lastMaxMb) return;
    _lastEnabled = enabled;
    _lastMaxMb = maxMb;
    _evictToFit();
    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _server?.close();
    super.dispose();
  }

  // ---- lookup -----------------------------------------------------------

  /// Path of a valid cached file for [track], or null. A hit refreshes the
  /// entry's last-access time (LRU) and protects it from eviction while it
  /// plays.
  String? lookup(Track track) {
    if (!isEnabled) return null;
    final key = keyFor(track);
    final entry = _index[key];
    if (entry == null) return null;

    final path = _pathOf(entry);
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() != entry.size) {
      _removeEntry(key);
      return null;
    }
    _index[key] = entry.touched(DateTime.now().millisecondsSinceEpoch);
    _playingKey = key;
    _persist();
    return path;
  }

  /// Forgets a cached file that failed to play.
  void invalidate(Track track) {
    _removeEntry(keyFor(track));
    notifyListeners();
  }

  /// The track that was playing is no longer protected from eviction.
  void clearPlaying() => _playingKey = null;

  // ---- caching while streaming -----------------------------------------

  /// Starts caching [url] and returns a handle whose `playbackUrl` the
  /// player should open instead of [url]. Returns null when caching is off or
  /// the track is already cached.
  Future<ProxyCacheHandle?> open(
    Track track,
    String url, {
    String? format,
    String? quality,
    Map<String, String>? headers,
  }) async {
    if (!isEnabled) return null;
    final key = keyFor(track);
    if (_index.containsKey(key)) return null;

    _jobs.removeWhere((j) => !j.session.isActive);
    for (final job in _jobs.where((j) => j.key == key).toList()) {
      job.session.cancel();
    }
    _jobs.removeWhere((j) => !j.session.isActive);

    final detached = _jobs.where((j) => j.session.isDetachedDownload).toList();
    while (detached.length >= _maxDetachedDownloads) {
      detached.removeAt(0).session.cancel();
    }

    _playingKey = key;
    final server = _server ??= CachingStreamServer();
    final session = await server.open(
      url: url,
      headers: headers ?? const {},
      partPath: '${_dir!.path}$_sep${_fileBase(track)}.part',
      onFinalize: (s, partPath, size) => _finalize(
        track,
        partPath,
        size,
        reportedDuration: s.reportedDuration,
        format: format,
        quality: quality,
        contentType: s.contentType,
      ),
    );
    _jobs.add(_Job(key, session));
    return session;
  }

  /// Sink for the DASH proxy on desktop: it receives the stitched stream.
  CacheByteSink? openDashSink(Track track, {String? quality}) {
    if (!isEnabled) return null;
    final key = keyFor(track);
    if (_index.containsKey(key)) return null;

    _sinks.removeWhere((s) => !s.isActive);
    for (final sink in _sinks.where((s) => s.key == key).toList()) {
      sink.cancel();
    }
    _playingKey = key;
    final sink = _DashSink(
        this, track, key, '${_dir!.path}$_sep${_fileBase(track)}.part', quality);
    _sinks.add(sink);
    return sink;
  }

  /// Verifies and registers a finished download. Returns the final path, or
  /// null when the file was rejected.
  Future<String?> _finalize(
    Track track,
    String partPath,
    int size, {
    Duration? reportedDuration,
    String? format,
    String? quality,
    String? contentType,
  }) async {
    if (!isEnabled || size <= 0 || size > maxBytes) return null;

    // The file must be the track we asked for: compare the duration the
    // player saw with the one the addon announced.
    final expected = _toSeconds(track.duration);
    if (expected != null && reportedDuration != null) {
      if ((expected - reportedDuration.inSeconds).abs() > 3) return null;
    }

    final key = keyFor(track);
    final fileName = '${_fileBase(track)}.${_extension(format, contentType)}';
    final dest = '${_dir!.path}$_sep$fileName';
    try {
      final previous = _index[key];
      if (previous != null && previous.fileName != fileName) {
        _deleteFile(_pathOf(previous));
      }
      final existing = File(dest);
      if (existing.existsSync()) existing.deleteSync();
      await File(partPath).rename(dest);
    } catch (_) {
      return null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    _index[key] = StreamCacheEntry(
      key: key,
      fileName: fileName,
      size: size,
      createdAt: now,
      lastAccess: now,
      trackId: track.id,
      addonId: track.addonId,
      addonTrackId: track.addonTrackId,
      title: track.title,
      artist: track.artist,
      duration: track.duration,
      format: format,
      quality: quality,
    );
    _evictToFit(protect: key);
    await _saveIndex();
    notifyListeners();
    return dest;
  }

  static int? _toSeconds(int? d) =>
      d == null ? null : (d > 10000 ? d ~/ 1000 : d);

  static String _extension(String? format, String? contentType) {
    switch (format?.toLowerCase()) {
      case 'flac':
        return 'flac';
      case 'mp3':
        return 'mp3';
      case 'ogg':
        return 'ogg';
      case 'opus':
        return 'opus';
      case 'aac':
      case 'm4a':
      case 'mp4':
      case 'dash':
        return 'm4a';
    }
    final type = (contentType ?? '').toLowerCase();
    if (type.contains('flac')) return 'flac';
    if (type.contains('mpeg')) return 'mp3';
    if (type.contains('ogg')) return 'ogg';
    if (type.contains('opus') || type.contains('webm')) return 'opus';
    return 'm4a';
  }

  // ---- eviction ---------------------------------------------------------

  /// Deletes the least recently played files until the cache fits the limit.
  /// The entry that is playing (or was just written) is never evicted.
  void _evictToFit({String? protect}) {
    var total = usedBytes;
    final max = maxBytes;
    if (total <= max) return;

    final candidates = _index.values
        .where((e) => e.key != protect && e.key != _playingKey)
        .toList()
      ..sort((a, b) => a.lastAccess.compareTo(b.lastAccess));
    for (final e in candidates) {
      if (total <= max) break;
      if (_deleteFile(_pathOf(e))) {
        _index.remove(e.key);
        total -= e.size;
      }
    }
    _persist();
  }

  bool _deleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _removeEntry(String key) {
    final entry = _index.remove(key);
    if (entry != null) _deleteFile(_pathOf(entry));
    _persist();
  }

  // ---- download manager integration ----------------------------------------

  /// Moves a cached file into the downloads folder instead of downloading the
  /// track again. Returns the new path, or null when the track is not cached.
  Future<String?> promote(
    Track track, {
    required String destDir,
    required String safeName,
  }) async {
    final key = keyFor(track);
    final entry = _index[key];
    if (entry == null) return null;
    final src = _pathOf(entry);
    if (!File(src).existsSync()) {
      _removeEntry(key);
      return null;
    }

    final ext = entry.fileName.contains('.')
        ? entry.fileName.substring(entry.fileName.lastIndexOf('.'))
        : '.m4a';
    final dest = '$destDir$_sep$safeName$ext';
    try {
      await Directory(destDir).create(recursive: true);
      final existing = File(dest);
      if (existing.existsSync()) await existing.delete();
      try {
        await File(src).rename(dest);
      } catch (_) {
        // Different volume, or the file is open in the player.
        await File(src).copy(dest);
        _deleteFile(src);
      }
    } catch (_) {
      return null;
    }

    _index.remove(key);
    await _saveIndex();
    notifyListeners();
    return dest;
  }

  /// Deletes every cached file and cancels running downloads.
  Future<void> clear() async {
    for (final job in _jobs) {
      job.session.cancel();
    }
    _jobs.clear();
    for (final sink in _sinks) {
      sink.cancel();
    }
    _sinks.clear();

    for (final e in _index.values.toList()) {
      if (_deleteFile(_pathOf(e))) _index.remove(e.key);
    }
    await _saveIndex();
    notifyListeners();
  }

  // ---- index persistence ------------------------------------------------

  void _persist() {
    unawaited(_saveIndex());
  }

  Future<void> _saveIndex() => _settings
      .saveStreamCacheIndex(_index.map((k, v) => MapEntry(k, v.toJson())));
}

class _Job {
  final String key;
  final CachingSession session;
  _Job(this.key, this.session);
}

/// Receives the stitched DASH stream from [DashLocalProxyServer] and writes
/// it to a `.part` file, registered once the stream completes.
class _DashSink implements CacheByteSink {
  _DashSink(this._service, this._track, this.key, this._partPath, this._quality);

  final StreamCacheService _service;
  final Track _track;
  final String key;
  final String _partPath;
  final String? _quality;

  IOSink? _out;
  int _bytes = 0;
  bool _active = true;
  bool _done = false;
  Duration? _reported;

  @override
  bool get isActive => _active;

  @override
  Future<void> add(List<int> bytes) async {
    if (!_active) return;
    _out ??= File(_partPath).openWrite();
    _out!.add(bytes);
    _bytes += bytes.length;
  }

  @override
  Future<void> finish() async {
    if (!_active) return;
    _active = false;
    final out = _out;
    _out = null;
    try {
      await out?.flush();
      await out?.close();
    } catch (_) {}
    final path = await _service._finalize(
      _track,
      _partPath,
      _bytes,
      reportedDuration: _reported,
      format: 'dash',
      quality: _quality,
    );
    if (path == null) _service._deleteFile(_partPath);
    _done = true;
  }

  @override
  Future<void> fail() async {
    if (!_active) return;
    _discard();
  }

  @override
  void reportDuration(Duration duration) {
    _reported = duration;
  }

  @override
  void release(Duration played) {
    if (!_active || _done) return;
    if (played < kMinPlayToCache) cancel();
  }

  @override
  void cancel() {
    if (!_active) return;
    _discard();
  }

  void _discard() {
    _active = false;
    final out = _out;
    _out = null;
    Future<void>(() async {
      try {
        await out?.close();
      } catch (_) {}
      _service._deleteFile(_partPath);
    });
  }
}
