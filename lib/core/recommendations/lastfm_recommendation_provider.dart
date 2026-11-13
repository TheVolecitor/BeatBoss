import '../services/last_fm_service.dart';
import 'rec_models.dart';
import 'recommendation_provider.dart';

/// Last.fm's grey-star placeholder image; treated as "no image".
const _lastFmPlaceholder = '2a96cbd8b46e442fc41c2b86b821562f';

/// Last.fm returns an object instead of a one-element array when there is a
/// single result. Always gives back a list of maps.
List<Map<String, dynamic>> _asList(dynamic node) {
  if (node is List) {
    return node
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (node is Map) return [Map<String, dynamic>.from(node)];
  return const [];
}

/// Picks the best image URL from a Last.fm `image[]` array (extralarge, then
/// large, ...). Empty strings and the star placeholder become null.
String? pickLastFmImage(dynamic images) {
  const order = ['extralarge', 'large', 'medium', 'small'];
  final list = _asList(images);
  for (final size in order) {
    for (final img in list) {
      if (img['size'] != size) continue;
      final url = img['#text']?.toString() ?? '';
      if (url.isEmpty || url.contains(_lastFmPlaceholder)) continue;
      return url;
    }
  }
  return null;
}

double? _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '');
}

/// Parses a Last.fm track list node (`track[]`, object or array).
List<RecTrack> parseLastFmTracks(dynamic node) {
  final result = <RecTrack>[];
  for (final t in _asList(node)) {
    final title = t['name']?.toString() ?? '';
    final artistNode = t['artist'];
    final artist = artistNode is Map
        ? (artistNode['name'] ?? artistNode['#text'])?.toString() ?? ''
        : artistNode?.toString() ?? '';
    if (title.isEmpty || artist.isEmpty) continue;
    result.add(RecTrack(
      title: title,
      artist: artist,
      imageUrl: pickLastFmImage(t['image']),
      match: _toDouble(t['match']),
    ));
  }
  return result;
}

/// Parses a Last.fm artist list node (`artist[]`, object or array).
List<RecArtist> parseLastFmArtists(dynamic node) {
  final result = <RecArtist>[];
  for (final a in _asList(node)) {
    final name = a['name']?.toString() ?? '';
    if (name.isEmpty) continue;
    result.add(RecArtist(
      name: name,
      imageUrl: pickLastFmImage(a['image']),
      match: _toDouble(a['match']),
    ));
  }
  return result;
}

/// Reads `root[outer][inner]` from an API response, tolerating missing keys.
dynamic _dig(Map<String, dynamic>? data, String outer, String inner) {
  final o = data?[outer];
  return o is Map ? o[inner] : null;
}

class LastFmRecommendationProvider implements RecommendationProvider {
  final LastFmService _lastFm;

  LastFmRecommendationProvider(this._lastFm);

  @override
  String get id => 'lastfm';

  @override
  String get displayName => 'Last.fm';

  @override
  Set<RecCapability> get capabilities => RecCapability.values.toSet();

  @override
  bool get needsLogin => true;

  @override
  bool get isLoggedIn => _lastFm.isAuthenticated;

  @override
  Future<List<RecTrack>> station(StationKind kind) async {
    final raw = await _lastFm.getStation(kind.name);
    return raw
        .map((m) => RecTrack(title: m['name'] ?? '', artist: m['artist'] ?? ''))
        .where((t) => t.title.isNotEmpty && t.artist.isNotEmpty)
        .toList();
  }

  @override
  Future<List<RecTrack>> similarTracks(String artist, String title,
      {int limit = 50}) async {
    final data = await _lastFm.callApi('track.getSimilar', {
      'artist': artist,
      'track': title,
      'limit': '$limit',
      'autocorrect': '1',
    });
    return parseLastFmTracks(_dig(data, 'similartracks', 'track'));
  }

  @override
  Future<List<RecArtist>> similarArtists(String artist,
      {int limit = 20}) async {
    final data = await _lastFm.callApi('artist.getSimilar', {
      'artist': artist,
      'limit': '$limit',
      'autocorrect': '1',
    });
    return parseLastFmArtists(_dig(data, 'similarartists', 'artist'));
  }

  @override
  Future<List<RecTrack>> artistTopTracks(String artist,
      {int limit = 30, int page = 1}) async {
    final data = await _lastFm.callApi('artist.getTopTracks', {
      'artist': artist,
      'limit': '$limit',
      'page': '$page',
      'autocorrect': '1',
    });
    return parseLastFmTracks(_dig(data, 'toptracks', 'track'));
  }

  @override
  Future<List<RecArtist>> userTopArtists(
      {String period = '3month', int limit = 10}) async {
    final user = _lastFm.username;
    if (user == null) return [];
    final data = await _lastFm.callApi('user.getTopArtists', {
      'user': user,
      'period': period,
      'limit': '$limit',
    });
    return parseLastFmArtists(_dig(data, 'topartists', 'artist'));
  }

  @override
  Future<List<RecTrack>> tagTopTracks(String tag,
      {int limit = 30, int page = 1}) async {
    final data = await _lastFm.callApi('tag.getTopTracks', {
      'tag': tag,
      'limit': '$limit',
      'page': '$page',
    });
    return parseLastFmTracks(_dig(data, 'tracks', 'track'));
  }

  @override
  Future<List<RecTrack>> chartTopTracks({int limit = 50, int page = 1}) async {
    final data = await _lastFm.callApi('chart.getTopTracks', {
      'limit': '$limit',
      'page': '$page',
    });
    return parseLastFmTracks(_dig(data, 'tracks', 'track'));
  }
}
