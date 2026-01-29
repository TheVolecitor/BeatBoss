import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/models.dart';

/// YouTube Service - mirrors Python YouTubeAPI class
/// Used ONLY to extract playlist metadata (track names), not for downloading
class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Extract playlist ID from URL
  String? extractPlaylistId(String url) {
    // Handle various YouTube URL formats
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

  /// Validate if URL is a YouTube playlist
  bool isValidPlaylistUrl(String url) {
    if (!url.contains('youtube.com') && !url.contains('music.youtube.com')) {
      return false;
    }
    return url.contains('list=');
  }

  /// Get playlist tracks (metadata only - title, channel)
  /// This is used to search DAB for matching tracks
  Future<List<YouTubePlaylistItem>> getPlaylistTracks(String url) async {
    final List<YouTubePlaylistItem> results = [];

    try {
      final playlistId = extractPlaylistId(url);
      if (playlistId == null) {
        print('[YouTube] Invalid playlist URL');
        return results;
      }

      print('[YouTube] Fetching playlist: $playlistId');

      // Get playlist videos
      await for (final video in _yt.playlists.getVideos(playlistId)) {
        results.add(YouTubePlaylistItem(
          videoId: video.id.value,
          title: video.title,
          channel: video.author,
        ));
      }

      print('[YouTube] Found ${results.length} tracks');
    } catch (e) {
      print('[YouTube] Error fetching playlist: $e');
    }

    return results;
  }

  /// Search YouTube (if needed for single video info)
  Future<YouTubePlaylistItem?> getVideoInfo(String videoId) async {
    try {
      final video = await _yt.videos.get(videoId);
      return YouTubePlaylistItem(
        videoId: video.id.value,
        title: video.title,
        channel: video.author,
      );
    } catch (e) {
      print('[YouTube] Error getting video info: $e');
      return null;
    }
  }

  void dispose() {
    _yt.close();
  }
}
