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

  /// The user's personal recommendations (up to 50 tracks). Null when
  /// recommendations are off or the user is not logged in.
  Future<RecShelf?> recommendedShelf({bool force = false}) async {
    if (!canRecommend) return null;
    final provider = active;
    return loadShelf(
      recommendedShelfId,
      force: force,
      build: () async {
        final tracks = await provider.station(StationKind.recommended);
        return RecShelf(
          id: recommendedShelfId,
          title: 'Recommended for you',
          tracks: _dedupe(tracks).take(50).toList(),
          fetchedAt: DateTime.now(),
        );
      },
    );
  }

  /// Tracks similar to [seed], used for autoplay and song radio. Addon names
  /// are often decorated, so cleaned-up variants are tried when the original
  /// isn't recognised.
  Future<List<RecTrack>> similarTo(Track seed, {int limit = 50}) async {
    if (!sourceEnabled) return const [];
    for (final v in lookupVariants(seed.artist, seed.title)) {
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
