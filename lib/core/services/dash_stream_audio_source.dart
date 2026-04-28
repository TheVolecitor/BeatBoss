import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'dash_native_parser.dart';

class DashStreamAudioSource extends StreamAudioSource {
  final DashManifest manifest;
  final String? proxyUrl;

  DashStreamAudioSource(this.manifest, {this.proxyUrl});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    
    // We only support streaming from the beginning for now, 
    // as jumping in a fragmented MP4 stream requires parsing boxes.
    return StreamAudioResponse(
      sourceLength: null, // Unknown total length in bytes
      contentLength: null,
      offset: start,
      stream: _yieldSegments(),
      contentType: 'audio/mp4',
    );
  }

  Stream<List<int>> _yieldSegments() async* {
    // 1. Fetch and yield the Init Segment
    final initUrl = _proxy(manifest.initSegmentUrl);
    print('[DashStream] Fetching Init Segment: $initUrl');
    
    try {
      final initResp = await http.get(Uri.parse(initUrl));
      if (initResp.statusCode == 200) {
        yield initResp.bodyBytes;
      } else {
        throw Exception('Init Segment failed: ${initResp.statusCode}');
      }
    } catch (e) {
      print('[DashStream] Init fetch error: $e');
      return; // Abort if init fails
    }

    // 2. Fetch and yield Media Segments sequentially
    for (int i = 0; i < manifest.mediaSegmentUrls.length; i++) {
      final mediaUrl = _proxy(manifest.mediaSegmentUrls[i]);
      print('[DashStream] Fetching Media Segment $i...');
      
      int retries = 0;
      bool success = false;
      while (retries < 3 && !success) {
        try {
          final resp = await http.get(Uri.parse(mediaUrl));
          if (resp.statusCode == 200) {
            yield resp.bodyBytes;
            success = true;
          } else {
            print('[DashStream] Failed to fetch segment $i: ${resp.statusCode}, retrying...');
            retries++;
            await Future.delayed(const Duration(seconds: 1));
          }
        } catch (e) {
          print('[DashStream] Segment $i error: $e');
          retries++;
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      
      if (!success) {
        print('[DashStream] Aborting stream after failed segment $i');
        break; // Stop stream if a segment fails completely
      }
    }
    print('[DashStream] Finished yielding all segments.');
  }

  String _proxy(String url) {
    if (proxyUrl != null && url.startsWith('http')) {
      return '$proxyUrl${Uri.encodeComponent(url)}';
    }
    return url;
  }
}
