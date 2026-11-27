import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

class MusicBrainzRecordingInfo {
  final String? isrc;
  final String? coverUrl;

  const MusicBrainzRecordingInfo({this.isrc, this.coverUrl});
}

/// Bulk-resolves ISRCs and cover metadata for up to 30 recording MBIDs per
/// request (rate-limited to 1.5s between batches) via ListenBrainz's public
/// `/1/metadata/recording/` endpoint, with MusicBrainz fallback for single
/// lookups and unauthenticated Deezer cover art resolution.
class MusicBrainzLookup {
  static const _userAgent =
      'BeatBoss/2.0.0 (https://github.com/TheVolecitor/BeatBoss)';

  final http.Client _client;
  final Duration _minInterval;
  final Map<String, MusicBrainzRecordingInfo?> _cache = {};
  final Map<String, Future<MusicBrainzRecordingInfo?>> _inflight = {};
  final Map<String, String?> _deezerCoverCache = {};
  final Map<String, Future<String?>> _deezerInflight = {};

  Future<void> _queue = Future.value();
  DateTime? _lastRequestAt;

  // Global concurrency cap for Deezer so multiple Home shelves don't spam
  // api.deezer.com simultaneously.
  static const int _maxDeezerConcurrent = 3;
  int _activeDeezer = 0;
  final Queue<Completer<void>> _deezerWaiters = Queue();

  MusicBrainzLookup({
    http.Client? client,
    Duration minInterval = const Duration(milliseconds: 1500),
  })  : _client = client ?? http.Client(),
        _minInterval = minInterval;

  MusicBrainzRecordingInfo? getCached(String mbid) => _cache[mbid.trim()];

  /// Clubs [mbids] into batches of 30 per 1.5 seconds via
  /// `GET /1/metadata/recording/?recording_mbids=...&inc=artist+release`.
  /// Deduplicates against both cache (including misses) and inflight requests.
  Future<Map<String, MusicBrainzRecordingInfo>> lookupRecordingsBulk(
    List<String> mbids,
  ) async {
    final result = <String, MusicBrainzRecordingInfo>{};
    final toWait = <String, Future<MusicBrainzRecordingInfo?>>{};
    final missing = <String>[];
    final seen = <String>{};

    for (final raw in mbids) {
      final clean = raw.trim();
      if (clean.isEmpty || !seen.add(clean)) continue;
      if (_cache.containsKey(clean)) {
        final cached = _cache[clean];
        if (cached != null) result[clean] = cached;
      } else if (_inflight.containsKey(clean)) {
        toWait[clean] = _inflight[clean]!;
      } else {
        missing.add(clean);
      }
    }

    const chunkSize = 30;
    for (var i = 0; i < missing.length; i += chunkSize) {
      final chunk = missing.skip(i).take(chunkSize).toList();
      final batchCompleters = <String, Completer<MusicBrainzRecordingInfo?>>{
        for (final id in chunk) id: Completer<MusicBrainzRecordingInfo?>(),
      };
      for (final id in chunk) {
        _inflight[id] = batchCompleters[id]!.future;
      }

      try {
        var fetched = await _enqueue(() => _fetchListenBrainzBulk(chunk));
        if (fetched == null) {
          await Future<void>.delayed(const Duration(seconds: 2));
          fetched = await _enqueue(() => _fetchListenBrainzBulk(chunk));
        }
        for (final id in chunk) {
          final info = fetched?[id];
          // Only cache hits/misses when we received a valid JSON response.
          if (fetched != null) {
            _cache[id] = info;
          }
          if (info != null) result[id] = info;
          batchCompleters[id]!.complete(info);
          _inflight.remove(id);
        }
      } catch (e) {
        for (final id in chunk) {
          batchCompleters[id]!.complete(null);
          _inflight.remove(id);
        }
      }
    }

    if (toWait.isNotEmpty) {
      await Future.wait(toWait.entries.map((e) async {
        final info = await e.value;
        if (info != null) result[e.key] = info;
      }));
    }

    return result;
  }

  Future<MusicBrainzRecordingInfo?> lookupRecording(String mbid) {
    final clean = mbid.trim();
    if (clean.isEmpty) return Future.value(null);
    if (_cache.containsKey(clean)) return Future.value(_cache[clean]);
    return _inflight.putIfAbsent(clean, () async {
      try {
        final bulk = await _enqueue(() => _fetchListenBrainzBulk([clean]));
        var info = bulk?[clean];
        info ??= await _enqueue(() => _fetchMusicBrainzSingle(clean));
        if (bulk != null || info != null) _cache[clean] = info;
        return info;
      } finally {
        _inflight.remove(clean);
      }
    });
  }

  /// Resolves cover art URL from Deezer without authentication using [isrc]
  /// (`GET /track/isrc:{isrc}`). Does not call Deezer `/search` (which returns
  /// empty `data: []` unauthenticated).
  Future<String?> resolveDeezerCover({
    String? isrc,
    String? title,
    String? artist,
  }) {
    final cleanIsrc = isrc?.trim() ?? '';
    if (cleanIsrc.isEmpty) return Future.value(null);
    final cacheKey = 'isrc:$cleanIsrc';
    if (_deezerCoverCache.containsKey(cacheKey)) {
      return Future.value(_deezerCoverCache[cacheKey]);
    }
    return _deezerInflight.putIfAbsent(cacheKey, () async {
      await _acquireDeezer();
      try {
        final cover = await _fetchDeezerCoverByIsrc(cleanIsrc);
        _deezerCoverCache[cacheKey] =
            (cover != null && cover.isNotEmpty) ? cover : null;
        return _deezerCoverCache[cacheKey];
      } finally {
        _releaseDeezer();
        _deezerInflight.remove(cacheKey);
      }
    });
  }

  Future<void> _acquireDeezer() async {
    if (_activeDeezer < _maxDeezerConcurrent) {
      _activeDeezer++;
      return;
    }
    final c = Completer<void>();
    _deezerWaiters.add(c);
    await c.future;
  }

  void _releaseDeezer() {
    if (_deezerWaiters.isNotEmpty) {
      _deezerWaiters.removeFirst().complete();
    } else if (_activeDeezer > 0) {
      _activeDeezer--;
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      if (_lastRequestAt != null) {
        final elapsed = DateTime.now().difference(_lastRequestAt!);
        if (elapsed < _minInterval) {
          await Future<void>.delayed(_minInterval - elapsed);
        }
      }
      _lastRequestAt = DateTime.now();
      try {
        completer.complete(await fn());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<Map<String, MusicBrainzRecordingInfo>?> _fetchListenBrainzBulk(
      List<String> mbids) async {
    if (mbids.isEmpty) return const {};
    try {
      final encoded = Uri.encodeQueryComponent(mbids.join(','));
      final uri = Uri.parse(
        'https://api.listenbrainz.org/1/metadata/recording/?recording_mbids=$encoded&inc=artist+release',
      );
      final resp = await _client.get(uri, headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      });
      if (resp.statusCode != 200) return null;
      final body = resp.body.trimLeft();
      if (!body.startsWith('{')) return null;
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;

      final out = <String, MusicBrainzRecordingInfo>{};
      for (final entry in decoded.entries) {
        final mbid = entry.key.trim();
        final val = entry.value;
        if (mbid.isEmpty || val is! Map) continue;

        String? isrc;
        final rec = val['recording'];
        if (rec is Map) {
          final isrcs = rec['isrcs'] as List<dynamic>? ?? const [];
          for (final item in isrcs) {
            final v = item?.toString().trim() ?? '';
            if (v.isNotEmpty) {
              isrc = v;
              break;
            }
          }
        }

        String? caaUrl;
        final rel = val['release'];
        if (rel is Map) {
          final caaRel = rel['caa_release_mbid']?.toString().trim() ?? '';
          final caaId = rel['caa_id']?.toString().trim() ?? '';
          if (caaRel.isNotEmpty && caaId.isNotEmpty) {
            caaUrl = 'https://coverartarchive.org/release/$caaRel/$caaId-250.jpg';
          }
        }

        out[mbid] = MusicBrainzRecordingInfo(isrc: isrc, coverUrl: caaUrl);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<MusicBrainzRecordingInfo?> _fetchMusicBrainzSingle(String mbid) async {
    try {
      final resp = await _client.get(
        Uri.parse(
            'https://musicbrainz.org/ws/2/recording/$mbid?inc=isrcs&fmt=json'),
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      );
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      String? isrc;
      final isrcs = data['isrcs'] as List<dynamic>? ?? const [];
      for (final item in isrcs) {
        final v = item?.toString().trim() ?? '';
        if (v.isNotEmpty) {
          isrc = v;
          break;
        }
      }

      String? coverUrl;
      if (isrc != null) {
        coverUrl = await resolveDeezerCover(isrc: isrc);
      }

      return MusicBrainzRecordingInfo(isrc: isrc, coverUrl: coverUrl);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchDeezerCoverByIsrc(String isrc) async {
    try {
      final resp = await _client.get(
        Uri.parse('https://api.deezer.com/track/isrc:$isrc'),
      );
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['error'] != null) return null;
      final album = data['album'];
      if (album is Map) {
        return (album['cover_medium'] ?? album['cover_big'] ?? album['cover'])
            ?.toString();
      }
    } catch (_) {}
    return null;
  }
}
