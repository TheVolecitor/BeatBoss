import 'package:flutter/foundation.dart';

import '../../core/models/addon_models.dart';
import '../../core/models/models.dart';
import '../../core/recommendations/rec_models.dart';
import '../../core/recommendations/recommendation_service.dart';
import '../../core/recommendations/resolved_shelf.dart';
import '../../core/recommendations/track_resolver.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/history_service.dart';
import '../../core/services/last_fm_service.dart';
import '../../core/services/listenbrainz_service.dart';
import '../../core/services/settings_service.dart';

/// Genres shown when the user has no Last.fm login.
const kLoggedOutTags = ['pop', 'rock', 'hip-hop'];

/// Holds everything the home screen shows: the addon catalog and the
/// recommendation shelves. Shelves are shown from the on-disk cache first and
/// refreshed in the background; their songs are looked up in the addon one by
/// one (see [ResolvedShelf]).
class HomeController extends ChangeNotifier {
  /// Songs resolved per home shelf. The mix screen resolves them all.
  static const _shelfLimit = 16;

  final RecommendationService recs;
  final SettingsService settings;
  final LastFmService lastFm;
  final ListenBrainzService? listenBrainz;
  final AddonService addons;
  final HistoryService history;

  String chartRange = 'week';
  bool get supportsChartRanges => recs.active.id == 'listenbrainz';

  // Addon catalog
  List<Track> catalogTracks = [];
  List<AddonAlbum> catalogAlbums = [];
  List<AddonPlaylist> catalogPlaylists = [];

  // Personal shelves
  late final ResolvedShelf recommended = _newShelf();
  late final ResolvedShelf mix = _newShelf();
  late final ResolvedShelf library = _newShelf();
  List<ResolvedShelf> artistMixes = [];

  // History-based and public shelves
  List<ResolvedShelf> because = [];
  RecShelf? fans;
  late final ResolvedShelf charts = _newShelf();
  final Map<String, ResolvedShelf> tags = {};

  bool loading = false;
  bool _disposed = false;
  bool _reloadQueued = false;
  String _signature = '';
  String? _addonId;

  HomeController({
    required this.recs,
    required this.settings,
    required this.lastFm,
    this.listenBrainz,
    required this.addons,
    required this.history,
  });

  ResolvedShelf _newShelf() => ResolvedShelf(recs.resolver, limit: _shelfLimit);

  /// Personal recommendations are available (switched on and logged in).
  bool get personal => recs.canRecommend;
  bool get sourceEnabled => recs.sourceEnabled;

  /// A short string that changes whenever the set of shelves should change.
  String get _currentSignature => [
        recs.canRecommend,
        recs.sourceEnabled,
        recs.active.id,
        settings.useAddonCatalogRecommendations,
      ].join('|');

  List<ResolvedShelf> get _allShelves => [
        recommended,
        mix,
        library,
        ...artistMixes,
        ...because,
        charts,
        ...tags.values,
      ];

  bool get hasAnyContent =>
      catalogTracks.isNotEmpty ||
      catalogAlbums.isNotEmpty ||
      catalogPlaylists.isNotEmpty ||
      _allShelves.any((s) => s.hasData) ||
      (fans != null && !fans!.isEmpty);

  /// The artist the "Fans also like" shelf is about.
  String? get fansArtist => _fansArtist;
  String? _fansArtist;

  void start() {
    _signature = _currentSignature;
    _addonId = addons.activeAddonId;
    lastFm.addListener(_onSourceChanged);
    listenBrainz?.addListener(_onSourceChanged);
    settings.addListener(_onSourceChanged);
    addons.addListener(_onAddonChanged);
    _showCached();
    refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    lastFm.removeListener(_onSourceChanged);
    listenBrainz?.removeListener(_onSourceChanged);
    settings.removeListener(_onSourceChanged);
    addons.removeListener(_onAddonChanged);
    for (final s in _allShelves) {
      s.dispose();
    }
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- Reacting to settings, login and addon changes ----

  void _onSourceChanged() {
    if (_disposed) return;
    final signature = _currentSignature;
    if (signature == _signature) return;
    _signature = signature;
    _showCached();
    if (loading) {
      _reloadQueued = true;
    } else {
      refresh();
    }
  }

  void _onAddonChanged() {
    if (_disposed) return;
    final id = addons.activeAddonId;
    if (id == _addonId) return;
    _addonId = id;
    // Songs have to be found again in the new addon.
    for (final s in _allShelves) {
      if (s.shelf != null) s.setShelf(s.shelf, force: true);
    }
    if (loading) {
      _reloadQueued = true;
    } else {
      refresh();
    }
  }

  // ---- Cache ----

  /// Shows whatever is cached right now, without any network call.
  void _showCached() {
    recommended.setShelf(recs.cachedRecommendedShelf);
    mix.setShelf(recs.canRecommend
        ? recs.cachedShelf(RecommendationService.mixShelfId)
        : null);
    library.setShelf(recs.canRecommend
        ? recs.cachedShelf(RecommendationService.libraryShelfId)
        : null);
    _setList(artistMixes, recs.cachedArtistMixShelves, (l) => artistMixes = l);

    _setList(
        because,
        _becauseSeeds().map(recs.cachedBecause).whereType<RecShelf>().toList(),
        (l) => because = l);
    _fansArtist = _pickFansArtist(
        recs.cachedShelf(RecommendationService.topArtistsShelfId));
    fans = _fansArtist == null ? null : recs.cachedSimilarArtists(_fansArtist!);
    charts.setShelf(recs.cachedChartsShelfFor(chartRange));
    if (!personal) {
      for (final tag in kLoggedOutTags) {
        _tagShelf(tag).setShelf(recs.cachedTagShelf(tag));
      }
    }

    if (!settings.useAddonCatalogRecommendations) {
      catalogTracks = [];
      catalogAlbums = [];
      catalogPlaylists = [];
    }
    _notify();
  }

  ResolvedShelf _tagShelf(String tag) =>
      tags.putIfAbsent(tag, () => _newShelf());

  /// Makes [target] hold exactly [shelves] (reusing its [ResolvedShelf]s).
  void _setList(List<ResolvedShelf> target, List<RecShelf> shelves,
      void Function(List<ResolvedShelf>) assign) {
    final next = <ResolvedShelf>[];
    for (var i = 0; i < shelves.length; i++) {
      final holder = i < target.length ? target[i] : _newShelf();
      holder.setShelf(shelves[i]);
      next.add(holder);
    }
    for (var i = shelves.length; i < target.length; i++) {
      target[i].dispose();
    }
    assign(next);
  }

  // ---- Refresh ----

  /// Loads every shelf. Cached shelves younger than 6 hours are reused unless
  /// [force] is set (pull to refresh).
  Future<void> refresh({bool force = false}) async {
    if (loading || _disposed) return;
    loading = true;
    _notify();
    try {
      await Future.wait([
        _loadCatalog(),
        if (recs.sourceEnabled) _loadPersonal(force),
        if (recs.sourceEnabled) _loadPublic(force),
      ]);
    } catch (e) {
      print('Home refresh failed: $e');
    } finally {
      loading = false;
      _notify();
      if (_reloadQueued && !_disposed) {
        _reloadQueued = false;
        refresh();
      }
    }
  }

  Future<void> _loadCatalog() async {
    if (!settings.useAddonCatalogRecommendations) return;
    try {
      final catalog = await addons.getCatalog();
      if (_disposed || !settings.useAddonCatalogRecommendations) return;
      catalogTracks = catalog?.tracks.map(trackFromAddon).toList() ?? [];
      catalogAlbums = catalog?.albums ?? [];
      catalogPlaylists = catalog?.playlists ?? [];
      _notify();
    } catch (e) {
      print('Error fetching catalog: $e');
    }
  }

  Future<void> _loadPersonal(bool force) async {
    if (!recs.canRecommend) return;
    void applyPersonal(ResolvedShelf target, RecShelf? shelf) {
      if (_disposed || !recs.canRecommend) return;
      target.setShelf(shelf);
    }

    await Future.wait([
      recs.recommendedShelf(force: force).then((s) => applyPersonal(recommended, s)),
      recs.mixShelf(force: force).then((s) => applyPersonal(mix, s)),
      recs.libraryShelf(force: force).then((s) => applyPersonal(library, s)),
      recs.artistMixShelves(force: force).then((shelves) {
        if (_disposed || !recs.canRecommend) return;
        _setList(artistMixes, shelves, (l) => artistMixes = l);
        _notify();
      }),
    ]);
  }

  Future<void> setChartRange(String range) async {
    if (chartRange == range || _disposed) return;
    chartRange = range;
    charts.setShelf(recs.cachedChartsShelfFor(range));
    _notify();
    final shelf = await recs.chartsShelf(range: range);
    if (!_disposed && chartRange == range) {
      charts.setShelf(shelf);
    }
  }

  /// Shelves that don't need a login: because-you-listened, fans-also-like,
  /// charts and (logged out only) genre tags.
  Future<void> _loadPublic(bool force) async {
    await Future.wait([
      _loadBecause(force),
      _loadFans(force),
      recs.chartsShelf(force: force, range: chartRange).then(charts.setShelf),
      if (!personal)
        for (final tag in kLoggedOutTags)
          recs.tagShelf(tag, force: force).then(_tagShelf(tag).setShelf),
    ]);
  }

  /// The two most recent songs by different artists.
  List<Track> _becauseSeeds() {
    final seeds = <Track>[];
    final artists = <String>{};
    for (final t in history.recentlyPlayed) {
      if (artists.add(primaryArtist(t.artist).toLowerCase())) seeds.add(t);
      if (seeds.length == 2) break;
    }
    return seeds;
  }

  Future<void> _loadBecause(bool force) async {
    final shelves = (await Future.wait(_becauseSeeds()
            .map((s) => recs.becauseYouListened(s, force: force))))
        .whereType<RecShelf>()
        .toList();
    if (_disposed) return;
    _setList(because, shelves, (l) => because = l);
    _notify();
  }

  String? _pickFansArtist(RecShelf? topArtists) {
    if (personal && topArtists != null && topArtists.artists.isNotEmpty) {
      return topArtists.artists.first.name;
    }
    if (history.recentlyPlayed.isNotEmpty) {
      return primaryArtist(history.recentlyPlayed.first.artist);
    }
    return null;
  }

  Future<void> _loadFans(bool force) async {
    final top = personal ? await recs.topArtistsShelf(force: force) : null;
    final artist = _pickFansArtist(top);
    _fansArtist = artist;
    if (artist == null) {
      fans = null;
    } else {
      final shelf = await recs.similarArtistsShelf(artist, force: force);
      if (_disposed) return;
      fans = shelf;
    }
    _notify();
  }
}
