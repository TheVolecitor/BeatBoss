import '../services/listenbrainz_service.dart';
import 'rec_models.dart';
import 'recommendation_provider.dart';
import 'track_matching.dart';

/// [RecommendationProvider] backed by ListenBrainz v1 API:
/// - Created-For playlists (Weekly Exploration, Weekly Jams, Daily Jams)
/// - Collaborative-filtering recording recommendations + metadata lookup
/// - LB Radio (`artist:(...)`, `tag:(...)`) for similar tracks, artist radio, tags
/// - Popularity API for artist top recordings
/// - Site-wide charts with pagination & time range support
class ListenBrainzRecommendationProvider implements RecommendationProvider {
  final ListenBrainzService _lb;

  /// Active chart time range (`week`, `month`, `all_time`).
  String chartRange = 'week';

  ListenBrainzRecommendationProvider(this._lb);

  @override
  String get id => 'listenbrainz';

  @override
  String get displayName => 'ListenBrainz';

  @override
  Set<RecCapability> get capabilities => const {
        RecCapability.personalStations,
        RecCapability.similarTracks,
        RecCapability.similarArtists,
        RecCapability.artistTopTracks,
        RecCapability.userTopArtists,
        RecCapability.tagTopTracks,
        RecCapability.charts,
      };

  @override
  bool get needsLogin => true;

  @override
  bool get isLoggedIn => _lb.isAuthenticated;

  RecTrack? _fromRecording(Map<String, dynamic> r) {
    final title =
        (r['track_name'] ?? r['recording_name'] ?? r['name'])?.toString() ??
            '';
    final artist =
        (r['artist_name'] ?? r['artist_credit_name'])?.toString() ?? '';
    if (title.isEmpty || artist.isEmpty) return null;
    final imageUrl = ListenBrainzService.coverArtUrl(
      r['caa_release_mbid'],
      r['caa_id'],
    );
    return RecTrack(
      title: title,
      artist: artist,
      album: r['release_name']?.toString(),
      imageUrl: imageUrl,
    );
  }

  RecTrack? _fromJspfTrack(Map<String, dynamic> t) {
    final title = (t['title'] ?? t['track_name'])?.toString() ?? '';
    final artist = (t['creator'] ?? t['artist_name'])?.toString() ?? '';
    if (title.isEmpty || artist.isEmpty) return null;
    final ext = t['extension'];
    Map<String, dynamic>? jspfTrack;
    if (ext is Map) {
      final raw = ext['https://musicbrainz.org/doc/jspf#track'] ??
          ext['https://listenbrainz.org'];
      if (raw is Map) jspfTrack = Map<String, dynamic>.from(raw);
    }
    final additional = jspfTrack?['additional_metadata'];
    final caaRelease = additional is Map
        ? additional['caa_release_mbid']
        : jspfTrack?['caa_release_mbid'];
    final caaId =
        additional is Map ? additional['caa_id'] : jspfTrack?['caa_id'];
    return RecTrack(
      title: title,
      artist: artist,
      album: t['album']?.toString(),
      imageUrl: ListenBrainzService.coverArtUrl(caaRelease, caaId),
    );
  }

  RecTrack? _fromMetadataRecording(Map<String, dynamic> entry) {
    final rec = entry['recording'];
    final art = entry['artist'];
    final rel = entry['release'];
    final title = (rec is Map ? rec['name'] : entry['recording_name'])
            ?.toString() ??
        '';
    final artist = (art is Map ? art['name'] : entry['artist_credit_name'])
            ?.toString() ??
        '';
    if (title.isEmpty || artist.isEmpty) return null;
    final album = rel is Map ? rel['name']?.toString() : null;
    final caaRelease = rel is Map ? rel['caa_release_mbid'] : null;
    final caaId = rel is Map ? rel['caa_id'] : null;
    return RecTrack(
      title: title,
      artist: artist,
      album: album,
      imageUrl: ListenBrainzService.coverArtUrl(caaRelease, caaId),
    );
  }

  String? _playlistMbid(Map<String, dynamic> playlist) {
    final identifier = playlist['identifier']?.toString() ?? '';
    if (identifier.isEmpty) return null;
    final parts = identifier.split('/');
    final mbid = parts.isNotEmpty ? parts.last.trim() : '';
    return mbid.isEmpty ? null : mbid;
  }

  String _cleanPrompt(String value) =>
      value.replaceAll('(', ' ').replaceAll(')', ' ').trim();

  @override
  Future<List<RecTrack>> station(StationKind kind) async {
    if (!isLoggedIn) return const [];
    switch (kind) {
      case StationKind.recommended:
        final playlists = await _lb.getCreatedForPlaylists();
        final tracks = <RecTrack>[];
        // Prefer Weekly Exploration or Daily Jams created-for playlists.
        final preferred = playlists.where((p) {
          final title = (p['title']?.toString() ?? '').toLowerCase();
          return title.contains('exploration') || title.contains('daily');
        }).toList();
        final target = preferred.isNotEmpty ? preferred.first : (playlists.isNotEmpty ? playlists.first : null);
        if (target != null) {
          final mbid = _playlistMbid(target);
          if (mbid != null) {
            final jspf = await _lb.getPlaylistTracks(mbid);
            tracks.addAll(jspf.map(_fromJspfTrack).whereType<RecTrack>());
          }
        }
        // Supplement with CF recording recommendations.
        final cf = await _lb.getUserRecommendedRecordings(count: 50);
        tracks.addAll(cf.map(_fromMetadataRecording).whereType<RecTrack>());
        if (tracks.isNotEmpty) return tracks;

        final fallback = await _lb.getUserTopRecordings(range: 'month', count: 50);
        return fallback.map(_fromRecording).whereType<RecTrack>().toList();

      case StationKind.mix:
        final playlists = await _lb.getCreatedForPlaylists();
        final jams = playlists.where((p) {
          final title = (p['title']?.toString() ?? '').toLowerCase();
          return title.contains('jams') || title.contains('mix');
        }).toList();
        if (jams.isNotEmpty) {
          final mbid = _playlistMbid(jams.first);
          if (mbid != null) {
            final jspf = await _lb.getPlaylistTracks(mbid);
            final parsed = jspf.map(_fromJspfTrack).whereType<RecTrack>().toList();
            if (parsed.isNotEmpty) return parsed;
          }
        }
        // Interleave recent favourites with CF discoveries.
        final recentTop = (await _lb.getUserTopRecordings(range: 'week', count: 25))
            .map(_fromRecording)
            .whereType<RecTrack>()
            .toList();
        final cf = (await _lb.getUserRecommendedRecordings(count: 25))
            .map(_fromMetadataRecording)
            .whereType<RecTrack>()
            .toList();
        final mixed = <RecTrack>[];
        for (var i = 0; i < recentTop.length || i < cf.length; i++) {
          if (i < recentTop.length) mixed.add(recentTop[i]);
          if (i < cf.length) mixed.add(cf[i]);
        }
        return mixed;

      case StationKind.library:
        final listens = await _lb.getUserListens(count: 50);
        return listens
            .map((l) => l['track_metadata'])
            .whereType<Map>()
            .map((m) => _fromRecording(Map<String, dynamic>.from(m)))
            .whereType<RecTrack>()
            .toList();
    }
  }

  @override
  Future<List<RecTrack>> similarTracks(String artist, String title,
      {int limit = 50}) async {
    if (!isLoggedIn || artist.trim().isEmpty) return const [];
    final prompt = 'artist:(${_cleanPrompt(artist)})';
    var raw = await _lb.getLbRadio(prompt: prompt, mode: 'medium');
    if (raw.isEmpty) {
      raw = await _lb.getLbRadio(prompt: prompt, mode: 'easy');
    }
    final seedKey = matchKey(artist, title);
    return raw
        .map(_fromJspfTrack)
        .whereType<RecTrack>()
        .where((t) => t.key != seedKey)
        .take(limit)
        .toList();
  }

  @override
  Future<List<RecArtist>> similarArtists(String artist,
      {int limit = 20}) async {
    if (!isLoggedIn || artist.trim().isEmpty) return const [];
    final raw = await _lb.getLbRadio(
      prompt: 'artist:(${_cleanPrompt(artist)})',
      mode: 'medium',
    );
    final seedNorm = normalizeForMatch(artist);
    final seen = <String>{seedNorm};
    final result = <RecArtist>[];
    for (final t in raw.map(_fromJspfTrack).whereType<RecTrack>()) {
      final norm = normalizeForMatch(t.artist);
      if (norm.isEmpty || !seen.add(norm)) continue;
      result.add(RecArtist(name: t.artist, imageUrl: t.imageUrl));
      if (result.length >= limit) break;
    }
    return result;
  }

  @override
  Future<List<RecTrack>> artistTopTracks(String artist,
      {int limit = 30, int page = 1}) async {
    if (!isLoggedIn || artist.trim().isEmpty) return const [];
    final lookup =
        await _lb.lookupMetadata(artistName: artist, recordingName: '');
    final artistMbids = lookup?['artist_mbids'] as List<dynamic>? ?? const [];
    if (artistMbids.isNotEmpty) {
      final mbid = artistMbids.first?.toString() ?? '';
      if (mbid.isNotEmpty) {
        final top = await _lb.getArtistTopRecordings(mbid);
        final parsed = top.map(_fromRecording).whereType<RecTrack>().toList();
        if (parsed.isNotEmpty) {
          final start = (page - 1) * limit;
          if (start >= parsed.length) return const [];
          return parsed.skip(start).take(limit).toList();
        }
      }
    }
    if (page > 1) return const [];
    final radio = await _lb.getLbRadio(
      prompt: 'artist:(${_cleanPrompt(artist)})',
      mode: 'easy',
    );
    return radio
        .map(_fromJspfTrack)
        .whereType<RecTrack>()
        .take(limit)
        .toList();
  }

  @override
  Future<List<RecArtist>> userTopArtists(
      {String period = '3month', int limit = 10}) async {
    if (!isLoggedIn) return const [];
    final rows = await _lb.getUserTopArtists(range: 'quarter', count: limit);
    return rows
        .map((a) => RecArtist(name: a['artist_name']?.toString() ?? ''))
        .where((a) => a.name.isNotEmpty)
        .toList();
  }

  @override
  Future<List<RecTrack>> tagTopTracks(String tag,
      {int limit = 30, int page = 1}) async {
    if (!isLoggedIn || tag.trim().isEmpty || page > 1) return const [];
    final raw = await _lb.getLbRadio(
      prompt: 'tag:(${_cleanPrompt(tag)})',
      mode: 'medium',
    );
    return raw.map(_fromJspfTrack).whereType<RecTrack>().take(limit).toList();
  }

  @override
  Future<List<RecTrack>> chartTopTracks({int limit = 50, int page = 1}) async {
    final offset = (page - 1) * limit;
    final rows = await _lb.getSitewideTopRecordings(
      range: chartRange,
      count: limit,
      offset: offset,
    );
    return rows.map(_fromRecording).whereType<RecTrack>().toList();
  }
}

