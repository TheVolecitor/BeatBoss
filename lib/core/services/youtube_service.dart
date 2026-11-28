import 'package:darttubefix/darttubefix.dart';

import '../models/models.dart';
import 'ytmusic_innertube.dart';

/// YouTube / YouTube Music playlist metadata service powered by
/// `YtMusicInnerTube` (`WEB_REMIX`) and `darttubefix` (no `youtube_explode_dart`).
class YouTubeService {
  final YtMusicInnerTube _ytm;

  YouTubeService({YtMusicInnerTube? innerTube})
      : _ytm = innerTube ?? YtMusicInnerTube();

  /// Extract playlist ID from URL.
  String? extractPlaylistId(String url) {
    final patterns = [
      RegExp(r'[?&]list=([a-zA-Z0-9_-]+)'),
      RegExp(r'playlist\?list=([a-zA-Z0-9_-]+)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Validate if URL is a YouTube or YouTube Music playlist.
  bool isValidPlaylistUrl(String url) {
    if (!url.contains('youtube.com') && !url.contains('music.youtube.com')) {
      return false;
    }
    return url.contains('list=');
  }

  /// Get playlist tracks (metadata only - title, channel) using YouTube Music
  /// InnerTube (`WEB_REMIX`) with `darttubefix` WEB fallback.
  Future<List<YouTubePlaylistItem>> getPlaylistTracks(String url) async {
    try {
      final playlistId = extractPlaylistId(url);
      if (playlistId == null) {
        print('[YouTube] Invalid playlist URL');
        return const [];
      }

      print('[YouTube] Fetching playlist via YT Music InnerTube: $playlistId');
      final results = await _ytm.getPlaylistItems(playlistId);
      print('[YouTube] Found ${results.length} tracks');
      return results;
    } catch (e) {
      print('[YouTube] Error fetching playlist: $e');
      return const [];
    }
  }

  /// Fetch single video/song info via `darttubefix`.
  Future<YouTubePlaylistItem?> getVideoInfo(String videoId) async {
    try {
      final yt = YouTube(
        'https://music.youtube.com/watch?v=$videoId',
        client: 'WEB_MUSIC',
      );
      final title = await yt.title;
      final author = await yt.author;
      return YouTubePlaylistItem(
        videoId: videoId,
        title: title,
        channel: author,
      );
    } catch (e) {
      print('[YouTube] Error getting video info: $e');
      return null;
    }
  }

  void dispose() {}
}
