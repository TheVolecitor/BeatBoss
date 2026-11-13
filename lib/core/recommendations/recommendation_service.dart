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

  /// The user switched on personal recommendations in Settings.
  bool get enabled => _settings.useLastFmRecommendations;

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

    try {
      final fresh = await build();
      if (fresh.isEmpty) return cached ?? fresh;
      await _box?.put(_boxKey(id), jsonEncode(fresh.toJson()));
      notifyListeners();
      return fresh;
    } catch (e) {
      print('Recommendation shelf "$id" failed: $e');
      return cached;
    }
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

  /// Tracks similar to [seed], used for autoplay and song radio.
  Future<List<RecTrack>> similarTo(Track seed, {int limit = 50}) =>
      active.similarTracks(seed.artist, seed.title, limit: limit);

  /// Removes every cached shelf (call on logout so personal data doesn't
  /// outlive the session).
  Future<void> clearShelves() async {
    await _box?.clear();
    notifyListeners();
  }

  List<RecTrack> _dedupe(List<RecTrack> tracks) {
    final seen = <String>{};
    return tracks.where((t) => seen.add(t.key)).toList();
  }
}
