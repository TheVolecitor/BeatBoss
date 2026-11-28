import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/addon_models.dart';
import '../models/models.dart';

/// Lightweight YouTube Music (`WEB_REMIX`) InnerTube client for pure YT Music
/// search (tracks, artists, albums, playlists), catalog detail pages, and
/// playlist import.
class YtMusicInnerTube {
  static const String _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const String _clientVersion = '1.20251013.03.00';

  final http.Client _client;
  static final Map<String, String> _artworkCache = {};

  YtMusicInnerTube({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the highest-resolution artwork for a YouTube Music [videoId]
  /// via `next` (queue panel square album art) with `player` fallback, cached
  /// in memory per videoId.
  Future<String?> getTrackArtwork(String videoId) async {
    if (videoId.isEmpty) return null;
    final cached = _artworkCache[videoId];
    if (cached != null) return cached;

    String? best;
    final nextJson = await _post('next', {'videoId': videoId});
    if (nextJson != null) {
      final queueContents = nextJson['contents']
              ?['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']
          ?['watchNextTabbedResultsRenderer']?['tabs']?[0]?['tabRenderer']
          ?['content']?['musicQueueRenderer']?['content']
          ?['playlistPanelRenderer']?['contents'] as List?;
      if (queueContents != null) {
        for (final entry in queueContents) {
          final renderer = entry is Map
              ? entry['playlistPanelVideoRenderer'] as Map?
              : null;
          if (renderer == null) continue;
          if (renderer['videoId']?.toString() == videoId || best == null) {
            best = _bestThumb(renderer);
            if (renderer['videoId']?.toString() == videoId && best != null) {
              break;
            }
          }
        }
      }
    }

    if (best == null || best.contains('i.ytimg.com')) {
      final playerJson = await _post('player', {'videoId': videoId});
      final thumbs =
          playerJson?['videoDetails']?['thumbnail']?['thumbnails'] as List?;
      if (thumbs != null && thumbs.isNotEmpty) {
        final raw = thumbs.last?['url']?.toString();
        final upscaled = upscaleThumbnail(raw);
        if (upscaled != null && upscaled.isNotEmpty) {
          best = upscaled;
        }
      }
    }

    if (best != null && best.isNotEmpty) {
      _artworkCache[videoId] = best;
    }
    return best;
  }

  /// Fetches synced or plain lyrics for a YouTube Music [videoId] via `next`
  /// (Lyrics tab `MPLYt_...`) + `browse`. Returns null if unavailable.
  Future<String?> getLyrics(String videoId) async {
    if (videoId.isEmpty) return null;
    final nextJson = await _post('next', {'videoId': videoId});
    if (nextJson == null) return null;

    final tabs = nextJson['contents']
            ?['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']
        ?['watchNextTabbedResultsRenderer']?['tabs'] as List?;
    if (tabs == null) return null;

    String? lyricsBrowseId;
    for (final tab in tabs) {
      final tr = tab is Map ? tab['tabRenderer'] as Map? : null;
      if (tr == null) continue;
      final bid = tr['endpoint']?['browseEndpoint']?['browseId']?.toString();
      final title = tr['title']?.toString().toLowerCase() ?? '';
      if (bid != null &&
          bid.isNotEmpty &&
          (bid.startsWith('MPLYt_') || title == 'lyrics')) {
        lyricsBrowseId = bid;
        break;
      }
    }
    if (lyricsBrowseId == null) return null;

    final browseJson = await _post('browse', {'browseId': lyricsBrowseId});
    if (browseJson == null) return null;

    final sections = browseJson['contents']?['sectionListRenderer']
        ?['contents'] as List?;
    if (sections != null) {
      for (final section in sections) {
        if (section is! Map) continue;
        final desc = section['musicDescriptionShelfRenderer']?['description']
            ?['runs'];
        final text = _runsText(desc);
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  Map<String, dynamic> get _context => {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': _clientVersion,
          },
        },
      };

  Map<String, String> get _headers => const {
        'User-Agent': 'Mozilla/5.0',
        'X-Youtube-Client-Name': '67',
        'X-Youtube-Client-Version': _clientVersion,
        'Origin': 'https://music.youtube.com',
        'Referer': 'https://music.youtube.com/',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>?> _post(
    String endpoint,
    Map<String, dynamic> extra,
  ) async {
    try {
      final body = {..._context, ...extra};
      final resp = await _client.post(
        Uri.parse(
            'https://music.youtube.com/youtubei/v1/$endpoint?key=$_apiKey&prettyPrint=false'),
        headers: _headers,
        body: jsonEncode(body),
      );
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      print('[YtMusicInnerTube] $endpoint error: $e');
      return null;
    }
  }

  /// Searches YouTube Music (`WEB_REMIX`) and returns tracks, albums,
  /// artists, and playlists. Songs are placed before music videos.
  Future<AddonSearchResult> search(
    String query, {
    required String addonId,
  }) async {
    final json = await _post('search', {'query': query});
    if (json == null) return AddonSearchResult();

    final songs = <AddonTrack>[];
    final videos = <AddonTrack>[];
    final albums = <AddonAlbum>[];
    final artists = <AddonArtist>[];
    final playlists = <AddonPlaylist>[];
    final seenTracks = <String>{};
    final seenAlbums = <String>{};
    final seenArtists = <String>{};
    final seenPlaylists = <String>{};

    void addTrack(AddonTrack t, {bool isVideo = false}) {
      if (t.id.isEmpty || !seenTracks.add(t.id)) return;
      if (isVideo) {
        videos.add(t);
      } else {
        songs.add(t);
      }
    }

    void addAlbum(AddonAlbum a) {
      if (a.id.isEmpty || !seenAlbums.add(a.id)) return;
      albums.add(a);
    }

    void addArtist(AddonArtist a) {
      if (a.id.isEmpty || !seenArtists.add(a.id)) return;
      artists.add(a);
    }

    void addPlaylist(AddonPlaylist p) {
      if (p.id.isEmpty || !seenPlaylists.add(p.id)) return;
      playlists.add(p);
    }

    final tabs = json['contents']?['tabbedSearchResultsRenderer']?['tabs'];
    final firstTab = (tabs is List && tabs.isNotEmpty) ? tabs.first : null;
    List? sections;
    if (firstTab is Map) {
      sections = firstTab['tabRenderer']?['content']?['sectionListRenderer']
          ?['contents'] as List?;
    }

    if (sections != null) {
      for (final section in sections) {
        if (section is! Map) continue;

        final card = section['musicCardShelfRenderer'];
        if (card is Map) {
          _parseTopCard(
            card,
            addonId: addonId,
            onTrack: (t, isVid) => addTrack(t, isVideo: isVid),
            onAlbum: addAlbum,
            onArtist: addArtist,
            onPlaylist: addPlaylist,
          );
          final cardContents = card['contents'] as List?;
          if (cardContents != null) {
            for (final c in cardContents) {
              if (c is Map && c['musicResponsiveListItemRenderer'] is Map) {
                _parseListItem(
                  c['musicResponsiveListItemRenderer'] as Map,
                  shelfHint: 'videos',
                  addonId: addonId,
                  onTrack: (t, isVid) => addTrack(t, isVideo: isVid),
                  onAlbum: addAlbum,
                  onArtist: addArtist,
                  onPlaylist: addPlaylist,
                );
              }
            }
          }
        }

        final itemSection = section['itemSectionRenderer'];
        if (itemSection is Map) {
          final contents = itemSection['contents'] as List?;
          if (contents != null) {
            for (final item in contents) {
              if (item is! Map) continue;
              if (item['musicResponsiveListItemRenderer'] is Map) {
                _parseListItem(
                  item['musicResponsiveListItemRenderer'] as Map,
                  shelfHint: '',
                  addonId: addonId,
                  onTrack: (t, isVid) => addTrack(t, isVideo: isVid),
                  onAlbum: addAlbum,
                  onArtist: addArtist,
                  onPlaylist: addPlaylist,
                );
              }
            }
          }
        }

        final shelf = section['musicShelfRenderer'];
        if (shelf is Map) {
          final shelfTitle = _runsText(shelf['title']?['runs']).toLowerCase();
          final contents = shelf['contents'] as List?;
          if (contents != null) {
            for (final item in contents) {
              if (item is Map && item['musicResponsiveListItemRenderer'] is Map) {
                _parseListItem(
                  item['musicResponsiveListItemRenderer'] as Map,
                  shelfHint: shelfTitle,
                  addonId: addonId,
                  onTrack: (t, isVid) => addTrack(t, isVideo: isVid),
                  onAlbum: addAlbum,
                  onArtist: addArtist,
                  onPlaylist: addPlaylist,
                );
              }
            }
          }
        }
      }
    }

    return AddonSearchResult(
      tracks: [...songs, ...videos],
      albums: albums,
      artists: artists,
      playlists: playlists,
    );
  }

  /// Fetches full album metadata and tracklist (`MPREb_...`).
  Future<AddonAlbum?> getAlbumDetail(
    String albumId, {
    required String addonId,
  }) async {
    final json = await _post('browse', {'browseId': albumId});
    if (json == null) return null;

    final header = _findHeader(json);
    final title = _runsText(header?['title']?['runs']);
    final artwork = _bestThumb(header);
    final subtitleRuns = _textRuns(header?['subtitle']?['runs']);
    final artist = _pickArtistFromRuns(subtitleRuns) ?? 'Unknown Artist';
    final year = _pickYearFromRuns(subtitleRuns);

    final tracks = <AddonTrack>[];
    for (final item in _collectListItems(json)) {
      _parseListItem(
        item,
        shelfHint: 'songs',
        addonId: addonId,
        defaultArtist: artist,
        defaultAlbum: title,
        defaultArtwork: artwork,
        onTrack: (t, _) => tracks.add(t),
      );
    }

    if (title.isEmpty && tracks.isEmpty) return null;
    return AddonAlbum(
      id: albumId,
      title: title.isNotEmpty ? title : 'Album',
      artist: artist,
      artworkURL: artwork,
      year: year,
      trackCount: tracks.length,
      tracks: tracks,
      addonId: addonId,
    );
  }

  /// Fetches full artist metadata, top tracks, and albums (`UC...`).
  Future<AddonArtist?> getArtistDetail(
    String artistId, {
    required String addonId,
  }) async {
    final json = await _post('browse', {'browseId': artistId});
    if (json == null) return null;

    final header = _findHeader(json);
    final name = _runsText(header?['title']?['runs']);
    final artwork = _bestThumb(header);

    final topTracks = <AddonTrack>[];
    final albums = <AddonAlbum>[];
    final seenTracks = <String>{};
    final seenAlbums = <String>{};

    for (final item in _collectListItems(json)) {
      _parseListItem(
        item,
        shelfHint: 'songs',
        addonId: addonId,
        defaultArtist: name,
        onTrack: (t, _) {
          if (seenTracks.add(t.id)) topTracks.add(t);
        },
        onAlbum: (a) {
          if (seenAlbums.add(a.id)) albums.add(a);
        },
      );
    }

    for (final card in _collectTwoRowItems(json)) {
      final nav = card['navigationEndpoint']?['browseEndpoint'] as Map?;
      final browseId = nav?['browseId']?.toString() ?? '';
      final pageType = nav?['browseEndpointContextSupportedConfigs']
              ?['browseEndpointContextMusicConfig']?['pageType']
          ?.toString();
      if (browseId.isEmpty) continue;
      if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' || browseId.startsWith('MPREb_')) {
        if (!seenAlbums.add(browseId)) continue;
        final title = _runsText(card['title']?['runs']);
        final subRuns = _textRuns(card['subtitle']?['runs']);
        albums.add(AddonAlbum(
          id: browseId,
          title: title,
          artist: name.isNotEmpty ? name : 'Artist',
          artworkURL: _bestThumb(card),
          year: _pickYearFromRuns(subRuns),
          addonId: addonId,
        ));
      }
    }

    if (name.isEmpty && topTracks.isEmpty && albums.isEmpty) return null;
    return AddonArtist(
      id: artistId,
      name: name.isNotEmpty ? name : 'Artist',
      artworkURL: artwork,
      topTracks: topTracks,
      albums: albums,
      addonId: addonId,
    );
  }

  /// Fetches full playlist metadata and tracks (`VL...` or `PL...`).
  Future<AddonPlaylist?> getPlaylistDetail(
    String playlistId, {
    required String addonId,
  }) async {
    final browseId =
        playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
    final json = await _post('browse', {'browseId': browseId});
    if (json == null) return null;

    final header = _findHeader(json);
    final title = _runsText(header?['title']?['runs']);
    final artwork = _bestThumb(header);
    final subRuns = _textRuns(header?['subtitle']?['runs']);
    final creator = _pickArtistFromRuns(subRuns);

    final tracks = <AddonTrack>[];
    final seen = <String>{};
    for (final item in _collectListItems(json)) {
      _parseListItem(
        item,
        shelfHint: 'songs',
        addonId: addonId,
        onTrack: (t, _) {
          if (seen.add(t.id)) tracks.add(t);
        },
      );
    }

    if (title.isEmpty && tracks.isEmpty) return null;
    return AddonPlaylist(
      id: playlistId,
      title: title.isNotEmpty ? title : 'Playlist',
      creator: creator,
      artworkURL: artwork,
      trackCount: tracks.length,
      tracks: tracks,
      addonId: addonId,
    );
  }

  /// Fetches playlist items for YT Music / YouTube import (replacing
  /// `youtube_explode_dart`). Tries YouTube Music `WEB_REMIX` browse with
  /// continuations first, then falls back to `darttubefix` `WEB` browse.
  Future<List<YouTubePlaylistItem>> getPlaylistItems(String playlistId) async {
    final browseId =
        playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
    final items = <YouTubePlaylistItem>[];
    final seen = <String>{};

    Map<String, dynamic>? page = await _post('browse', {'browseId': browseId});
    var safety = 0;
    while (page != null && safety < 25) {
      safety++;
      for (final raw in _collectListItems(page)) {
        _parseListItem(
          raw,
          shelfHint: 'songs',
          addonId: 'import',
          onTrack: (t, _) {
            if (t.id.isNotEmpty && seen.add(t.id)) {
              items.add(YouTubePlaylistItem(
                videoId: t.id,
                title: t.title,
                channel: t.artist,
              ));
            }
          },
        );
      }
      final cont = _extractContinuation(page);
      if (cont == null || cont.isEmpty) break;
      page = await _post('browse', {'continuation': cont});
    }

    if (items.isNotEmpty) return items;

    // Fallback for standard YouTube playlists via YouTube WEB InnerTube.
    try {
      final resp = await _client.post(
        Uri.parse(
            'https://www.youtube.com/youtubei/v1/browse?key=$_apiKey&prettyPrint=false'),
        headers: const {
          'User-Agent': 'Mozilla/5.0',
          'X-Youtube-Client-Name': '1',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'context': {
            'client': {
              'clientName': 'WEB',
              'clientVersion': '2.20251021.01.00',
            },
          },
          'browseId': browseId,
        }),
      );
      if (resp.statusCode == 200) {
        final webJson = jsonDecode(resp.body);
        for (final raw in _collectPlaylistVideoRenderers(webJson)) {
          final vid = raw['videoId']?.toString() ?? '';
          final title = _runsText(raw['title']?['runs']);
          final author = _runsText(raw['shortBylineText']?['runs']);
          if (vid.isNotEmpty && title.isNotEmpty && seen.add(vid)) {
            items.add(YouTubePlaylistItem(
              videoId: vid,
              title: title,
              channel: author.isNotEmpty ? author : 'YouTube',
            ));
          }
        }
      }
    } catch (e) {
      print('[YtMusicInnerTube] WEB browse fallback error: $e');
    }

    return items;
  }

  // ---- Parsing helpers ----

  void _parseTopCard(
    Map card, {
    required String addonId,
    required void Function(AddonTrack, bool isVideo) onTrack,
    required void Function(AddonAlbum) onAlbum,
    required void Function(AddonArtist) onArtist,
    required void Function(AddonPlaylist) onPlaylist,
  }) {
    final title = _runsText(card['title']?['runs']);
    if (title.isEmpty) return;
    final thumb = _bestThumb(card);
    final subRuns = _textRuns(card['subtitle']?['runs']);
    final nav = card['title']?['runs']?[0]?['navigationEndpoint'] as Map? ??
        card['onTap'] as Map?;
    final browse = nav?['browseEndpoint'] as Map?;
    final browseId = browse?['browseId']?.toString() ?? '';
    final pageType = browse?['browseEndpointContextSupportedConfigs']
            ?['browseEndpointContextMusicConfig']?['pageType']
        ?.toString();
    final watchVid = nav?['watchEndpoint']?['videoId']?.toString() ?? '';

    if (pageType == 'MUSIC_PAGE_TYPE_ARTIST' || browseId.startsWith('UC')) {
      onArtist(AddonArtist(
        id: browseId,
        name: title,
        artworkURL: thumb,
        addonId: addonId,
      ));
    } else if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' ||
        browseId.startsWith('MPREb_')) {
      onAlbum(AddonAlbum(
        id: browseId,
        title: title,
        artist: _pickArtistFromRuns(subRuns) ?? 'Unknown Artist',
        artworkURL: thumb,
        year: _pickYearFromRuns(subRuns),
        addonId: addonId,
      ));
    } else if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST' ||
        browseId.startsWith('VL') ||
        browseId.startsWith('PL')) {
      onPlaylist(AddonPlaylist(
        id: browseId,
        title: title,
        creator: _pickArtistFromRuns(subRuns),
        artworkURL: thumb,
        addonId: addonId,
      ));
    } else if (watchVid.isNotEmpty) {
      final isVid = subRuns.any((s) => s.toLowerCase() == 'video');
      onTrack(
        AddonTrack(
          id: watchVid,
          title: title,
          artist: _pickArtistFromRuns(subRuns) ?? 'YouTube Music',
          duration: _pickDurationFromRuns(subRuns),
          artworkURL: thumb ?? 'https://i.ytimg.com/vi/$watchVid/hqdefault.jpg',
          addonId: addonId,
        ),
        isVid,
      );
    }
  }

  void _parseListItem(
    Map item, {
    required String shelfHint,
    required String addonId,
    String? defaultArtist,
    String? defaultAlbum,
    String? defaultArtwork,
    void Function(AddonTrack, bool isVideo)? onTrack,
    void Function(AddonAlbum)? onAlbum,
    void Function(AddonArtist)? onArtist,
    void Function(AddonPlaylist)? onPlaylist,
  }) {
    final flex = item['flexColumns'] as List?;
    if (flex == null || flex.isEmpty) return;

    final col0 = flex[0]?['musicResponsiveListItemFlexColumnRenderer']?['text'];
    final title = _runsText(col0?['runs']);
    if (title.isEmpty) return;

    final col1Runs = flex.length > 1
        ? _textRuns(
            flex[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']
                ?['runs'],
          )
        : const <String>[];
    final fixedCols = item['fixedColumns'] as List?;
    final fixedRuns = (fixedCols != null && fixedCols.isNotEmpty)
        ? _textRuns(
            fixedCols[0]?['musicResponsiveListItemFixedColumnRenderer']?['text']
                ?['runs'],
          )
        : const <String>[];

    final thumb = _bestThumb(item) ?? defaultArtwork;

    final nav = item['navigationEndpoint'] as Map? ??
        col0?['runs']?[0]?['navigationEndpoint'] as Map?;
    final browse = nav?['browseEndpoint'] as Map?;
    final browseId = browse?['browseId']?.toString() ?? '';
    final pageType = browse?['browseEndpointContextSupportedConfigs']
            ?['browseEndpointContextMusicConfig']?['pageType']
        ?.toString();

    final overlayNav = item['overlay']?['musicItemThumbnailOverlayRenderer']
            ?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']
        as Map?;
    final watch = (overlayNav?['watchEndpoint'] ??
            nav?['watchEndpoint'] ??
            item['playlistItemData'])
        as Map?;
    final videoId = watch?['videoId']?.toString() ?? '';
    final videoType = watch?['watchEndpointMusicSupportedConfigs']
            ?['watchEndpointMusicConfig']?['musicVideoType']
        ?.toString();

    if (pageType == 'MUSIC_PAGE_TYPE_ARTIST' ||
        (shelfHint == 'artists' && browseId.isNotEmpty)) {
      onArtist?.call(AddonArtist(
        id: browseId,
        name: title,
        artworkURL: thumb,
        addonId: addonId,
      ));
      return;
    }

    if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' ||
        browseId.startsWith('MPREb_') ||
        (shelfHint == 'albums' && browseId.isNotEmpty)) {
      onAlbum?.call(AddonAlbum(
        id: browseId,
        title: title,
        artist: _pickArtistFromRuns(col1Runs) ?? defaultArtist ?? 'Unknown Artist',
        artworkURL: thumb,
        year: _pickYearFromRuns(col1Runs),
        addonId: addonId,
      ));
      return;
    }

    if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST' ||
        (shelfHint.contains('playlist') && browseId.isNotEmpty)) {
      onPlaylist?.call(AddonPlaylist(
        id: browseId,
        title: title,
        creator: _pickArtistFromRuns(col1Runs),
        artworkURL: thumb,
        addonId: addonId,
      ));
      return;
    }

    if (videoId.isNotEmpty) {
      final isVideo = shelfHint == 'videos' ||
          videoType == 'MUSIC_VIDEO_TYPE_OMV' ||
          videoType == 'MUSIC_VIDEO_TYPE_UGC' ||
          col1Runs.any((s) => s.toLowerCase() == 'video');
      final duration = _pickDurationFromRuns(fixedRuns) ??
          _pickDurationFromRuns(col1Runs);
      final artist =
          _pickArtistFromRuns(col1Runs) ?? defaultArtist ?? 'YouTube Music';
      final album = _pickAlbumFromRuns(col1Runs) ?? defaultAlbum;
      onTrack?.call(
        AddonTrack(
          id: videoId,
          title: title,
          artist: artist,
          album: album,
          duration: duration,
          artworkURL: thumb ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
          addonId: addonId,
        ),
        isVideo,
      );
    }
  }

  static String _runsText(dynamic runs) {
    if (runs is! List) return '';
    return runs
        .whereType<Map>()
        .map((r) => r['text']?.toString() ?? '')
        .join()
        .trim();
  }

  static List<String> _textRuns(dynamic runs) {
    if (runs is! List) return const [];
    return [
      for (final r in runs)
        if (r is Map)
          for (final part in (r['text']?.toString() ?? '').split('•'))
            if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static String? _bestThumb(Map? node) {
    if (node == null) return null;
    final thumbs = (node['thumbnail']?['musicThumbnailRenderer']?['thumbnail']
                ?['thumbnails'] ??
            node['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']
                ?['thumbnails'] ??
            node['thumbnail']?['thumbnails'])
        as List?;
    if (thumbs == null || thumbs.isEmpty) return null;
    final raw = thumbs.last?['url']?.toString();
    return upscaleThumbnail(raw);
  }

  /// Requests a crisp 1200px image from YouTube Music's CDN instead of the
  /// small search-preview sizes (e.g. w120-h120 or s120).
  static String? upscaleThumbnail(String? url) {
    if (url == null || url.isEmpty) return url;
    if (url.contains('lh3.googleusercontent.com') ||
        url.contains('yt3.ggpht.com')) {
      final resizedWh = url.replaceFirst(
          RegExp(r'=w\d+-h\d+[^?&#]*'), '=w1200-h1200-l90-rj');
      if (resizedWh != url) return resizedWh;
      return url.replaceFirst(RegExp(r'=s\d+[^?&#]*'), '=s1200');
    }
    if (url.contains('i.ytimg.com/vi/')) {
      return url.replaceFirst(
          RegExp(r'/(default|mqdefault|hqdefault)\.jpg'), '/sddefault.jpg');
    }
    return url;
  }

  static bool _isNoiseRun(String s) {
    final lower = s.toLowerCase();
    return const {
          'song',
          'video',
          'album',
          'single',
          'ep',
          'playlist',
          'artist',
        }.contains(lower) ||
        RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(s) ||
        RegExp(r'^\d{4}$').hasMatch(s) ||
        lower.endsWith('plays') ||
        lower.endsWith('views') ||
        lower.endsWith('subscribers') ||
        lower.endsWith('songs') ||
        lower.endsWith('tracks');
  }

  static String? _pickArtistFromRuns(List<String> runs) {
    for (final r in runs) {
      if (!_isNoiseRun(r)) return r;
    }
    return null;
  }

  static String? _pickAlbumFromRuns(List<String> runs) {
    final meaningful = runs.where((r) => !_isNoiseRun(r)).toList();
    return meaningful.length >= 2 ? meaningful[1] : null;
  }

  static String? _pickYearFromRuns(List<String> runs) {
    for (final r in runs) {
      if (RegExp(r'^\d{4}$').hasMatch(r)) return r;
    }
    return null;
  }

  static int? _pickDurationFromRuns(List<String> runs) {
    for (final r in runs) {
      if (!RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(r)) continue;
      final parts = r.split(':').map(int.tryParse).toList();
      if (parts.any((p) => p == null)) continue;
      if (parts.length == 2) return parts[0]! * 60 + parts[1]!;
      if (parts.length == 3) {
        return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
      }
    }
    return null;
  }

  static Map? _findHeader(Map json) {
    final header = json['header'];
    if (header is Map) {
      return (header['musicResponsiveHeaderRenderer'] ??
              header['musicDetailHeaderRenderer'] ??
              header['musicImmersiveHeaderRenderer'] ??
              header['musicVisualHeaderRenderer'])
          as Map?;
    }
    // Two-column browse layout (newer YT Music albums/playlists)
    final col = json['contents']?['twoColumnBrowseResultsRenderer']?['tabs']?[0]
        ?['tabRenderer']?['content']?['sectionListRenderer']?['contents']?[0];
    if (col is Map) {
      return (col['musicResponsiveHeaderRenderer'] ??
              col['musicEditablePlaylistDetailHeaderRenderer']?['header']
                  ?['musicResponsiveHeaderRenderer'])
          as Map?;
    }
    return null;
  }

  static List<Map> _collectListItems(dynamic node) {
    final out = <Map>[];
    void walk(dynamic n) {
      if (n is Map) {
        if (n['musicResponsiveListItemRenderer'] is Map) {
          out.add(n['musicResponsiveListItemRenderer'] as Map);
        } else {
          for (final v in n.values) {
            walk(v);
          }
        }
      } else if (n is List) {
        for (final item in n) {
          walk(item);
        }
      }
    }

    walk(node);
    return out;
  }

  static List<Map> _collectTwoRowItems(dynamic node) {
    final out = <Map>[];
    void walk(dynamic n) {
      if (n is Map) {
        if (n['musicTwoRowItemRenderer'] is Map) {
          out.add(n['musicTwoRowItemRenderer'] as Map);
        } else {
          for (final v in n.values) {
            walk(v);
          }
        }
      } else if (n is List) {
        for (final item in n) {
          walk(item);
        }
      }
    }

    walk(node);
    return out;
  }

  static List<Map> _collectPlaylistVideoRenderers(dynamic node) {
    final out = <Map>[];
    void walk(dynamic n) {
      if (n is Map) {
        if (n['playlistVideoRenderer'] is Map) {
          out.add(n['playlistVideoRenderer'] as Map);
        } else {
          for (final v in n.values) {
            walk(v);
          }
        }
      } else if (n is List) {
        for (final item in n) {
          walk(item);
        }
      }
    }

    walk(node);
    return out;
  }

  static String? _extractContinuation(dynamic node) {
    String? found;
    void walk(dynamic n) {
      if (found != null) return;
      if (n is Map) {
        final next = n['nextContinuationData']?['continuation']?.toString() ??
            n['continuationEndpoint']?['continuationCommand']?['token']
                ?.toString();
        if (next != null && next.isNotEmpty) {
          found = next;
          return;
        }
        for (final v in n.values) {
          walk(v);
        }
      } else if (n is List) {
        for (final item in n) {
          walk(item);
        }
      }
    }

    walk(node);
    return found;
  }
}

