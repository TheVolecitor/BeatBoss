import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class DashManifest {
  final String initSegmentUrl;
  final List<String> mediaSegmentUrls;
  final double duration;
  final double segmentDuration;

  DashManifest({
    required this.initSegmentUrl,
    required this.mediaSegmentUrls,
    required this.duration,
    required this.segmentDuration,
  });
}

class DashNativeParser {
  static Future<DashManifest> parse(String manifestUrl) async {
    print('[DashNativeParser] Fetching manifest: $manifestUrl');
    final response = await http.get(Uri.parse(manifestUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to load MPD: ${response.statusCode}');
    }

    final xmlString = response.body;
    final document = XmlDocument.parse(xmlString);
    
    // Find base URL
    String baseUrl = '';
    final baseUrlElements = document.findAllElements('BaseURL');
    if (baseUrlElements.isNotEmpty) {
      baseUrl = baseUrlElements.first.innerText.trim();
    } else {
      final uri = Uri.parse(manifestUrl);
      baseUrl = '${uri.scheme}://${uri.host}${uri.path.substring(0, uri.path.lastIndexOf('/') + 1)}';
    }

    // Find SegmentTemplate
    final representation = document.findAllElements('Representation').first;
    final representationId = representation.getAttribute('id') ?? '';
    
    final segmentTemplate = document.findAllElements('SegmentTemplate').first;
    
    String initialization = segmentTemplate.getAttribute('initialization') ?? '';
    initialization = initialization.replaceAll(r'$RepresentationID$', representationId);
    final initSegmentUrl = _buildUrl(baseUrl, initialization);

    String media = segmentTemplate.getAttribute('media') ?? '';
    media = media.replaceAll(r'$RepresentationID$', representationId);
    
    final startNumberStr = segmentTemplate.getAttribute('startNumber');
    int startNumber = startNumberStr != null ? int.parse(startNumberStr) : 1;

    final timescaleStr = segmentTemplate.getAttribute('timescale') ?? '1';
    final timescale = int.parse(timescaleStr);
    double segmentDurationSeconds = 0.0;
    int totalSegments = 0;

    final segmentTimeline = segmentTemplate.findElements('SegmentTimeline').firstOrNull;

    if (segmentTimeline != null) {
      final sElements = segmentTimeline.findElements('S');
      for (final s in sElements) {
        final dStr = s.getAttribute('d');
        if (dStr != null) {
          segmentDurationSeconds = int.parse(dStr) / timescale;
        }
        final rStr = s.getAttribute('r');
        int r = rStr != null ? int.parse(rStr) : 0;
        totalSegments += (1 + r);
      }
    } else {
      // Fallback if SegmentTimeline is missing but duration and timescale are present
      final durationStr = segmentTemplate.getAttribute('duration');
      if (durationStr != null) {
        final duration = int.parse(durationStr);
        segmentDurationSeconds = duration / timescale;
        
        final mpdElement = document.findElements('MPD').firstOrNull;
        if (mpdElement != null) {
          final mediaPresentationDuration = mpdElement.getAttribute('mediaPresentationDuration');
          if (mediaPresentationDuration != null) {
            final totalDurationSeconds = _parseDuration(mediaPresentationDuration);
            totalSegments = (totalDurationSeconds / segmentDurationSeconds).ceil();
          }
        }
      }
      
      if (totalSegments == 0) {
        throw Exception('Could not determine total segments from manifest.');
      }
    }

    List<String> mediaSegmentUrls = [];
    for (int i = 0; i < totalSegments; i++) {
      int currentNumber = startNumber + i;
      String currentMedia = media.replaceAll(r'$Number$', currentNumber.toString());
      mediaSegmentUrls.add(_buildUrl(baseUrl, currentMedia));
    }

    double duration = 0.0;
    final mpdElement = document.findElements('MPD').firstOrNull;
    if (mpdElement != null) {
      final mediaPresentationDuration = mpdElement.getAttribute('mediaPresentationDuration');
      if (mediaPresentationDuration != null) {
        duration = _parseDuration(mediaPresentationDuration);
      }
    }

    print('[DashNativeParser] Parsed successfully. Init: $initSegmentUrl, Segments: ${mediaSegmentUrls.length}, Duration: $duration');

    return DashManifest(
      initSegmentUrl: initSegmentUrl,
      mediaSegmentUrls: mediaSegmentUrls,
      duration: duration,
      segmentDuration: segmentDurationSeconds,
    );
  }

  static String _buildUrl(String baseUrl, String path) {
    if (path.startsWith('http')) return path;
    if (baseUrl.endsWith('/') && path.startsWith('/')) {
      return baseUrl + path.substring(1);
    } else if (baseUrl.endsWith('/') || path.startsWith('/')) {
      return '$baseUrl$path';
    } else {
      return '$baseUrl/$path';
    }
  }

  static double _parseDuration(String durationString) {
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?');
    final match = regex.firstMatch(durationString);
    if (match != null) {
      final hours = match.group(1) != null ? double.parse(match.group(1)!) : 0;
      final minutes = match.group(2) != null ? double.parse(match.group(2)!) : 0;
      final seconds = match.group(3) != null ? double.parse(match.group(3)!) : 0;
      return ((hours * 3600) + (minutes * 60) + seconds).toDouble();
    }
    return 0.0;
  }
}
