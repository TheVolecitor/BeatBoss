import 'package:darttubefix/darttubefix.dart';

import '../models/addon_models.dart';
import 'settings_service.dart';
import 'user_addon_handler.dart';
import 'ytmusic_innertube.dart';

/// Built-in YouTube Music addon powered by `WEB_REMIX` InnerTube + `darttubefix`.
/// Provides YouTube Music search (tracks, albums, artists, playlists),
/// catalog detail pages, and direct audio stream resolution.
class YouTubeMusicAddonHandler extends UserAddonHandler {
  static const String addonId = 'com.beatboss.ytmusic';

  final SettingsService _settings;
  final YtMusicInnerTube _ytm;

  YouTubeMusicAddonHandler({
    required SettingsService settingsService,
    YtMusicInnerTube? innerTube,
  })  : _settings = settingsService,
        _ytm = innerTube ?? YtMusicInnerTube();

  @override
  AddonManifest get manifest => AddonManifest(
        id: addonId,
        name: 'YouTube Music',
        version: '1.1.0',
        description:
            'Built-in YouTube Music search (songs, albums, artists, playlists) and audio playback.',
        icon: 'assets/yt_music_icon.png',
        resources: const [
          AddonResource.search,
          AddonResource.stream,
          AddonResource.catalog,
          AddonResource.lyrics,
          AddonResource.settings,
        ],
        types: const ['track', 'album', 'artist', 'playlist'],
        contentType: AddonContentType.music,
        addonType: AddonType.user,
        installedAt: DateTime.now(),
        isBuiltIn: true,
        settings: const [
          AddonSettingField(
            key: 'audioQuality',
            type: 'select',
            label: 'Audio quality',
            help: 'Choose between highest available bitrate or balanced data usage.',
            defaultValue: 'best',
            options: [
              AddonSettingOption(value: 'best', label: 'Best available'),
              AddonSettingOption(value: 'medium', label: 'Balanced (128kbps)'),
            ],
          ),
          AddonSettingField(
            key: 'preferOpus',
            type: 'toggle',
            label: 'Prefer Opus (WebM)',
            help: 'Uses Opus audio when available instead of AAC/M4A.',
            defaultValue: false,
          ),
        ],
      );

  int? _parseDurationSeconds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    if (parts.length == 2) return parts[0]! * 60 + parts[1]!;
    if (parts.length == 3) {
      return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
    }
    return null;
  }

  @override
  Future<AddonSearchResult?> search(String query) async {
    try {
      final ytmResult = await _ytm.search(query, addonId: addonId);
      if (!ytmResult.isEmpty) return ytmResult;

      // Fallback to darttubefix WEB_MUSIC search if InnerTube returned empty.
      final search = Search(query, client: 'WEB_MUSIC');
      await search.fetch();
      final tracks = <AddonTrack>[];
      for (final yt in search.videos.take(20)) {
        final id = yt.videoId;
        if (id.isEmpty) continue;
        tracks.add(AddonTrack(
          id: id,
          title: yt.title.isNotEmpty ? yt.title : 'Unknown Title',
          artist: yt.author.isNotEmpty ? yt.author : 'YouTube Music',
          duration: _parseDurationSeconds(yt.duration),
          artworkURL: yt.thumbnail.isNotEmpty
              ? yt.thumbnail
              : 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
          addonId: addonId,
        ));
      }
      final artists = [
        for (final a in search.artists)
          if (a.channelId.isNotEmpty)
            AddonArtist(
              id: a.channelId,
              name: a.title,
              artworkURL: a.thumbnail.isNotEmpty ? a.thumbnail : null,
              addonId: addonId,
            ),
      ];
      final albums = [
        for (final al in search.albums)
          if (al.playlistId.isNotEmpty)
            AddonAlbum(
              id: al.playlistId,
              title: al.title,
              artist: 'YouTube Music',
              artworkURL: al.thumbnail.isNotEmpty ? al.thumbnail : null,
              addonId: addonId,
            ),
      ];
      final playlists = [
        for (final pl in search.playlists)
          if (pl.playlistId.isNotEmpty)
            AddonPlaylist(
              id: pl.playlistId,
              title: pl.title,
              artworkURL: pl.thumbnail.isNotEmpty ? pl.thumbnail : null,
              addonId: addonId,
            ),
      ];
      return AddonSearchResult(
        tracks: tracks,
        albums: albums,
        artists: artists,
        playlists: playlists,
      );
    } catch (e) {
      print('[YouTubeMusicAddon] Search error: $e');
      return null;
    }
  }

  @override
  Future<AddonAlbum?> getAlbumDetail(String albumId) =>
      _ytm.getAlbumDetail(albumId, addonId: addonId);

  @override
  Future<AddonArtist?> getArtistDetail(String artistId) =>
      _ytm.getArtistDetail(artistId, addonId: addonId);

  @override
  Future<AddonPlaylist?> getPlaylistDetail(String playlistId) =>
      _ytm.getPlaylistDetail(playlistId, addonId: addonId);

  @override
  Future<String?> getLyrics(String artist, String title,
      {String? album, int? duration, String? trackId}) async {
    try {
      if (trackId != null && trackId.isNotEmpty) {
        final direct = await _ytm.getLyrics(trackId);
        if (direct != null && direct.isNotEmpty) return direct;
      }
      final searchRes = await _ytm.search('$artist $title', addonId: addonId);
      for (final t in searchRes.tracks.take(2)) {
        if (t.id == trackId) continue;
        final lyrics = await _ytm.getLyrics(t.id);
        if (lyrics != null && lyrics.isNotEmpty) return lyrics;
      }
    } catch (e) {
      print('[YouTubeMusicAddon] getLyrics error: $e');
    }
    return null;
  }

  static final _ytIdRe = RegExp(r'^[0-9A-Za-z_-]{11}$');

  @override
  Future<AddonStreamResult?> getStreamResult(String trackId) async {
    if (!_ytIdRe.hasMatch(trackId)) return null;
    final stored = _settings.getAddonSettings(addonId);
    final preferOpus =
        stored['preferOpus'] == true || stored['preferOpus']?.toString() == 'true';
    final qualityPref = stored['audioQuality']?.toString() ?? 'best';

    // Try clients known to yield direct non-SABR audio-only streams.
    for (final client in const ['ANDROID_VR', 'IOS', 'VISION_OS', 'WEB_MUSIC']) {
      try {
        final yt = YouTube(
          'https://music.youtube.com/watch?v=$trackId',
          client: client,
        );
        final streams = await yt.streams;
        final audioQuery = streams.audioOnly;
        if (audioQuery.fmtStreams.isEmpty) continue;

        Stream? selected;
        if (preferOpus) {
          final opusList = audioQuery.filter(subtype: 'webm').orderBy('abr').fmtStreams;
          if (opusList.isNotEmpty) selected = opusList.last;
        }
        if (selected == null) {
          final mp4List = audioQuery.filter(subtype: 'mp4').orderBy('abr').fmtStreams;
          if (mp4List.isNotEmpty) selected = mp4List.last;
        }
        if (qualityPref == 'medium' && audioQuery.fmtStreams.isNotEmpty) {
          final sorted = List<Stream>.from(audioQuery.fmtStreams)
            ..sort((a, b) => (a.bitrate ?? 0).compareTo(b.bitrate ?? 0));
          selected = sorted.firstWhere(
            (s) => (s.bitrate ?? 0) >= 96000,
            orElse: () => sorted.last,
          );
        }
        selected ??= audioQuery.orderBy('abr').last;
        if (selected == null || selected.url.isEmpty || selected.includesVideoTrack) {
          continue;
        }

        final isOpus = selected.mimeType.contains('webm') ||
            selected.mimeType.contains('opus');
        return AddonStreamResult(
          url: selected.url,
          format: isOpus ? 'opus' : 'm4a',
          quality: selected.abr ?? (isOpus ? 'Opus' : 'AAC'),
          codec: isOpus ? 'opus' : 'aac',
          container: isOpus ? 'ogg' : 'mp4',
          manifest: 'none',
        );
      } catch (e) {
        print('[YouTubeMusicAddon] Client $client failed for $trackId: $e');
      }
    }
    return null;
  }
}
