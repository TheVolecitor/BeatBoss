import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/addon_models.dart';
import 'user_addon_handler.dart';

/// Inbuilt addon for LRCLIB (synced lyrics database).
/// https://lrclib.net/docs
class LrcLibAddonHandler extends UserAddonHandler {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://lrclib.net/api',
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
    headers: kIsWeb ? {} : {
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
      {String? album, int? duration, String? trackId}) async {
    final durSeconds = duration != null && duration > 10000
        ? duration ~/ 1000
        : duration;
    try {
      // 1. Try exact match first (/get)
      final response = await _dio.get('/get', queryParameters: {
        'artist_name': artist,
        'track_name': title,
        if (album != null && album.isNotEmpty) 'album_name': album,
        if (durSeconds != null && durSeconds > 0) 'duration': durSeconds,
      });

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final text = (data['syncedLyrics'] ?? data['plainLyrics'])?.toString();
        if (text != null && text.trim().isNotEmpty) return text;
      }
    } catch (e) {
      if (e is! DioException || e.response?.statusCode != 404) {
        print('[LRCLIB] getLyrics error: $e');
      }
    }
    return _searchFallback(artist, title);
  }

  String _cleanQueryPart(String input) {
    return input
        .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), '')
        .replaceAll(RegExp(r'\s+(feat\.?|ft\.?|with)\s+.*$', caseSensitive: false), '')
        .trim();
  }

  Future<String?> _searchFallback(String artist, String title) async {
    final primaryArtist = artist.split(RegExp(r'\s*[,&]\s*')).first.trim();
    final queries = <String>{
      '$artist $title'.trim(),
      '${_cleanQueryPart(primaryArtist)} ${_cleanQueryPart(title)}'.trim(),
      _cleanQueryPart(title),
    }..removeWhere((q) => q.isEmpty);

    for (final q in queries) {
      try {
        final response = await _dio.get('/search', queryParameters: {'q': q});
        if (response.statusCode == 200 &&
            response.data is List &&
            (response.data as List).isNotEmpty) {
          for (final item in response.data) {
            final text =
                (item['syncedLyrics'] ?? item['plainLyrics'])?.toString();
            if (text != null && text.trim().isNotEmpty) return text;
          }
        }
      } catch (e) {
        print('[LRCLIB] searchFallback error: $e');
      }
    }
    return null;
  }
}
