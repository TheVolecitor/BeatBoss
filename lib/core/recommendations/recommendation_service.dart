import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/addon_service.dart';
import '../services/settings_service.dart';
import '../utils/hive/hive_provider.dart';
import 'rec_models.dart';
import 'recommendation_provider.dart';
import 'track_resolver.dart';

/// Single entry point for recommendations. Picks the active
/// [RecommendationProvider], caches shelves on disk and owns the
/// [TrackResolver] that makes recommendations playable.
class RecommendationService extends ChangeNotifier {
  static const _shelvesBoxName = 'rec_shelves';
  static const shelfTtl = Duration(hours: 6);

  /// Id of the "recommended for you" shelf.
  static const recommendedShelfId = 'station_recommended';
  static const mixShelfId = 'station_mix';
  static const libraryShelfId = 'station_library';
  static const topArtistsShelfId = 'top_artists';
  static const chartsShelfId = 'charts';

  final SettingsService _settings;
  final List<RecommendationProvider> _providers;
  final TrackResolver resolver;
  Box? _box;
  int _shelfGeneration = 0;

  RecommendationService({
    required SettingsService settings,
    required AddonService addons,
    required List<RecommendationProvider> providers,
  })  : _settings = settings,
        _providers = providers,
        resolver = TrackResolver(addons);

  Future<void> init() async {
    _box = await Hive.openBox(_shelvesBoxName);
    await resolver.init();
  }

  List<RecommendationProvider> get providers => List.unmodifiable(_providers);

  RecommendationProvider get active => _providers.firstWhere(
        (p) => p.id == _settings.recProviderId,
        orElse: () => _providers.first,
      );

  /// A recommendation source is switched on in Settings (not "Off").
  bool get sourceEnabled => _settings.recSourceEnabled;

  /// The user switched on personal recommendations in Settings (and a source
  /// is on).
  bool get enabled => sourceEnabled && _settings.useLastFmRecommendations;

  /// Personal recommendations are switched on and the provider has a login.
  bool get canRecommend => enabled && active.isLoggedIn;

  String _boxKey(String id) => '${active.id}:$id';

  RecShelf? cachedShelf(String id) {
    final raw = _box?.get(_boxKey(id));
    if (raw is! String) return null;
    try {
      return RecShelf.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// The cached "recommended for you" shelf, or null when recommendations are
  /// off or the user is logged out (so stale personal data is never shown).
  RecShelf? get cachedRecommendedShelf =>
      canRecommend ? cachedShelf(recommendedShelfId) : null;

  /// Returns the cached shelf when it is younger than [shelfTtl] (and [force]
  /// is false); otherwise builds, saves and returns a fresh one. If the build
  /// fails or comes back empty, the old cached shelf is kept and returned.
  Future<RecShelf?> loadShelf(
    String id, {
    bool force = false,
    required Future<RecShelf> Function() build,
  }) async {
    final cached = cachedShelf(id);
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < shelfTtl) {
      return cached;
    }

    final generation = _shelfGeneration;
    RecShelf fresh;
    try {
      fresh = await build();
    } catch (e) {
      print('Recommendation shelf "$id" build failed: $e');
      return cached;
    }

    if (fresh.isEmpty) return cached ?? fresh;
    if (generation != _shelfGeneration) return null;

    try {
      await _box?.put(_boxKey(id), jsonEncode(fresh.toJson()));
    } catch (e) {
      print('Recommendation shelf "$id" cache write failed: $e');
    }
    notifyListeners();
    return fresh;
  }

  /// Builds a track shelf from [fetch] and caches it. [fetch] only runs when
  /// the cached shelf is missing, stale or [force] is set.
  Future<RecShelf?> _trackShelf(
    String id,
    String title, {
    String? subtitle,
    required bool force,
    int max = 50,
    required Future<List<RecTrack>> Function() fetch,
  }) {
    return loadShelf(
      id,
      force: force,
      build: () async => RecShelf(
        id: id,
        title: title,
        subtitle: subtitle,
        tracks: _dedupe(await fetch()).take(max).toList(),
        fetchedAt: DateTime.now(),
      ),
    );
  }

  /// The user's personal recommendations (up to 50 tracks). Null when
  /// recommendations are off or the user is not logged in.
  Future<RecShelf?> recommendedShelf({bool force = false}) async {
    if (!canRecommend) return null;
    return _trackShelf(
      recommendedShelfId,
      'Recommended for you',
      subtitle: 'Picked from your listening',
      force: force,
      fetch: () => active.station(StationKind.recommended),
    );
  }

  /// The provider's "mix" station. Needs a login.
  Future<RecShelf?> mixShelf({bool force = false}) async {
    if (!canRecommend) return null;
    return _trackShelf(
      mixShelfId,
      'Your mix',
      subtitle: 'Songs you know and new ones',
      force: force,
      fetch: () => active.station(StationKind.mix),
    );
  }

  /// The provider's "library" station. Needs a login.
  Future<RecShelf?> libraryShelf({bool force = false}) async {
    if (!canRecommend) return null;
    return _trackShelf(
      libraryShelfId,
      'Your library',
      subtitle: 'Your favourites on repeat',
      force: force,
      fetch: () => active.station(StationKind.library),
    );
  }

  /// The artists the user listened to most lately (cached like a shelf).
  Future<RecShelf?> topArtistsShelf({bool force = false}) async {
    if (!canRecommend) return null;
    return loadShelf(
      topArtistsShelfId,
      force: force,
      build: () async => RecShelf(
        id: topArtistsShelfId,
        title: 'Your top artists',
        kind: ShelfKind.artists,
        artists: await active.userTopArtists(period: '3month', limit: 10),
        fetchedAt: DateTime.now(),
      ),
    );
  }

  /// "<Artist> Mix" shelves for the user's top 3 artists: the artist's top
  /// tracks interleaved with songs similar to the best one.
  Future<List<RecShelf>> artistMixShelves({bool force = false}) async {
    final top = await topArtistsShelf(force: force);
    if (top == null) return const [];
    final shelves = await Future.wait(
      top.artists.take(3).map((a) => artistMixShelf(a.name, force: force)),
    );
    return shelves.whereType<RecShelf>().toList();
  }

  /// The cached artist mixes, without any network call.
  List<RecShelf> get cachedArtistMixShelves {
    if (!canRecommend) return const [];
    final top = cachedShelf(topArtistsShelfId);
    if (top == null) return const [];
    return top.artists
        .take(3)
        .map((a) => cachedShelf(artistMixShelfId(a.name)))
        .whereType<RecShelf>()
        .toList();
  }

  String artistMixShelfId(String artist) => 'artist_mix:${normalizeKeyPart(artist)}';

  Future<RecShelf?> artistMixShelf(String artist, {bool force = false}) {
    return _trackShelf(
      artistMixShelfId(artist),
      '$artist Mix',
      subtitle: 'Made from your top artists',
      force: force,
      fetch: () async {
        final top = await topTracksOf(artist, limit: 15);
        final similar = top.isEmpty
            ? const <RecTrack>[]
            : await similarTracksOf(top.first.artist, top.first.title, limit: 15);
        // Alternate between the artist's own songs and similar ones.
        final mixed = <RecTrack>[];
        for (var i = 0; i < top.length || i < similar.length; i++) {
          if (i < top.length) mixed.add(top[i]);
          if (i < similar.length) mixed.add(similar[i]);
        }
        return mixed;
      },
    );
  }

  String becauseShelfId(Track seed) => 'because:${matchKey(seed.artist, seed.title)}';

  /// Songs similar to [seed], shown as "Because you listened to ...".
  Future<RecShelf?> becauseYouListened(Track seed, {bool force = false}) async {
    if (!sourceEnabled) return null;
    return _trackShelf(
      becauseShelfId(seed),
      'Because you listened to ${seed.title}',
      force: force,
      max: 20,
      fetch: () => similarTracksOf(seed.artist, seed.title, limit: 20),
    );
  }

  RecShelf? cachedBecause(Track seed) =>
      sourceEnabled ? cachedShelf(becauseShelfId(seed)) : null;

  String similarArtistsShelfId(String artist) => 'fans:${normalizeKeyPart(artist)}';

  /// "Fans also like <artist>": artists similar to [artist].
  Future<RecShelf?> similarArtistsShelf(String artist, {bool force = false}) async {
    if (!sourceEnabled) return null;
    final id = similarArtistsShelfId(artist);
    return loadShelf(
      id,
      force: force,
      build: () async => RecShelf(
        id: id,
        title: 'Fans also like $artist',
        kind: ShelfKind.artists,
        artists: await similarArtistsOf(artist, limit: 20),
        fetchedAt: DateTime.now(),
      ),
    );
  }

  RecShelf? cachedSimilarArtists(String artist) =>
      sourceEnabled ? cachedShelf(similarArtistsShelfId(artist)) : null;

  /// What's popular right now. No login needed.
  Future<RecShelf?> chartsShelf({bool force = false}) async {
    if (!sourceEnabled) return null;
    return _trackShelf(
      chartsShelfId,
      'Top charts',
      force: force,
      max: 30,
      fetch: () => active.chartTopTracks(limit: 30),
    );
  }

  RecShelf? get cachedChartsShelf =>
      sourceEnabled ? cachedShelf(chartsShelfId) : null;

  /// More chart entries for the mix screen's "Load more".
  Future<List<RecTrack>> moreCharts(int page) async {
    if (!sourceEnabled) return const [];
    return active.chartTopTracks(limit: 30, page: page);
  }

  String tagShelfId(String tag) => 'tag:${normalizeKeyPart(tag)}';

  /// Top tracks for a genre or mood tag. No login needed.
  Future<RecShelf?> tagShelf(String tag, {bool force = false}) async {
    if (!sourceEnabled) return null;
    return _trackShelf(
      tagShelfId(tag),
      'Top $tag',
      force: force,
      max: 30,
      fetch: () => active.tagTopTracks(tag, limit: 30),
    );
  }

  RecShelf? cachedTagShelf(String tag) =>
      sourceEnabled ? cachedShelf(tagShelfId(tag)) : null;

  Future<List<RecTrack>> moreTagTracks(String tag, int page) async {
    if (!sourceEnabled) return const [];
    return active.tagTopTracks(tag, limit: 30, page: page);
  }

  /// The first of [artist]'s top tracks that the active addon can play, for
  /// starting an artist radio. Null when none of the first few can be found.
  Future<Track?> firstPlayableTopTrack(String artist) async {
    final top = await topTracksOf(artist, limit: 6);
    for (final rec in top) {
      final track = await resolver.resolve(rec);
      if (track != null) return track;
    }
    return null;
  }

  /// Tracks similar to [seed], used for autoplay and song radio.
  Future<List<RecTrack>> similarTo(Track seed, {int limit = 50}) =>
      similarTracksOf(seed.artist, seed.title, limit: limit);

  /// Tracks similar to a song. Addon names are often decorated, so
  /// cleaned-up variants are tried when the original isn't recognised.
  Future<List<RecTrack>> similarTracksOf(String artist, String title,
      {int limit = 50}) async {
    if (!sourceEnabled) return const [];
    for (final v in lookupVariants(artist, title)) {
      final found = await active.similarTracks(v.artist, v.title, limit: limit);
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  /// Artists similar to [artist] (any credit format).
  Future<List<RecArtist>> similarArtistsOf(String artist, {int limit = 20}) async {
    if (!sourceEnabled) return const [];
    for (final name in artistVariants(artist)) {
      final found = await active.similarArtists(name, limit: limit);
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  /// Top tracks of [artist] (any credit format).
  Future<List<RecTrack>> topTracksOf(String artist, {int limit = 30}) async {
    if (!sourceEnabled) return const [];
    for (final name in artistVariants(artist)) {
      final found = await active.artistTopTracks(name, limit: limit);
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  /// Removes every cached shelf (call on logout so personal data doesn't
  /// outlive the session).
  Future<void> clearShelves() async {
    _shelfGeneration++;
    await _box?.clear();
    notifyListeners();
  }

  List<RecTrack> _dedupe(List<RecTrack> tracks) {
    final seen = <String>{};
    return tracks.where((t) => seen.add(t.key)).toList();
  }
}
