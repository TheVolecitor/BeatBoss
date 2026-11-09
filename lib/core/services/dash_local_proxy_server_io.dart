import 'dart:io';
import 'package:http/http.dart' as http;
import 'dash_native_parser.dart';
import 'stream_cache/cache_models.dart';

class DashLocalProxyServer {
  static HttpServer? _server;
  static DashManifest? _currentManifest;
  static String? _proxyUrl;
  static double Function()? _getPosition;
  // Local stream cache sink; the first request after start() takes it.
  static CacheByteSink? _sink;

  static Future<String> start(DashManifest manifest, {String? proxyUrl, double Function()? getPosition, CacheByteSink? sink}) async {
    _currentManifest = manifest;
    _proxyUrl = proxyUrl;
    _getPosition = getPosition;
    _sink = sink;

    if (_server == null) {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      print('[DashLocalProxyServer] Started on port ${_server!.port}');
      _server!.listen(_handleRequest);
    }

    return 'http://127.0.0.1:${_server!.port}/stream';
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    if (_currentManifest == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    print('[DashLocalProxyServer] Handling request for continuous fMP4 stream...');

    final response = request.response;
    response.headers.contentType = ContentType('audio', 'mp4');

    // Some players expect Accept-Ranges to not fail immediately.
    response.headers.set('Accept-Ranges', 'none');

    final manifest = _currentManifest!;

    // The cache sink belongs to the first request, which streams the track
    // from its first segment. A later request (e.g. after a seek) restarts
    // the stream and must not write into the same file.
    final sink = _sink;
    _sink = null;
    var streamComplete = false;

    // Client writes never throw out of here: with a cache sink the download
    // keeps going after the player has disconnected.
    var clientAlive = true;
    Future<void> send(List<int> data) async {
      if (!clientAlive) return;
      try {
        response.add(data);
        await response.flush();
      } catch (_) {
        clientAlive = false;
      }
    }

    try {
      // 1. Fetch and pipe the Init Segment
      final initUrl = _proxy(manifest.initSegmentUrl);
      print('[DashLocalProxyServer] Fetching Init Segment: $initUrl');
      final initResp = await http.get(Uri.parse(initUrl));
      if (initResp.statusCode == 200 || initResp.statusCode == 206) {
        await sink?.add(initResp.bodyBytes);
        await send(initResp.bodyBytes);
      } else {
        throw Exception('Init Segment failed: ${initResp.statusCode}');
      }

      // 2. Fetch and pipe Media Segments sequentially
      for (int i = 0; i < manifest.mediaSegmentUrls.length; i++) {
        // If client disconnected, stop fetching (unless the cache still needs
        // the remaining segments)
        if (!clientAlive || request.response.connectionInfo == null) {
          clientAlive = false;
          if (sink == null || !sink.isActive) {
            print('[DashLocalProxyServer] Client disconnected, stopping stream.');
            break;
          }
        }

        // Throttle fetching so we don't download the whole file instantly.
        // Not while caching: the cache download runs ahead at full speed.
        if (sink == null && _getPosition != null && manifest.segmentDuration > 0) {
          final currentPos = _getPosition!();
          final segmentStartPos = i * manifest.segmentDuration;
          final leadTime = segmentStartPos - currentPos;

          // If we are more than 15 seconds ahead, wait until we are closer
          if (leadTime > 15.0) {
            print('[DashLocalProxyServer] Throttling fetch (lead time: ${leadTime.toStringAsFixed(1)}s)');
            bool clientConnected = true;
            while (_getPosition != null) {
              if (request.response.connectionInfo == null) {
                clientConnected = false;
                break;
              }
              final newPos = _getPosition!();
              if (segmentStartPos - newPos <= 10.0) {
                break;
              }
              await Future.delayed(const Duration(milliseconds: 500));
            }
            if (!clientConnected) break;
          }
        }

        final mediaUrl = _proxy(manifest.mediaSegmentUrls[i]);
        print('[DashLocalProxyServer] Fetching Media Segment $i...');
        
        int retries = 0;
        bool success = false;
        while (retries < 3 && !success) {
          try {
            final resp = await http.get(Uri.parse(mediaUrl));
            if (resp.statusCode == 200 || resp.statusCode == 206) {
              await sink?.add(resp.bodyBytes);
              await send(resp.bodyBytes);
              success = true;
            } else {
              print('[DashLocalProxyServer] Failed to fetch segment $i: ${resp.statusCode}, retrying...');
              retries++;
              await Future.delayed(const Duration(seconds: 1));
            }
          } catch (e) {
            print('[DashLocalProxyServer] Segment $i error: $e');
            retries++;
            await Future.delayed(const Duration(seconds: 1));
          }
        }
        
        if (!success) {
          print('[DashLocalProxyServer] Aborting stream after failed segment $i');
          break; // Stop stream if a segment fails completely
        }
        if (i == manifest.mediaSegmentUrls.length - 1) streamComplete = true;
      }
      if (manifest.mediaSegmentUrls.isEmpty) streamComplete = true;
    } catch (e) {
      print('[DashLocalProxyServer] Stream error: $e');
    } finally {
      if (sink != null) {
        if (streamComplete) {
          await sink.finish();
        } else {
          await sink.fail();
        }
      }
      print('[DashLocalProxyServer] Closing connection.');
      try {
        await response.close();
      } catch (_) {}
    }
  }

  static String _proxy(String url) {
    if (_proxyUrl != null && url.startsWith('http')) {
      return '$_proxyUrl${Uri.encodeComponent(url)}';
    }
    return url;
  }

  static void stop() {
    _server?.close(force: true);
    _server = null;
    _currentManifest = null;
    _getPosition = null;
    _sink = null;
  }
}
