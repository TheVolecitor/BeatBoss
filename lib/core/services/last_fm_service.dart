import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';

class LastFmService extends ChangeNotifier {
  // Worker URL. The Worker holds the API key and shared secret; override with
  // --dart-define=LASTFM_BACKEND_URL=<url> to test against another Worker.
  static const String _baseUrl = String.fromEnvironment(
    'LASTFM_BACKEND_URL',
    defaultValue: 'https://beatboss-lastfm.thevolecitor.workers.dev/',
  );

  LastFmService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _sessionKey;
  String? _username;

  /// Reason the last [startAuth] call failed, for display in the UI.
  String? lastAuthError;

  bool get isAuthenticated => _sessionKey != null;
  String? get username => _username;

  Future<void> init() async {
    _sessionKey = await _storage.read(key: 'lastfm_session_key');
    _username = await _storage.read(key: 'lastfm_username');
    notifyListeners();
  }

  /// Step 1 of the web auth flow: request a token via Worker and open the
  /// Last.fm authorization page in the browser. Returns the token to pass to
  /// [completeAuth] once the user has approved access, or null on failure.
  Future<String?> startAuth() async {
    lastAuthError = null;

    try {
      final response = await _client.post(
        Uri.parse(_baseUrl),
        body: {'method': 'auth.getToken'},
      );
      if (response.statusCode != 200) {
        lastAuthError = 'Token request failed (HTTP ${response.statusCode})';
        return null;
      }

      final data = jsonDecode(response.body);
      final token = data['token'] as String?;
      if (token == null) {
        lastAuthError = 'Token request failed: ${response.body}';
        return null;
      }

      // The Worker returns the ready-made authorization URL (it holds the key).
      final urlString = data['url'] as String?;
      if (urlString == null) {
        lastAuthError = 'Backend did not return a login URL';
        return null;
      }
      final authUrl = Uri.tryParse(urlString);
      if (authUrl == null ||
          authUrl.scheme != 'https' ||
          authUrl.host != 'www.last.fm') {
        lastAuthError = 'Backend returned an unexpected login URL';
        return null;
      }

      final launched =
          await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      if (!launched) lastAuthError = 'Could not open the browser';
      return launched ? token : null;
    } catch (e) {
      lastAuthError = 'Could not start authorization: $e';
      print('Last.fm Auth Start Error: $e');
      return null;
    }
  }

  /// Step 2: exchange the authorized [token] for a session key via Worker.
  /// Returns false if the user has not approved the token yet.
  Future<bool> completeAuth(String token) async {
    try {
      final response = await _client.post(
        Uri.parse(_baseUrl),
        body: {'method': 'auth.getSession', 'token': token},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['session'] != null) {
          _sessionKey = data['session']['key'];
          _username = data['session']['name'];

          await _storage.write(key: 'lastfm_session_key', value: _sessionKey);
          if (_username != null) {
            await _storage.write(key: 'lastfm_username', value: _username!);
          }

          notifyListeners(); // Notify UI
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Last.fm Auth Complete Error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    _sessionKey = null;
    _username = null;
    await _storage.delete(key: 'lastfm_session_key');
    await _storage.delete(key: 'lastfm_username');
    notifyListeners();
  }

  /// POSTs [method] with [params] to the Worker, which adds the API key and
  /// signs the request. Returns the decoded JSON, or null on an HTTP error, an
  /// API error payload (`{"error": ..}`), or a network failure.
  Future<Map<String, dynamic>?> callApi(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse(_baseUrl),
        body: {'method': method, 'format': 'json', ...params},
      );
      if (response.statusCode != 200) {
        print('Last.fm $method failed: HTTP ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) {
        print('Last.fm $method error: ${data['error']} ${data['message']}');
        return null;
      }
      return data;
    } catch (e) {
      print('Last.fm $method Error: $e');
      return null;
    }
  }

  /// Update "Now Playing" status via Worker
  Future<void> updateNowPlaying(Track track) async {
    if (_sessionKey == null) return;

    final params = {
      'artist': track.artist,
      'track': track.title,
      'sk': _sessionKey!,
    };

    if (track.albumTitle != null) {
      params['album'] = track.albumTitle!;
    }

    await callApi('track.updateNowPlaying', params);
  }

  /// Scrobble a track via Worker
  Future<void> scrobble(Track track, {required DateTime timestamp}) async {
    if (_sessionKey == null) return;

    final params = {
      'artist': track.artist,
      'track': track.title,
      'timestamp': (timestamp.millisecondsSinceEpoch ~/ 1000).toString(),
      'sk': _sessionKey!,
    };

    if (track.albumTitle != null) {
      params['album'] = track.albumTitle!;
    }

    // The worker handles signing and forwarding to Last.fm
    final result = await callApi('track.scrobble', params);
    if (result != null) print('Last.fm scrobbled: ${track.title}');
  }

  Future<List<Map<String, String>>> getRecommendations() =>
      getStation('recommended');

  /// Fetches one of the user's website stations: `recommended`, `mix` or
  /// `library`. Returns `[{name, artist}]`, or an empty list when the station
  /// is unavailable.
  Future<List<Map<String, String>>> getStation(String kind) async {
    if (_username == null) return [];
    if (!const {'recommended', 'mix', 'library'}.contains(kind)) return [];

    // Unauthenticated request to the Last.fm player station endpoint.
    final url =
        'https://www.last.fm/player/station/user/$_username/$kind';

    try {
      print('Fetching $kind station from: $url');
      final response = await _client.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['playlist'] != null) {
          final tracks = data['playlist'] as List;
          return tracks.map<Map<String, String>>((t) {
            final name = t['name'].toString();
            String artist = 'Unknown';
            if (t['artists'] != null && (t['artists'] as List).isNotEmpty) {
              artist = t['artists'][0]['name'].toString();
            }
            return {
              'name': name,
              'artist': artist,
            };
          }).toList();
        }
      } else {
        print('Last.fm $kind station error: ${response.statusCode}');
      }
    } catch (e) {
      if (e.toString().contains('11001') || e.toString().contains('No such host')) {
        print('[LastFmService] Host resolution failed for the $kind station. Last.fm might be unreachable or DNS is failing.');
      } else {
        print('Last.fm $kind station error: $e');
      }
    }
    return [];
  }
}
