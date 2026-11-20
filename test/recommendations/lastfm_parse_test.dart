import 'dart:convert';

import 'package:beatboss/core/recommendations/lastfm_recommendation_provider.dart';
import 'package:beatboss/core/recommendations/recommendation_provider.dart';
import 'package:beatboss/core/services/last_fm_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _placeholder =
    'https://lastfm.freetls.fastly.net/i/u/300x300/2a96cbd8b46e442fc41c2b86b821562f.png';

void main() {
  group('parseLastFmTracks', () {
    test('parses an array of tracks and picks the extralarge image', () {
      final json = jsonDecode('''
      {"similartracks": {"track": [
        {"name": "Song A", "match": 0.93, "artist": {"name": "Artist A"},
         "image": [
           {"#text": "https://img/large.png", "size": "large"},
           {"#text": "https://img/xl.png", "size": "extralarge"}
         ]},
        {"name": "Song B", "match": "0.5", "artist": {"name": "Artist B"}, "image": []}
      ]}}
      ''');

      final tracks = parseLastFmTracks(json['similartracks']['track']);

      expect(tracks, hasLength(2));
      expect(tracks[0].title, 'Song A');
      expect(tracks[0].artist, 'Artist A');
      expect(tracks[0].match, 0.93);
      expect(tracks[0].imageUrl, 'https://img/xl.png');
      expect(tracks[1].match, 0.5); // a string match is parsed too
      expect(tracks[1].imageUrl, isNull);
    });

    test('accepts a single object instead of an array', () {
      final json = jsonDecode('''
      {"toptracks": {"track": {"name": "Only One", "artist": {"name": "Solo"}}}}
      ''');

      final tracks = parseLastFmTracks(json['toptracks']['track']);

      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'Only One');
      expect(tracks.single.artist, 'Solo');
    });

    test('treats the placeholder star and empty strings as no image', () {
      final tracks = parseLastFmTracks([
        {
          'name': 'A',
          'artist': {'name': 'X'},
          'image': [
            {'#text': _placeholder, 'size': 'extralarge'},
            {'#text': '', 'size': 'large'},
          ],
        },
      ]);

      expect(tracks.single.imageUrl, isNull);
    });

    test('skips entries without a title or artist and tolerates junk', () {
      final tracks = parseLastFmTracks([
        {'name': '', 'artist': {'name': 'X'}},
        {'name': 'No Artist'},
        'not a map',
      ]);

      expect(tracks, isEmpty);
      expect(parseLastFmTracks(null), isEmpty);
    });
  });

  group('parseLastFmArtists', () {
    test('parses artists with a string match', () {
      final artists = parseLastFmArtists([
        {'name': 'Band', 'match': '0.75', 'image': []},
        {'name': ''},
      ]);

      expect(artists, hasLength(1));
      expect(artists.single.name, 'Band');
      expect(artists.single.match, 0.75);
    });
  });

  group('LastFmService.callApi', () {
    test('posts method and format, and returns the decoded JSON', () async {
      late http.Request seen;
      final service = LastFmService(client: MockClient((request) async {
        seen = request;
        return http.Response('{"similartracks": {"track": []}}', 200);
      }));

      final data = await service.callApi('track.getSimilar', {'artist': 'X'});

      expect(data, isNotNull);
      expect(seen.bodyFields['method'], 'track.getSimilar');
      expect(seen.bodyFields['format'], 'json');
      expect(seen.bodyFields['artist'], 'X');
    });

    test('returns null for an API error payload', () async {
      final service = LastFmService(
        client: MockClient((_) async =>
            http.Response('{"error": 6, "message": "Track not found"}', 200)),
      );

      expect(await service.callApi('track.getSimilar', {}), isNull);
    });

    test('returns null for an HTTP error or a network failure', () async {
      final httpError = LastFmService(
        client: MockClient((_) async => http.Response('nope', 500)),
      );
      final netError = LastFmService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );

      expect(await httpError.callApi('x', {}), isNull);
      expect(await netError.callApi('x', {}), isNull);
    });

    test('provider maps track.getSimilar to RecTracks', () async {
      final service = LastFmService(client: MockClient((_) async {
        return http.Response(
          '{"similartracks": {"track": {"name": "S", "artist": {"name": "A"}}}}',
          200,
        );
      }));
      final provider = LastFmRecommendationProvider(service);

      final tracks = await provider.similarTracks('A', 'B');

      expect(tracks.single.title, 'S');
      expect(provider.capabilities, contains(RecCapability.similarTracks));
    });
  });
}
