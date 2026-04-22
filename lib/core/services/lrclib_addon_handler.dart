import 'package:dio/dio.dart';
import '../models/addon_models.dart';
import 'user_addon_handler.dart';

/// Inbuilt addon for LRCLIB (synced lyrics database).
/// https://lrclib.net/docs
class LrcLibAddonHandler extends UserAddonHandler {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://lrclib.net/api',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    headers: {
      'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'accept-encoding': 'gzip, deflate, br, zstd',
      'accept-language': 'en-US,en;q=0.9',
      'cache-control': 'max-age=0',
      'connection': 'keep-alive',
      'host': 'lrclib.net',
      'sec-ch-ua': '"Google Chrome";v="147", "Not.A/Brand";v="8", "Chromium";v="147"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      'sec-fetch-dest': 'document',
      'sec-fetch-mode': 'navigate',
      'sec-fetch-site': 'none',
      'sec-fetch-user': '?1',
      'upgrade-insecure-requests': '1',
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
    },

  ));

  @override
  AddonManifest get manifest => AddonManifest(
        id: 'net.lrclib',
        name: 'LRCLIB',
        version: '1.0.0',
        description: 'Synced lyrics database. Provides high-quality lyrics for millions of tracks.',
        icon: null,
        resources: [AddonResource.lyrics],
        types: ['track'],
        contentType: AddonContentType.music,
        addonType: AddonType.user,
        baseUrl: null,
        installedAt: DateTime(2024, 1, 1),
        isBuiltIn: true,
      );

  @override
  Future<AddonSearchResult?> search(String query) async => null;

  @override
  Future<AddonStreamResult?> getStreamResult(String trackId) async => null;

  @override
  Future<String?> getLyrics(String artist, String title,
      {String? album, int? duration}) async {
    try {
      // 1. Try exact match first (/get)
      final response = await _dio.get('/get', queryParameters: {
        'artist_name': artist,
        'track_name': title,
        if (album != null && album.isNotEmpty) 'album_name': album,
        if (duration != null && duration > 0) 'duration': duration,
      });

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        // Prioritize synced lyrics
        return data['syncedLyrics'] ?? data['plainLyrics'];
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        // Not found via exact match, try search fallback
        return _searchFallback(artist, title);
      }
      print('[LRCLIB] getLyrics error: $e');
    }
    return null;
  }

  Future<String?> _searchFallback(String artist, String title) async {
    try {
      final response = await _dio.get('/search', queryParameters: {
        'q': '$artist $title',
      });

      if (response.statusCode == 200 && response.data is List && (response.data as List).isNotEmpty) {
        // Take the first result that has lyrics
        for (var item in response.data) {
          if (item['syncedLyrics'] != null || item['plainLyrics'] != null) {
            return item['syncedLyrics'] ?? item['plainLyrics'];
          }
        }
      }
    } catch (e) {
      print('[LRCLIB] searchFallback error: $e');
    }
    return null;
  }
}
