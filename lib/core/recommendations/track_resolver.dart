import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../models/addon_models.dart';
import '../models/models.dart';
import '../services/addon_service.dart';
import '../utils/hive/hive_provider.dart';
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
  );
}

/// Turns a [RecTrack] (just a title and artist) into a playable [Track] by
/// searching the active addon. Results, including misses, are cached on disk.
class TrackResolver {
  static const _boxName = 'rec_resolve';
  static const _hitTtl = Duration(days: 7);
  static const _missTtl = Duration(days: 1);
  static const _maxConcurrentSearches = 4;

  final AddonService _addons;
  Box? _box;

  /// Same key resolved twice at once shares one search.
  final Map<String, Future<Track?>> _inflight = {};

  int _activeSearches = 0;
  final Queue<Completer<void>> _waiters = Queue();

  TrackResolver(this._addons);

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  String _cacheKey(RecTrack rec) => '${_addons.activeAddonId}|${rec.key}';

  /// Resolves one track. Returns null when no good match exists or the search
  /// failed. Failures are not cached; "no match" results are.
  Future<Track?> resolve(RecTrack rec) {
    final key = _cacheKey(rec);
    return _inflight.putIfAbsent(key, () async {
      try {
        return await _resolveUncached(rec, key);
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
    Future<void> worker() async {
      while (!cancelled && next < recs.length) {
        final i = next++;
        final track = await resolve(recs[i]);
        if (!cancelled && !controller.isClosed) controller.add((i, track));
      }
    }

    () async {
      final workers = recs.length < _maxConcurrentSearches
          ? recs.length
          : _maxConcurrentSearches;
      await Future.wait(List.generate(workers, (_) => worker()));
      if (!controller.isClosed) await controller.close();
    }();

    return controller.stream;
  }

  Future<Track?> _resolveUncached(RecTrack rec, String key) async {
    final cached = _readCache(key);
    if (cached != null) return cached.track;

    await _acquire();
    try {
      final result = await _addons.search('${rec.title} ${rec.artist}', limit: 5);
      // null means no active addon or a failed request: don't cache that.
      if (result == null) return null;

      AddonTrack? best;
      var bestScore = 0.0;
      for (final candidate in result.tracks) {
        final score = scoreMatch(rec, candidate.title, candidate.artist);
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }

      final track =
          (best != null && bestScore >= kMatchThreshold) ? trackFromAddon(best) : null;
      await _writeCache(key, track);
      return track;
    } catch (e) {
      print('Track resolve error for "${rec.title}" by ${rec.artist}: $e');
      return null;
    } finally {
      _release();
    }
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
