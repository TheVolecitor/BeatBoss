import 'dart:io';

import 'package:beatboss/core/models/addon_models.dart';
import 'package:beatboss/core/models/models.dart';
import 'package:beatboss/core/recommendations/rec_models.dart';
import 'package:beatboss/core/recommendations/recommendation_provider.dart';
import 'package:beatboss/core/recommendations/recommendation_service.dart';
import 'package:beatboss/core/recommendations/resolved_shelf.dart';
import 'package:beatboss/core/services/addon_service.dart';
import 'package:beatboss/core/services/settings_service.dart';
import 'package:beatboss/core/services/user_addon_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeProvider implements RecommendationProvider {
  bool loggedIn = true;
  int calls = 0;
  List<RecArtist> topArtists = [];
  Map<String, List<RecTrack>> topTracks = {};
  Map<String, List<RecTrack>> similar = {};
  List<RecTrack> charts = [];
  List<RecTrack> mix = [];

  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake';
  @override
  Set<RecCapability> get capabilities => RecCapability.values.toSet();
  @override
  bool get needsLogin => true;
  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<List<RecTrack>> station(StationKind kind) async {
    calls++;
    return kind == StationKind.mix ? mix : [];
  }

  @override
  Future<List<RecTrack>> similarTracks(String artist, String title,
      {int limit = 50}) async {
    calls++;
    return similar[title] ?? [];
  }

  @override
  Future<List<RecArtist>> similarArtists(String artist,
      {int limit = 20}) async {
    calls++;
    return [const RecArtist(name: 'Sib')];
  }

  @override
  Future<List<RecTrack>> artistTopTracks(String artist,
      {int limit = 30, int page = 1}) async {
    calls++;
    return topTracks[artist] ?? [];
  }

  @override
  Future<List<RecArtist>> userTopArtists(
      {String period = '3month', int limit = 10}) async {
    calls++;
    return topArtists;
  }

  @override
  Future<List<RecTrack>> tagTopTracks(String tag,
          {int limit = 30, int page = 1}) async =>
      [];

  @override
  Future<List<RecTrack>> chartTopTracks({int limit = 50, int page = 1}) async {
    calls++;
    return charts;
  }
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
  late SettingsService settings;
  late _FakeProvider provider;
  late _FakeAddon addon;
  late RecommendationService recs;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('beatboss_shelves_test');
    Hive.init(dir.path);
    settings = SettingsService();
    await settings.init();
    await settings.setUseLastFmRecommendations(true);
    final addons = AddonService(settingsService: settings);
    addon = _FakeAddon();
    addons.registerUserHandler('fake', addon);
    await addons.initAddons();
    await addons.setActiveAddon('fake');

    provider = _FakeProvider();
    recs = RecommendationService(
        settings: settings, addons: addons, providers: [provider]);
    await recs.init();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('artist mixes', () {
    setUp(() {
      provider.topArtists = [
        for (final n in ['A', 'B', 'C', 'D']) RecArtist(name: n),
      ];
      provider.topTracks = {
        'A': [rec('A1', 'A'), rec('A2', 'A')],
        'B': [rec('B1', 'B')],
        'C': [rec('C1', 'C')],
        'D': [rec('D1', 'D')],
      };
      provider.similar = {
        'A1': [rec('S1', 'X'), rec('S2', 'Y'), rec('S3', 'Z')],
      };
    });

    test('are built for the top 3 artists only', () async {
      final shelves = await recs.artistMixShelves();

      expect(shelves.map((s) => s.title), ['A Mix', 'B Mix', 'C Mix']);
    });

    test("interleave the artist's songs with similar ones", () async {
      final mix = await recs.artistMixShelf('A');

      expect(mix!.tracks.map((t) => t.title), ['A1', 'S1', 'A2', 'S2', 'S3']);
    });

    test('come from the cache until forced', () async {
      await recs.artistMixShelves();
      final calls = provider.calls;

      await recs.artistMixShelves();
      expect(provider.calls, calls, reason: 'cached shelves are reused');
      expect(recs.cachedArtistMixShelves, hasLength(3));

      await recs.artistMixShelves(force: true);
      expect(provider.calls, greaterThan(calls));
    });

    test('are not built without a login', () async {
      provider.loggedIn = false;

      expect(await recs.artistMixShelves(), isEmpty);
      expect(recs.cachedArtistMixShelves, isEmpty);
    });
  });

  group('station shelves', () {
    test('need a login', () async {
      provider.mix = [rec('M', 'A')];
      provider.loggedIn = false;

      expect(await recs.mixShelf(), isNull);

      provider.loggedIn = true;
      expect((await recs.mixShelf())!.tracks.single.title, 'M');
    });
  });

  group('public shelves', () {
    test('charts work without a login', () async {
      provider.loggedIn = false;
      provider.charts = [rec('Hit', 'A'), rec('Hit', 'A'), rec('Other', 'B')];

      final shelf = await recs.chartsShelf();

      expect(shelf!.tracks.map((t) => t.title), ['Hit', 'Other'],
          reason: 'duplicates are dropped');
      expect(recs.cachedChartsShelf, isNotNull);
    });

    test('are not built when recommendations are off', () async {
      await settings.setRecProviderId(SettingsService.recSourceOff);
      provider.charts = [rec('Hit', 'A')];

      expect(await recs.chartsShelf(), isNull);
      expect(recs.cachedChartsShelf, isNull);
      expect(provider.calls, 0);
    });

    test('because-you-listened is named after the seed', () async {
      provider.similar = {
        'Seed': [rec('One', 'A')]
      };
      final seed = Track(id: 's', title: 'Seed', artist: 'Origin');

      final shelf = await recs.becauseYouListened(seed);

      expect(shelf!.title, 'Because you listened to Seed');
      expect(recs.cachedBecause(seed), isNotNull);
    });

    test('fans-also-like holds artists', () async {
      final shelf = await recs.similarArtistsShelf('Origin');

      expect(shelf!.kind, ShelfKind.artists);
      expect(shelf.title, 'Fans also like Origin');
      expect(shelf.artists.single.name, 'Sib');
    });
  });

  group('ResolvedShelf', () {
    RecShelf shelfOf(List<RecTrack> tracks) => RecShelf(
        id: 's', title: 'T', tracks: tracks, fetchedAt: DateTime(2024));

    test('keeps found songs and drops the ones the addon lacks', () async {
      addon.catalog.addAll(['One A', 'Three C']);
      final resolved = ResolvedShelf(recs.resolver)
        ..setShelf(
            shelfOf([rec('One', 'A'), rec('Two', 'B'), rec('Three', 'C')]));

      final tracks = await resolved.playableWhenReady(min: 3);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(tracks.map((t) => t.title), ['One', 'Three']);
      expect(resolved.items.map((i) => i.rec.title), ['One', 'Three']);
      expect(resolved.isResolving, isFalse);
      resolved.dispose();
    });

    test('shows entries it is still looking up', () {
      addon.catalog.add('One A');
      final resolved = ResolvedShelf(recs.resolver)
        ..setShelf(shelfOf([rec('One', 'A')]));

      expect(resolved.items.single.track, isNull);
      expect(resolved.isResolving, isTrue);
      resolved.dispose();
    });

    test('only resolves the first [limit] entries', () async {
      addon.catalog.addAll(['One A', 'Two B', 'Three C']);
      final resolved = ResolvedShelf(recs.resolver, limit: 2)
        ..setShelf(
            shelfOf([rec('One', 'A'), rec('Two', 'B'), rec('Three', 'C')]));

      await resolved.playableWhenReady(
          min: 3, timeout: const Duration(seconds: 1));

      expect(resolved.playable.map((t) => t.title), ['One', 'Two']);
      resolved.dispose();
    });

    test('append resolves the new entries and skips known ones', () async {
      addon.catalog.addAll(['One A', 'Two B']);
      final resolved = ResolvedShelf(recs.resolver)
        ..setShelf(shelfOf([rec('One', 'A')]));
      await resolved.playableWhenReady(min: 1);

      resolved.append([rec('One', 'A'), rec('Two', 'B')]);
      await resolved.playableWhenReady(min: 2);

      expect(resolved.playable.map((t) => t.title), ['One', 'Two']);
      resolved.dispose();
    });
  });
}
