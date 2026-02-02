import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/models.dart';

class LastFmService extends ChangeNotifier {
  // Use Worker URL
  static const String _baseUrl =
      'https://beatboss-lastfm.thevolecitor.workers.dev/';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  String? _sessionKey;
  String? _username;

  bool get isAuthenticated => _sessionKey != null;
  String? get username => _username;

  Future<void> init() async {
    _sessionKey = await _storage.read(key: 'lastfm_session_key');
    _username = await _storage.read(key: 'lastfm_username');
    notifyListeners();
  }

  /// Authenticate using username and password (Mobile Session) via Worker
  Future<bool> login(String username, String password) async {
    final params = {
      'method': 'auth.getMobileSession',
      'username': username,
      'password': password,
    };

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        body: params,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['session'] != null) {
          _sessionKey = data['session']['key'];
          _username = data['session']['name']; // Parse name

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
      print('Last.fm Login Error: $e');
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

  /// Update "Now Playing" status via Worker
  Future<void> updateNowPlaying(Track track) async {
    if (_sessionKey == null) return;

    final params = {
      'method': 'track.updateNowPlaying',
      'artist': track.artist,
      'track': track.title,
      'sk': _sessionKey!,
    };

    if (track.albumTitle != null) {
      params['album'] = track.albumTitle!;
    }

    try {
      await http.post(Uri.parse(_baseUrl), body: params);
    } catch (e) {
      print('Last.fm NowPlaying Error: $e');
    }
  }

  /// Scrobble a track via Worker
  Future<void> scrobble(Track track, {required DateTime timestamp}) async {
    if (_sessionKey == null) return;

    final params = {
      'method': 'track.scrobble',
      'artist': track.artist,
      'track': track.title,
      'timestamp': (timestamp.millisecondsSinceEpoch ~/ 1000).toString(),
      'sk': _sessionKey!,
    };

    if (track.albumTitle != null) {
      params['album'] = track.albumTitle!;
    }

    try {
      // The worker handles signing and forwarding to Last.fm
      await http.post(Uri.parse(_baseUrl), body: params);
      print('Last.fm scrobbled: ${track.title}');
    } catch (e) {
      print('Last.fm Scrobble Error: $e');
    }
  }

  Future<List<Map<String, String>>> getRecommendations() async {
    if (_username == null) return [];

    // Direct request to Last.fm player API as requested
    final url =
        'https://www.last.fm/player/station/user/$_username/recommended';

    try {
      print('Fetching recommendations from: $url');
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // The structure of this endpoint usually returns { playlist: [ { name, artists: [ { name } ] } ] }
        // or similar. Let's inspect/adapt based on standard Last.fm player responses.
        // Usually: { playlist: [ { name: "Title", artists: [ { name: "Artist" } ] } ] }

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
        print('Last.fm Recommendations Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Last.fm Recommendations Error: $e');
    }
    return [];
  }
}
