import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';

/// ListenBrainz API v1 client (https://listenbrainz.readthedocs.io/en/latest/users/api/index.html).
/// Supports user-token validation, playing-now / single listen submission,
/// user stats, and personalized recommendations without needing an API key.
class ListenBrainzService extends ChangeNotifier {
  static const String _apiRoot = 'https://api.listenbrainz.org/1';

  ListenBrainzService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _token;
  String? _username;
  String? lastAuthError;

  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  String? get username => _username;

  Future<void> init() async {
    _token = await _storage.read(key: 'listenbrainz_token');
    _username = await _storage.read(key: 'listenbrainz_username');
    notifyListeners();
  }

  /// Opens the ListenBrainz user settings page so the user can copy their
  /// user token.
  Future<bool> openTokenPage() async {
    return launchUrl(
      Uri.parse('https://listenbrainz.org/settings/'),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Validates [token] against GET /1/validate-token and stores the session.
  Future<bool> connect(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      lastAuthError = 'Please enter your ListenBrainz user token';
      return false;
    }
    lastAuthError = null;
    try {
      final resp = await _client.get(
        Uri.parse('$_apiRoot/validate-token'),
        headers: {'Authorization': 'Token $trimmed'},
      );
      if (resp.statusCode != 200) {
        lastAuthError = 'Validation failed (HTTP ${resp.statusCode})';
        return false;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['valid'] != true) {
        lastAuthError = data['message']?.toString() ?? 'Invalid user token';
        return false;
      }
      final user = data['user_name']?.toString();
      if (user == null || user.isEmpty) {
        lastAuthError = 'Could not read ListenBrainz username';
        return false;
      }
      _token = trimmed;
      _username = user;
      await _storage.write(key: 'listenbrainz_token', value: trimmed);
      await _storage.write(key: 'listenbrainz_username', value: user);
      notifyListeners();
      return true;
    } catch (e) {
      lastAuthError = 'Connection error: $e';
      print('ListenBrainz Auth Error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _username = null;
    await _storage.delete(key: 'listenbrainz_token');
    await _storage.delete(key: 'listenbrainz_username');
    notifyListeners();
  }

  Map<String, dynamic> _trackMetadata(Track track) {
    final additionalInfo = <String, dynamic>{
      'submission_client': 'BeatBoss',
      'submission_client_version': '2.0.0',
      if (track.isrc != null && track.isrc!.isNotEmpty) 'isrc': track.isrc,
      if (track.duration != null && track.duration! > 0)
        'duration': track.duration,
    };
    return {
      'artist_name': track.artist,
      'track_name': track.title,
      if (track.albumTitle != null && track.albumTitle!.isNotEmpty)
        'release_name': track.albumTitle,
      'additional_info': additionalInfo,
    };
  }

  Future<void> updateNowPlaying(Track track) async {
    if (!isAuthenticated) return;
    try {
      await _client.post(
        Uri.parse('$_apiRoot/submit-listens'),
        headers: {
          'Authorization': 'Token $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'listen_type': 'playing_now',
          'payload': [
            {'track_metadata': _trackMetadata(track)},
          ],
        }),
      );
    } catch (e) {
      print('ListenBrainz Now Playing Error: $e');
    }
  }

  Future<void> scrobble(Track track, {DateTime? timestamp}) async {
    if (!isAuthenticated) return;
    try {
      final ts = (timestamp ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      await _client.post(
        Uri.parse('$_apiRoot/submit-listens'),
        headers: {
          'Authorization': 'Token $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'listen_type': 'single',
          'payload': [
            {
              'listened_at': ts,
              'track_metadata': _trackMetadata(track),
            },
          ],
        }),
      );
      print('ListenBrainz Scrobbled: ${track.title} by ${track.artist}');
    } catch (e) {
      print('ListenBrainz Scrobble Error: $e');
    }
  }

  /// Builds a Cover Art Archive thumbnail URL from `caa_release_mbid` and
  /// `caa_id`, or null if either is missing.
  static String? coverArtUrl(dynamic caaReleaseMbid, dynamic caaId,
      {int size = 250}) {
    final release = caaReleaseMbid?.toString() ?? '';
    final id = caaId?.toString() ?? '';
    if (release.isEmpty || id.isEmpty) return null;
    return 'https://coverartarchive.org/release/$release/$id-$size.jpg';
  }

  Map<String, String> get _authHeaders => isAuthenticated
      ? {'Authorization': 'Token $_token'}
      : const {};

  /// Fetches the authenticated user's top recordings.
  Future<List<Map<String, dynamic>>> getUserTopRecordings({
    String range = 'month',
    int count = 50,
  }) async {
    final user = username;
    if (user == null || user.isEmpty) return const [];
    try {
      final resp = await _client.get(
        Uri.parse('$_apiRoot/stats/user/$user/recordings?range=$range&count=$count'),
        headers: _authHeaders,
      );
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['payload']?['recordings'] as List<dynamic>? ?? const [];
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      print('ListenBrainz top recordings error: $e');
      return const [];
    }
  }

  /// Fetches the authenticated user's top artists.
  Future<List<Map<String, dynamic>>> getUserTopArtists({
    String range = 'quarter',
    int count = 15,
  }) async {
    final user = username;
    if (user == null || user.isEmpty) return const [];
    try {
      final resp = await _client.get(
        Uri.parse('$_apiRoot/stats/user/$user/artists?range=$range&count=$count'),
        headers: _authHeaders,
      );
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['payload']?['artists'] as List<dynamic>? ?? const [];
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      print('ListenBrainz top artists error: $e');
      return const [];
    }
  }

  /// Fetches the authenticated user's recent listens (for Library / Mixes).
  Future<List<Map<String, dynamic>>> getUserListens({int count = 50}) async {
    final user = username;
    if (user == null || user.isEmpty) return const [];
    try {
      final resp = await _client.get(
        Uri.parse('$_apiRoot/user/$user/listens?count=$count'),
        headers: _authHeaders,
      );
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['payload']?['listens'] as List<dynamic>? ?? const [];
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      print('ListenBrainz user listens error: $e');
      return const [];
    }
  }

  /// Fetches playlists automatically generated for the authenticated user
  /// (e.g. Weekly Exploration, Weekly Jams, Daily Jams) via
  /// GET /1/user/{user_name}/playlists/createdfor.
  Future<List<Map<String, dynamic>>> getCreatedForPlaylists({
    int count = 25,
    int offset = 0,
  }) async {
    final user = username;
    if (user == null || user.isEmpty) return const [];
    try {
      final resp = await _client.get(
        Uri.parse(
            '$_apiRoot/user/$user/playlists/createdfor?count=$count&offset=$offset'),
        headers: _authHeaders,
      );
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['playlists'] as List<dynamic>? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => e['playlist'])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('ListenBrainz createdfor playlists error: $e');
      return const [];
    }
  }

  /// Fetches tracks of a JSPF playlist via GET /1/playlist/{playlist_mbid}.
  Future<List<Map<String, dynamic>>> getPlaylistTracks(
      String playlistMbid) async {
    if (playlistMbid.isEmpty) return const [];
    try {
      final resp = await _client.get(
        Uri.parse('$_apiRoot/playlist/$playlistMbid'),
        headers: _authHeaders,
      );
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tracks = data['playlist']?['track'] as List<dynamic>? ?? const [];
      return tracks
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('ListenBrainz playlist tracks error: $e');
      return const [];
    }
  }

  /// Fetches collaborative-filtering recording recommendations for the user via
  /// GET /1/cf/recommendation/user/{user_name}/recording and resolves their
  /// metadata via GET /1/metadata/recording/.
  Future<List<Map<String, dynamic>>> getUserRecommendedRecordings({
    int count = 50,
    int offset = 0,
  }) async {
    final user = username;
    if (user == null || user.isEmpty) return const [];
    try {
      final resp = await _client.get(
        Uri.parse(
            '$_apiRoot/cf/recommendation/user/$user/recording?count=$count&offset=$offset'),
        headers: _authHeaders,
      );
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final mbidRows = data['payload']?['mbids'] as List<dynamic>? ?? const [];
      final mbids = mbidRows
          .whereType<Map>()
          .map((e) => e['recording_mbid']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (mbids.isEmpty) return const [];
      return getRecordingsMetadata(mbids);
    } catch (e) {
      print('ListenBrainz CF recommendations error: $e');
      return const [];
    }
  }

  /// Resolves recording MBIDs to track/artist/release/cover metadata via
  /// GET /1/metadata/recording/.
  Future<List<Map<String, dynamic>>> getRecordingsMetadata(
    List<String> recordingMbids,
  ) async {
    if (recordingMbids.isEmpty || !isAuthenticated) return const [];
    final results = <Map<String, dynamic>>[];
    const chunkSize = 25;
    for (var i = 0; i < recordingMbids.length; i += chunkSize) {
      final chunk = recordingMbids.skip(i).take(chunkSize).join(',');
      try {
        final resp = await _client.get(
          Uri.parse(
              '$_apiRoot/metadata/recording/?recording_mbids=$chunk&inc=artist+release'),
          headers: _authHeaders,
        );
        if (resp.statusCode != 200) continue;
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.values) {
            if (entry is Map) {
              results.add(Map<String, dynamic>.from(entry));
            }
          }
        }
      } catch (e) {
        print('ListenBrainz metadata/recording error: $e');
      }
    }
    return results;
  }

  /// Generates an LB Radio JSPF playlist via GET /1/explore/lb-radio.
  /// Requires authentication. [mode] is `easy`, `medium`, or `hard`.
  Future<List<Map<String, dynamic>>> getLbRadio({
    required String prompt,
    String mode = 'medium',
  }) async {
    if (!isAuthenticated || prompt.trim().isEmpty) return const [];
    try {
      final uri = Uri.parse('$_apiRoot/explore/lb-radio').replace(
        queryParameters: {'prompt': prompt, 'mode': mode},
      );
      final resp = await _client.get(uri, headers: _authHeaders);
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final payload = data['payload'] as Map<String, dynamic>? ?? const {};
      final playlist = payload['jspf']?['playlist'] ?? payload['playlist'];
      final tracks =
          (playlist is Map ? playlist['track'] : null) as List<dynamic>? ??
              const [];
      return tracks
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('ListenBrainz lb-radio error: $e');
      return const [];
    }
  }

  /// Looks up MusicBrainz metadata for an artist & recording name via
  /// GET /1/metadata/lookup/. Requires authentication.
  Future<Map<String, dynamic>?> lookupMetadata({
    required String artistName,
    required String recordingName,
  }) async {
    if (!isAuthenticated || artistName.trim().isEmpty) return null;
    try {
      final uri = Uri.parse('$_apiRoot/metadata/lookup/').replace(
        queryParameters: {
          'artist_name': artistName,
          'recording_name': recordingName,
          'metadata': 'true',
        },
      );
      final resp = await _client.get(uri, headers: _authHeaders);
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      print('ListenBrainz metadata lookup error: $e');
      return null;
    }
  }

  /// Fetches popularity-ranked top recordings for an artist MBID via
  /// GET /1/popularity/top-recordings-for-artist/{artist_mbid}.
  Future<List<Map<String, dynamic>>> getArtistTopRecordings(
      String artistMbid) async {
    if (!isAuthenticated || artistMbid.isEmpty) return const [];
    try {
      final resp = await _client.get(
        Uri.parse('$_apiRoot/popularity/top-recordings-for-artist/$artistMbid'),
        headers: _authHeaders,
      );
      if (resp.statusCode != 200) return const [];
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('ListenBrainz artist top recordings error: $e');
      return const [];
    }
  }

  /// Fetches site-wide top recordings (used for public/logged-out charts).
  Future<List<Map<String, dynamic>>> getSitewideTopRecordings({
    String range = 'week',
    int count = 50,
    int offset = 0,
  }) async {
    try {
      final resp = await _client.get(
        Uri.parse(
            '$_apiRoot/stats/sitewide/recordings?range=$range&count=$count&offset=$offset'),
      );
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['payload']?['recordings'] as List<dynamic>? ?? const [];
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      print('ListenBrainz sitewide recordings error: $e');
      return const [];
    }
  }
}

