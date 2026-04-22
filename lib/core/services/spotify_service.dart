import 'package:dio/dio.dart';

/// Spotify Service - Scrapes public playlist data
class SpotifyService {
  final Dio _dio = Dio();

  SpotifyService() {
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
    };
  }

  bool isValidPlaylistUrl(String url) {
    return url.contains('open.spotify.com/playlist/');
  }

  Future<List<SpotifyPlaylistItem>> getPlaylistTracks(String url) async {
    final List<SpotifyPlaylistItem> results = [];
    try {
      String? playlistId;

      // Extract ID from URL
      if (url.contains('playlist/')) {
        // Handle https://open.spotify.com/playlist/ID?si=...
        final RegExp regex = RegExp(r'playlist/([a-zA-Z0-9]+)');
        final match = regex.firstMatch(url);
        if (match != null) {
          playlistId = match.group(1);
        }
      }

      if (playlistId == null) {
        print('[Spotify] Could not extract playlist ID');
        return [];
      }

      final workerUrl =
          'https://beatboss-spotify.thevolecitor.workers.dev/?playlist=$playlistId';
      print('[Spotify] Fetching from: $workerUrl');

      final response = await _dio.get(workerUrl);

      if (response.statusCode == 200 && response.data is List) {
        for (var item in response.data) {
          final name = item['name'] as String?;
          final artist = item['artist'] as String?;

          if (name != null && artist != null) {
            results.add(SpotifyPlaylistItem(
              title: name,
              artist: artist,
            ));
          }
        }
      }
    } catch (e) {
      print('[Spotify] Error: $e');
    }
    return results;
  }
}

class SpotifyPlaylistItem {
  final String title;
  final String artist;
  SpotifyPlaylistItem({required this.title, required this.artist});
}
