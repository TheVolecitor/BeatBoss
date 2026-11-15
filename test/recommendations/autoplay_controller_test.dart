import 'dart:io';

import 'package:beatboss/core/models/addon_models.dart';
import 'package:beatboss/core/models/models.dart';
import 'package:beatboss/core/recommendations/autoplay_controller.dart';
import 'package:beatboss/core/recommendations/rec_models.dart';
import 'package:beatboss/core/recommendations/recommendation_provider.dart';
import 'package:beatboss/core/recommendations/recommendation_service.dart';
import 'package:beatboss/core/services/addon_service.dart';
import 'package:beatboss/core/services/history_service.dart';
import 'package:beatboss/core/services/settings_service.dart';
import 'package:beatboss/core/services/user_addon_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Canned recommendations, no network.
class _FakeProvider implements RecommendationProvider {
  List<RecTrack> similar = [];

  /// Similar songs per seed title; seeds not listed here get [similar].
  Map<String, List<RecTrack>> similarBySeed = {};
  List<RecArtist> artists = [];
  Map<String, List<RecTrack>> topTracks = {};

  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake';
  @override
  Set<RecCapability> get capabilities => RecCapability.values.toSet();
  @override
  bool get needsLogin => false;
  @override
  bool get isLoggedIn => true;

  @override
  Future<List<RecTrack>> similarTracks(String artist, String title,
          {int limit = 50}) async =>
      similarBySeed[title] ?? similar;
  @override
  Future<List<RecArtist>> similarArtists(String artist, {int limit = 20}) async =>
      artists;
  @override
  Future<List<RecTrack>> artistTopTracks(String artist,
          {int limit = 30, int page = 1}) async =>
      topTracks[artist] ?? [];
  @override
  Future<List<RecTrack>> station(StationKind kind) async => [];
  @override
  Future<List<RecArtist>> userTopArtists(
          {String period = '3month', int limit = 10}) async =>
      [];
  @override
  Future<List<RecTrack>> tagTopTracks(String tag,
          {int limit = 30, int page = 1}) async =>
      [];
  @override
  Future<List<RecTrack>> chartTopTracks({int limit = 50, int page = 1}) async =>
      [];
}

/// An addon whose catalog holds exactly the songs it is given.
class _FakeAddon extends UserAddonHandler {
  final Set<String> catalog = {}; // "title artist"

  @override
  AddonManifest get manifest => AddonManifest(
        id: 'fake',
        name: 'Fake',
        version: '1',
        resources: [AddonResource.search, AddonResource.stream],
        types: ['track'],
        contentType: AddonContentType.music,
        addonType: AddonType.user,
        installedAt: DateTime(2024),
      );

  @override
  Future<AddonSearchResult?> search(String query) async {
    if (!catalog.contains(query)) return AddonSearchResult();
    // Query is "title artist"; the artist is the last word in these tests.
    final i = query.lastIndexOf(' ');
    return AddonSearchResult(tracks: [
      AddonTrack(
        id: query,
        title: query.substring(0, i),
        artist: query.substring(i + 1),
        addonId: 'fake',
      ),
    ]);
  }

  @override
  Future<AddonStreamResult?> getStreamResult(String trackId) async => null;
}

RecTrack rec(String title, String artist) =>
    RecTrack(title: title, artist: artist);

void main() {
  late Directory dir;
  late _FakeProvider provider;
  late _FakeAddon addon;
  late AutoplayController controller;
  final seed = Track(id: 'seed', title: 'Seed', artist: 'Origin');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('beatboss_autoplay_test');
    Hive.init(dir.path);
    final settings = SettingsService();
    await settings.init();
    final addons = AddonService(settingsService: settings);
    addon = _FakeAddon();
    addons.registerUserHandler('fake', addon);
    await addons.initAddons();
    await addons.setActiveAddon('fake');

    provider = _FakeProvider();
    final recs = RecommendationService(
      settings: settings,
      addons: addons,
      providers: [provider],
    );
    await recs.init();
    controller = AutoplayController(recs: recs, history: HistoryService());
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  /// Puts [songs] in both the recommendations and the addon catalog.
  void offer(List<RecTrack> songs) {
    provider.similar = songs;
    for (final s in songs) {
      addon.catalog.add('${s.title} ${s.artist}');
    }
  }

  test('returns playable tracks that are similar to the seed', () async {
    offer([rec('One', 'A'), rec('Two', 'B'), rec('Three', 'C')]);

    final batch =
        await controller.nextBatch(seeds: [seed], queue: [seed], want: 8);

    expect(batch.map((t) => t.title).toSet(), {'One', 'Two', 'Three'});
    expect(batch.every((t) => t.addonId == 'fake'), isTrue);
  });

  test('stops at the requested number of tracks', () async {
    offer([for (var i = 0; i < 20; i++) rec('Song$i', 'Artist$i')]);

    final batch =
        await controller.nextBatch(seeds: [seed], queue: [seed], want: 5);

    expect(batch, hasLength(5));
  });

  test('leaves out songs that are already in the queue', () async {
    offer([rec('One', 'A'), rec('Two', 'B')]);
    final queued = Track(id: 'q', title: 'One', artist: 'A');

    final batch = await controller
        .nextBatch(seeds: [seed], queue: [seed, queued], want: 8);

    expect(batch.map((t) => t.title), ['Two']);
  });

  test('skips songs the addon cannot find', () async {
    provider.similar = [rec('Have', 'A'), rec('Missing', 'B')];
    addon.catalog.add('Have A'); // "Missing B" is not in the catalog

    final batch =
        await controller.nextBatch(seeds: [seed], queue: [seed], want: 8);

    expect(batch.map((t) => t.title), ['Have']);
  });

  test('falls back to similar artists when there are no similar songs',
      () async {
    provider.similar = [];
    provider.artists = [const RecArtist(name: 'Sib')];
    provider.topTracks = {
      'Sib': [rec('Hit', 'Sib')],
    };
    addon.catalog.add('Hit Sib');

    final batch =
        await controller.nextBatch(seeds: [seed], queue: [seed], want: 8);

    expect(batch.map((t) => t.title), ['Hit']);
  });

  test("falls back to the seed artist's own songs as a last resort", () async {
    provider.topTracks = {
      'Origin': [rec('Deep Cut', 'Origin')],
    };
    addon.catalog.add('Deep Cut Origin');

    final batch =
        await controller.nextBatch(seeds: [seed], queue: [seed], want: 8);

    expect(batch.map((t) => t.title), ['Deep Cut']);
  });

  test('gives an empty list when nothing can be found', () async {
    final batch =
        await controller.nextBatch(seeds: [seed], queue: [seed], want: 8);

    expect(batch, isEmpty);
  });

  test('gives an empty list without seeds', () async {
    offer([rec('One', 'A')]);

    expect(await controller.nextBatch(seeds: [], queue: []), isEmpty);
  });

  group('seeds', () {
    final older = Track(id: 'old', title: 'Older', artist: 'X');
    final newer = Track(id: 'new', title: 'Newer', artist: 'Y');

    void offerFor(String seedTitle, List<RecTrack> songs) {
      provider.similarBySeed[seedTitle] = songs;
      for (final s in songs) {
        addon.catalog.add('${s.title} ${s.artist}');
      }
    }

    test('the first seed leads: songs follow the song that was just chosen',
        () async {
      offerFor('Newer', [rec('ForNewer', 'A')]);
      offerFor('Older', [rec('ForOlder', 'B')]);

      final batch = await controller.nextBatch(seeds: [newer, older], queue: []);

      expect(batch.map((t) => t.title), ['ForNewer']);
    });

    test('falls back to the next seed when the first finds nothing', () async {
      // The newest song has no similar songs; the older one does.
      offerFor('Older', [rec('ForOlder', 'B')]);

      final batch = await controller.nextBatch(seeds: [newer, older], queue: []);

      expect(batch.map((t) => t.title), ['ForOlder']);
    });

    test('falls back when the first seed only has songs that are already queued',
        () async {
      offerFor('Newer', [rec('Queued', 'A')]);
      offerFor('Older', [rec('Fresh', 'B')]);
      final queued = Track(id: 'q', title: 'Queued', artist: 'A');

      final batch = await controller
          .nextBatch(seeds: [newer, older], queue: [newer, queued]);

      expect(batch.map((t) => t.title), ['Fresh']);
    });

    test('is empty when no seed finds anything', () async {
      final batch = await controller.nextBatch(seeds: [newer, older], queue: []);

      expect(batch, isEmpty);
    });
  });
}
