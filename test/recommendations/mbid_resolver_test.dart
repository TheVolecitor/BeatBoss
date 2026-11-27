import 'dart:convert';
import 'dart:io';

import 'package:beatboss/core/models/addon_models.dart';
import 'package:beatboss/core/recommendations/musicbrainz_lookup.dart';
import 'package:beatboss/core/recommendations/rec_models.dart';
import 'package:beatboss/core/recommendations/resolved_shelf.dart';
import 'package:beatboss/core/recommendations/track_resolver.dart';
import 'package:beatboss/core/services/addon_service.dart';
import 'package:beatboss/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _IsrcTrackingAddonService extends AddonService {
  int searchCalls = 0;
  int isrcCalls = 0;
  String? lastIsrc;
  final bool isrcSupported;

  _IsrcTrackingAddonService({
    required super.settingsService,
    this.isrcSupported = true,
  });

  @override
  String? get activeAddonId => 'srv';

  @override
  bool supportsIsrcFor([String? addonId]) => isrcSupported;

  @override
  bool supportsResolveFor([String? addonId]) => false;

  @override
  Future<({bool handled, AddonTrack? track})> resolveTrack(RecTrack rec,
          {String? addonId}) async =>
      (handled: false, track: null);

  @override
  Future<String?> resolveIsrc(String isrc, {String? addonId}) async {
    isrcCalls++;
    lastIsrc = isrc;
    return isrcSupported ? 'track-from-isrc-$isrc' : null;
  }

  @override
  Future<AddonSearchResult?> search(String query,
      {String? addonId, int? limit}) async {
    searchCalls++;
    return AddonSearchResult(tracks: [
      AddonTrack(
        id: 'search-hit',
        title: 'Track',
        artist: 'Artist',
        addonId: 'srv',
      ),
    ]);
  }
}

void main() {
  late Directory dir;
  late SettingsService settings;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('beatboss_mbid_test');
    Hive.init(dir.path);
    settings = SettingsService();
    await settings.init();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('TrackResolver uses MusicBrainz MBID -> ISRC -> addon resolveIsrc without search',
      () async {
    final mbClient = MockClient((req) async {
      if (req.url.host == 'api.listenbrainz.org') {
        return http.Response('{}', 404);
      }
      if (req.url.host == 'musicbrainz.org') {
        expect(req.url.path, '/ws/2/recording/mbid-123');
        return http.Response(
          jsonEncode({
            'isrcs': ['USRC12345678'],
          }),
          200,
        );
      }
      if (req.url.host == 'api.deezer.com') {
        expect(req.url.path, '/track/isrc:USRC12345678');
        return http.Response(
          jsonEncode({
            'album': {
              'cover_medium': 'https://cdn-images.dzcdn.net/cover-usrc.jpg',
            },
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final addons = _IsrcTrackingAddonService(settingsService: settings);
    final resolver = TrackResolver(
      addons,
      mbLookup: MusicBrainzLookup(
        client: mbClient,
        minInterval: Duration.zero,
      ),
    );
    await resolver.init();

    final track = await resolver.resolve(const RecTrack(
      title: 'Track',
      artist: 'Artist',
      mbid: 'mbid-123',
    ));

    expect(track, isNotNull);
    expect(track!.id, 'track-from-isrc-USRC12345678');
    expect(track.isrc, 'USRC12345678');
    expect(track.albumCover, 'https://cdn-images.dzcdn.net/cover-usrc.jpg');
    expect(addons.isrcCalls, 1);
    expect(addons.searchCalls, 0);
  });

  test('Lazy ResolvedShelf clubs MBIDs into 30-per-batch bulk lookup for ISRC and cover without calling addon search',
      () async {
    final mbClient = MockClient((req) async {
      if (req.url.host == 'api.listenbrainz.org') {
        expect(req.url.path, '/1/metadata/recording/');
        expect(req.url.queryParameters['recording_mbids'], 'mbid-abc');
        return http.Response(
          jsonEncode({
            'mbid-abc': {
              'recording': {
                'isrcs': ['GBXYZ0000001'],
              },
              'release': {
                'caa_id': 999,
                'caa_release_mbid': 'rel-caa',
              },
            },
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final addons = _IsrcTrackingAddonService(settingsService: settings);
    final resolver = TrackResolver(
      addons,
      mbLookup: MusicBrainzLookup(
        client: mbClient,
        minInterval: Duration.zero,
      ),
    );
    await resolver.init();

    final shelf = ResolvedShelf(resolver, limit: 8, eagerResolve: false)
      ..setShelf(RecShelf(
        id: 'charts',
        title: 'Top charts',
        tracks: const [
          RecTrack(title: 'Track', artist: 'Artist', mbid: 'mbid-abc'),
        ],
        fetchedAt: DateTime(2026),
      ));

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(addons.searchCalls, 0);
    expect(addons.isrcCalls, 0);
    expect(shelf.items.single.rec.isrc, 'GBXYZ0000001');
    expect(
      shelf.items.single.rec.imageUrl,
      'https://coverartarchive.org/release/rel-caa/999-250.jpg',
    );

    final played = await shelf.resolveAt(0);
    expect(played?.id, 'track-from-isrc-GBXYZ0000001');
    expect(addons.isrcCalls, 1);
    expect(addons.searchCalls, 0);
    shelf.dispose();
  });

  test('Lazy ResolvedShelf uses caa_id cover directly when ListenBrainz returns isrcs: null',
      () async {
    var deezerCalled = false;
    var mbCalled = false;
    final mbClient = MockClient((req) async {
      if (req.url.host == 'api.listenbrainz.org') {
        return http.Response(
          jsonEncode({
            '85240a9c-5d8f-44da-bfae-c2bdd8f1e9d7': {
              'recording': {'isrcs': null, 'name': 'Ishqa Ve'},
              'release': {
                'caa_id': 43675573854,
                'caa_release_mbid': 'bbeb52a2-c0b6-4aaf-8772-4af1c0874cb5',
              },
            },
          }),
          200,
        );
      }
      if (req.url.host == 'api.deezer.com') deezerCalled = true;
      if (req.url.host == 'musicbrainz.org') mbCalled = true;
      return http.Response('{}', 404);
    });

    final addons = _IsrcTrackingAddonService(settingsService: settings);
    final resolver = TrackResolver(
      addons,
      mbLookup: MusicBrainzLookup(
        client: mbClient,
        minInterval: Duration.zero,
      ),
    );
    await resolver.init();

    final shelf = ResolvedShelf(resolver, limit: 8, eagerResolve: false)
      ..setShelf(RecShelf(
        id: 'charts',
        title: 'Top charts',
        tracks: const [
          RecTrack(
            title: 'Ishqa Ve',
            artist: 'Zeeshan Ali',
            mbid: '85240a9c-5d8f-44da-bfae-c2bdd8f1e9d7',
          ),
        ],
        fetchedAt: DateTime(2026),
      ));

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(deezerCalled, isFalse);
    expect(mbCalled, isFalse);
    expect(
      shelf.items.single.rec.imageUrl,
      'https://coverartarchive.org/release/bbeb52a2-c0b6-4aaf-8772-4af1c0874cb5/43675573854-250.jpg',
    );
    shelf.dispose();
  });

  test('MusicBrainzLookup retries once when ListenBrainz returns HTML instead of JSON',
      () async {
    var attempts = 0;
    final client = MockClient((req) async {
      attempts++;
      if (attempts == 1) {
        return http.Response('<!DOCTYPE html><html></html>', 200);
      }
      return http.Response(
        jsonEncode({
          'mbid-retry': {
            'recording': {
              'isrcs': ['USRETRY00001'],
            },
            'release': {
              'caa_id': 777,
              'caa_release_mbid': 'rel-retry',
            },
          },
        }),
        200,
      );
    });

    final lookup = MusicBrainzLookup(client: client, minInterval: Duration.zero);
    final res = await lookup.lookupRecordingsBulk(['mbid-retry']);

    expect(attempts, 2);
    expect(res['mbid-retry']?.isrc, 'USRETRY00001');
    expect(
      res['mbid-retry']?.coverUrl,
      'https://coverartarchive.org/release/rel-retry/777-250.jpg',
    );
  });

  test('Lazy ResolvedShelf falls back to addon search for remaining tracks and caches cover for 6 hours',
      () async {
    final mbClient = MockClient((_) async => http.Response('{}', 404));
    final addons = _IsrcTrackingAddonService(settingsService: settings);
    final resolver = TrackResolver(
      addons,
      mbLookup: MusicBrainzLookup(client: mbClient, minInterval: Duration.zero),
    );
    await resolver.init();

    // First shelf without MBID/ISRC falls back to addon search.
    final shelf1 = ResolvedShelf(resolver, eagerResolve: false)
      ..setShelf(RecShelf(
        id: 'charts',
        title: 'Top charts',
        tracks: const [RecTrack(title: 'Track', artist: 'Artist')],
        fetchedAt: DateTime(2026),
      ));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(addons.searchCalls, 1);
    shelf1.dispose();

    // Second shelf with the same track hits the 6-hour cover cache (0 searches).
    final shelf2 = ResolvedShelf(resolver, eagerResolve: false)
      ..setShelf(RecShelf(
        id: 'charts',
        title: 'Top charts',
        tracks: const [RecTrack(title: 'Track', artist: 'Artist')],
        fetchedAt: DateTime(2026, 1, 2),
      ));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(addons.searchCalls, 1);
    shelf2.dispose();
  });
}

