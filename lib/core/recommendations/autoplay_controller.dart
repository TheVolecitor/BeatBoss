import 'dart:async';
import 'dart:math';

import '../models/models.dart';
import '../services/history_service.dart';
import 'rec_models.dart';
import 'recommendation_service.dart';
import 'track_matching.dart';

/// Drops candidates that were already seen (by [matchKey]) and keeps at most
/// [perArtist] tracks per artist, preserving the input order.
List<RecTrack> filterCandidates(
  List<RecTrack> candidates,
  Set<String> exclude, {
  int perArtist = 2,
}) {
  final seen = <String>{};
  final perArtistCount = <String, int>{};
  final result = <RecTrack>[];
  for (final c in candidates) {
    final key = matchKey(c.artist, c.title);
    if (exclude.contains(key) || !seen.add(key)) continue;
    final artistKey = normalizeForMatch(c.artist);
    final n = perArtistCount[artistKey] ?? 0;
    if (n >= perArtist) continue;
    perArtistCount[artistKey] = n + 1;
    result.add(c);
  }
  return result;
}

/// Finds playable songs similar to what the user is listening to, to keep the
/// queue going (autoplay) or to fill a song radio.
class AutoplayController {
  final RecommendationService recs;
  final HistoryService history;
  final Random _random;

  AutoplayController({
    required this.recs,
    required this.history,
    Random? random,
  }) : _random = random ?? Random();

  /// Returns up to [want] playable tracks that are not already in [queue] or
  /// in the last 50 played. [seeds] are the songs the user chose themselves,
  /// in the order to try them: the first one that yields songs wins, so the
  /// caller decides which seed leads (and can rotate them between batches).
  /// Returns an empty list when nothing suitable was found.
  Future<List<Track>> nextBatch({
    required List<Track> seeds,
    required List<Track> queue,
    int want = 8,
  }) async {
    if (seeds.isEmpty) return const [];
    try {
      return await _nextBatch(seeds, queue, want).timeout(_timeout);
    } on TimeoutException {
      print('[Autoplay] timed out after ${_timeout.inSeconds}s');
      return const [];
    } catch (e) {
      print('[Autoplay] error: $e');
      return const [];
    }
  }

  /// A slow or stuck search must not keep the queue waiting forever.
  static const _timeout = Duration(seconds: 45);

  Future<List<Track>> _nextBatch(
      List<Track> seeds, List<Track> queue, int want) async {
    for (final seed in seeds.take(3)) {
      final batch = await _batchForSeed(seed, queue, want);
      if (batch.isNotEmpty) return batch;
      print('[Autoplay] nothing for "${seed.title}", trying the next seed');
    }
    return const [];
  }

  Future<List<Track>> _batchForSeed(
      Track seed, List<Track> queue, int want) async {
    final exclude = <String>{
      for (final t in queue) matchKey(t.artist, t.title),
      for (final t in history.recentlyPlayed.take(50))
        matchKey(t.artist, t.title),
    };

    // Aim above `want`: some candidates won't be found in the addon.
    final target = want * 3;
    final provider = recs.active;

    // 1. Songs similar to the seed.
    final similar = await recs.similarTo(seed, limit: 50);
    var pool = filterCandidates(similar, exclude);
    print('[Autoplay] "${seed.title}" by ${seed.artist}: '
        '${similar.length} similar songs, ${pool.length} usable');

    // 2. Top songs of artists similar to the seed's artist.
    if (pool.length < target) {
      final artists = await recs.similarArtistsOf(seed.artist, limit: 5);
      for (final artist in artists.take(3)) {
        if (!recs.sourceEnabled) break;
        final top = await provider.artistTopTracks(artist.name, limit: 10);
        pool = filterCandidates([...pool, ...top], exclude);
        if (pool.length >= target) break;
      }
      print('[Autoplay] after similar artists: ${pool.length} usable');
    }

    // Shuffle the best matches a little so the radio isn't identical each time.
    final head = pool.take(30).toList()..shuffle(_random);
    pool = [...head, ...pool.skip(30)];

    final result = <Track>[];
    final taken = <String>{};
    var tried = 0;

    Future<void> resolveFrom(List<RecTrack> candidates) async {
      await for (final (_, track) in recs.resolver.resolveMany(candidates)) {
        tried++;
        if (track == null) continue;
        final key = matchKey(track.artist, track.title);
        if (exclude.contains(key) || !taken.add(key)) continue;
        result.add(track);
        if (result.length >= want) break; // cancels the remaining searches
      }
    }

    if (pool.isNotEmpty) {
      await resolveFrom(pool);
    }

    // 3. The seed artist's own top songs, if playable results are still short.
    if (result.length < want && recs.sourceEnabled) {
      final seenPool = {
        for (final c in pool) matchKey(c.artist, c.title),
      };
      final top = await recs.topTracksOf(seed.artist, limit: 20);
      final extra = filterCandidates(top, {...exclude, ...seenPool});
      print('[Autoplay] after the artist\'s top songs: ${extra.length} usable');
      if (extra.isNotEmpty) {
        await resolveFrom(extra);
      }
    }

    if (result.isEmpty && pool.isEmpty) return const [];
    print('[Autoplay] found ${result.length} playable songs '
        'after searching for $tried (active addon: ${recs.resolver.activeAddonId})');
    return result;
  }
}
