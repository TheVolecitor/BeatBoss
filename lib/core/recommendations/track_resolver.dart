import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../models/addon_models.dart';
import '../models/models.dart';
import '../services/addon_service.dart';
import '../utils/hive/hive_provider.dart';
import 'musicbrainz_lookup.dart';
import 'rec_models.dart';
import 'track_matching.dart';

export 'track_matching.dart';

/// Maps an addon search/catalog hit to the app's [Track].
Track trackFromAddon(AddonTrack at) {
  return Track(
    id: at.id,
    title: at.title,
    artist: at.artist,
    albumTitle: at.album,
    albumCover: at.artworkURL,
    duration: at.duration,
    addonId: at.addonId,
    addonTrackId: at.id,
    streamURL: at.streamURL,
    isrc: at.isrc,
  );
}

/// Turns a [RecTrack] (just a title and artist) into a playable [Track] by
/// searching the active addon. Results, including misses, are cached on disk.
class TrackResolver {
  static const _boxName = 'rec_resolve';
  static const _hitTtl = Duration(days: 7);
  static const _missTtl = Duration(days: 1);
  static const _coverTtl = Duration(hours: 6);
  static const _maxConcurrentSearches = 4;

  final AddonService _addons;
  final MusicBrainzLookup _mbLookup;
  Box? _box;

  /// Same key resolved twice at once shares one search.
  final Map<String, Future<Track?>> _inflight = {};

  int _activeSearches = 0;
  final Queue<Completer<void>> _waiters = Queue();

  TrackResolver(this._addons, {MusicBrainzLookup? mbLookup})
      : _mbLookup = mbLookup ?? MusicBrainzLookup();

  /// Bulk-resolves ISRCs for [mbids] via MusicBrainz without touching any addon.
  Future<Map<String, MusicBrainzRecordingInfo>> lookupMbidsBulk(
          List<String> mbids) =>
      _mbLookup.lookupRecordingsBulk(mbids);

  /// Resolves cover art via Deezer (by ISRC or title+artist) without auth.
  Future<String?> resolveDeezerCover({
    String? isrc,
    String? title,
    String? artist,
  }) =>
      _mbLookup.resolveDeezerCover(
        isrc: isrc,
        title: title,
        artist: artist,
      );

  /// Resolves a cover URL from a MusicBrainz recording MBID without touching
  /// the active addon.
  Future<String?> resolveCoverFromMbid(String mbid) async {
    final info = await _mbLookup.lookupRecording(mbid);
    return info?.coverUrl;
  }

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// The addon searches go to (for log messages).
  String? get activeAddonId => _addons.activeAddonId;

  String _cacheKey(RecTrack rec, String? addonId) => '${addonId ?? 'none'}|${rec.key}';

  /// Resolves one track. Returns null when no good match exists or the search
  /// failed. Failures are not cached; "no match" results are.
  Future<Track?> resolve(RecTrack rec) {
    final addonId = _addons.activeAddonId;
    final key = _cacheKey(rec, addonId);
    return _inflight.putIfAbsent(key, () async {
      try {
        return await _resolveUncached(rec, key, addonId);
      } finally {
        _inflight.remove(key);
      }
    });
  }

  /// Resolves [recs] with at most 4 searches at a time and emits
  /// `(index, track)` as each one finishes. Cancelling the subscription stops
  /// any searches that haven't started yet.
  Stream<(int, Track?)> resolveMany(List<RecTrack> recs) {
    final controller = StreamController<(int, Track?)>();
    var cancelled = false;
    controller.onCancel = () => cancelled = true;

    var next = 0;
    Future<void> worker(List<RecTrack> items) async {
      while (!cancelled && next < items.length) {
        final i = next++;
        final track = await resolve(items[i]);
        if (!cancelled && !controller.isClosed) controller.add((i, track));
      }
    }

    () async {
      // Pre-batch MBID -> ISRC + cover via ListenBrainz (30 MBIDs per 1.5s)
      // so MixScreen ("See all") doesn't fall back to per-track MusicBrainz
      // calls.
      final mbids = <String>[
        for (final r in recs)
          if ((r.isrc == null || r.isrc!.trim().isEmpty) &&
              r.mbid != null &&
              r.mbid!.trim().isNotEmpty)
            r.mbid!.trim(),
      ];
      var enrichedRecs = recs;
      if (mbids.isNotEmpty) {
        final bulk = await _mbLookup.lookupRecordingsBulk(mbids);
        if (cancelled) return;
        enrichedRecs = [
          for (final r in recs)
            if (r.mbid != null && bulk.containsKey(r.mbid!.trim()))
              r.copyWith(
                isrc: (r.isrc == null || r.isrc!.trim().isEmpty)
                    ? bulk[r.mbid!.trim()]!.isrc
                    : r.isrc,
                imageUrl: (r.imageUrl == null || r.imageUrl!.isEmpty)
                    ? bulk[r.mbid!.trim()]!.coverUrl
                    : r.imageUrl,
              )
            else
              r,
        ];
      }

      final workers = enrichedRecs.length < _maxConcurrentSearches
          ? enrichedRecs.length
          : _maxConcurrentSearches;
      await Future.wait(List.generate(workers, (_) => worker(enrichedRecs)));
      if (!controller.isClosed) await controller.close();
    }();

    return controller.stream;
  }

  Future<Track?> _resolveUncached(RecTrack rec, String key, String? addonId) async {
    final cached = _readCache(key);
    if (cached != null) return cached.track;

    await _acquire();
    try {
      var enriched = rec;
      // 0. If we have a MusicBrainz recording MBID and the addon supports ISRC
      //    resolution, look up the ISRC from MusicBrainz first.
      if ((enriched.isrc == null || enriched.isrc!.trim().isEmpty) &&
          enriched.mbid != null &&
          enriched.mbid!.isNotEmpty &&
          (_addons.supportsIsrcFor(addonId) ||
              _addons.supportsResolveFor(addonId))) {
        final mbInfo = await _mbLookup.lookupRecording(enriched.mbid!);
        if (mbInfo != null) {
          enriched = enriched.copyWith(
            isrc: mbInfo.isrc ?? enriched.isrc,
            imageUrl: enriched.imageUrl ?? mbInfo.coverUrl,
          );
        }
      }

      // 1. Eclipse /resolve endpoint (uses ISRC when known, or title+artist+durationMs)
      final exact = await _addons.resolveTrack(enriched, addonId: addonId);
      if (exact.handled) {
        final track = exact.track != null ? trackFromAddon(exact.track!) : null;
        await _writeCache(key, track);
        return track;
      }

      // 2. Eclipse /resolve-isrc?isrc=... lookup when ISRC is known
      final recIsrc = enriched.isrc?.trim();
      if (recIsrc != null && recIsrc.isNotEmpty) {
        final isrcTrackId = await _addons.resolveIsrc(recIsrc, addonId: addonId);
        if (isrcTrackId != null) {
          var cover = enriched.imageUrl;
          if (cover == null || cover.isEmpty) {
            cover = await _mbLookup.resolveDeezerCover(
              isrc: recIsrc,
              title: enriched.title,
              artist: enriched.artist,
            );
          }
          final track = Track(
            id: isrcTrackId,
            title: enriched.title,
            artist: enriched.artist,
            albumTitle: enriched.album,
            albumCover: cover,
            duration: enriched.durationMs != null
                ? (enriched.durationMs! / 1000).round()
                : null,
            addonId: addonId,
            addonTrackId: isrcTrackId,
            isrc: recIsrc,
          );
          await _writeCache(key, track);
          return track;
        }
      }

      // 3. Fallback to /search, prioritizing ISRC match among results
      final result = await _addons.search(
        '${enriched.title} ${enriched.artist}',
        limit: 5,
        addonId: addonId,
      );
      // null means no active addon or a failed request: don't cache that.
      if (result == null) return null;

      AddonTrack? best;
      var bestScore = 0.0;
      for (final candidate in result.tracks) {
        final score = scoreMatch(
          enriched,
          candidate.title,
          candidate.artist,
          candidateIsrc: candidate.isrc,
        );
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }

      Track? track;
      if (best != null && bestScore >= kMatchThreshold) {
        final base = trackFromAddon(best);
        final fallbackCover = enriched.imageUrl;
        track = (base.albumCover == null || base.albumCover!.isEmpty) &&
                fallbackCover != null &&
                fallbackCover.isNotEmpty
            ? Track(
                id: base.id,
                title: base.title,
                artist: base.artist,
                albumTitle: base.albumTitle,
                albumCover: fallbackCover,
                duration: base.duration,
                addonId: base.addonId,
                addonTrackId: base.addonTrackId,
                streamURL: base.streamURL,
                isrc: base.isrc,
              )
            : base;
      }
      await _writeCache(key, track);
      return track;
    } catch (e) {
      print('Track resolve error for "${rec.title}" by ${rec.artist}: $e');
      return null;
    } finally {
      _release();
    }
  }

  /// Returns cached cover art / ISRC for [recKey] if younger than 6 hours.
  ({String? imageUrl, String? isrc})? getCachedCover(String recKey) {
    final raw = _box?.get('cover:$recKey');
    if (raw is! String) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch((data['at'] as num).toInt());
      if (DateTime.now().difference(at) > _coverTtl) return null;
      return (
        imageUrl: data['img']?.toString(),
        isrc: data['isrc']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Caches resolved cover art / ISRC for [recKey] for 6 hours.
  Future<void> cacheCover(String recKey, {String? imageUrl, String? isrc}) async {
    try {
      await _box?.put(
        'cover:$recKey',
        jsonEncode({
          'img': imageUrl,
          'isrc': isrc,
          'at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  ({Track? track})? _readCache(String key) {
    final raw = _box?.get(key);
    if (raw is! String) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch((data['at'] as num).toInt());
      final t = data['t'];
      final ttl = t == null ? _missTtl : _hitTtl;
      if (DateTime.now().difference(at) > ttl) return null;
      return (track: t == null ? null : Track.fromJson(Map<String, dynamic>.from(t as Map)));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, Track? track) async {
    try {
      await _box?.put(
        key,
        jsonEncode({
          't': track?.toJson(),
          'at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      print('Track resolve cache write error: $e');
    }
  }

  Future<void> _acquire() {
    if (_activeSearches < _maxConcurrentSearches) {
      _activeSearches++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // Hand the slot straight to the next waiter.
      _waiters.removeFirst().complete();
    } else {
      _activeSearches--;
    }
  }
}
