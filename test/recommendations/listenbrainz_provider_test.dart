import 'dart:convert';

import 'package:beatboss/core/recommendations/listenbrainz_recommendation_provider.dart';
import 'package:beatboss/core/recommendations/recommendation_provider.dart';
import 'package:beatboss/core/services/listenbrainz_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _TestListenBrainzService extends ListenBrainzService {
  final String? _fakeUser;
  final String? _fakeToken;

  _TestListenBrainzService({
    required http.Client client,
    String? username,
    String? token,
  })  : _fakeUser = username,
        _fakeToken = token,
        super(client: client);

  @override
  bool get isAuthenticated => _fakeToken != null && _fakeToken!.isNotEmpty;

  @override
  String? get username => _fakeUser;
}

void main() {
  test('chartTopTracks passes offset for pagination and builds CAA cover URL',
      () async {
    Uri? captured;
    final client = MockClient((req) async {
      captured = req.url;
      return http.Response(
        jsonEncode({
          'payload': {
            'recordings': [
              {
                'track_name': 'SWIM',
                'artist_name': 'BTS',
                'release_name': 'ARIRANG',
                'caa_id': 44649429843,
                'caa_release_mbid': '2f9b427d-cc6e-4465-9f70-9d2109381db0',
              },
            ],
          },
        }),
        200,
      );
    });

    final lb = _TestListenBrainzService(client: client);
    final provider = ListenBrainzRecommendationProvider(lb)..chartRange = 'month';
    final tracks = await provider.chartTopTracks(limit: 30, page: 2);

    expect(captured?.path, '/1/stats/sitewide/recordings');
    expect(captured?.queryParameters['range'], 'month');
    expect(captured?.queryParameters['count'], '30');
    expect(captured?.queryParameters['offset'], '30');
    expect(tracks, hasLength(1));
    expect(tracks.first.title, 'SWIM');
    expect(tracks.first.artist, 'BTS');
    expect(
      tracks.first.imageUrl,
      'https://coverartarchive.org/release/2f9b427d-cc6e-4465-9f70-9d2109381db0/44649429843-250.jpg',
    );
  });

  test('station(recommended) combines createdfor playlist and CF recordings',
      () async {
    final client = MockClient((req) async {
      if (req.url.path == '/1/user/alice/playlists/createdfor') {
        return http.Response(
          jsonEncode({
            'playlists': [
              {
                'playlist': {
                  'title': 'Weekly Exploration for alice',
                  'identifier': 'https://listenbrainz.org/playlist/pl-123',
                },
              },
            ],
          }),
          200,
        );
      }
      if (req.url.path == '/1/playlist/pl-123') {
        return http.Response(
          jsonEncode({
            'playlist': {
              'track': [
                {
                  'title': 'Let It Happen',
                  'creator': 'Tame Impala',
                  'album': 'Currents',
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path == '/1/cf/recommendation/user/alice/recording') {
        return http.Response(
          jsonEncode({
            'payload': {
              'mbids': [
                {'recording_mbid': 'rec-1', 'score': 9.1},
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path == '/1/metadata/recording/') {
        return http.Response(
          jsonEncode({
            'rec-1': {
              'recording': {'name': 'Borderline'},
              'artist': {'name': 'Tame Impala'},
              'release': {
                'name': 'The Slow Rush',
                'caa_id': 12345,
                'caa_release_mbid': 'rel-1',
              },
            },
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final lb = _TestListenBrainzService(
      client: client,
      username: 'alice',
      token: 'tok-123',
    );
    final provider = ListenBrainzRecommendationProvider(lb);
    final tracks = await provider.station(StationKind.recommended);

    expect(tracks.map((t) => t.title), ['Let It Happen', 'Borderline']);
    expect(
      tracks.last.imageUrl,
      'https://coverartarchive.org/release/rel-1/12345-250.jpg',
    );
  });

  test('similarTracks uses lb-radio and excludes the seed track', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/1/explore/lb-radio') {
        return http.Response(
          jsonEncode({
            'payload': {
              'jspf': {
                'playlist': {
                  'track': [
                    {'title': 'Dracula', 'creator': 'Tame Impala'},
                    {'title': 'Elephant', 'creator': 'Tame Impala'},
                  ],
                },
              },
            },
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final lb = _TestListenBrainzService(
      client: client,
      username: 'alice',
      token: 'tok-123',
    );
    final provider = ListenBrainzRecommendationProvider(lb);
    final similar = await provider.similarTracks('Tame Impala', 'Dracula');

    expect(similar.map((t) => t.title), ['Elephant']);
  });
}

