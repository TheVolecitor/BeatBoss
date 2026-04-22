class DashManifest {
  final String initUrl;
  final String mediaTemplate;
  final List<int> segmentIndices;
  final int bandwidth;
  final double durationSeconds;

  DashManifest({
    required this.initUrl,
    required this.mediaTemplate,
    required this.segmentIndices,
    this.bandwidth = 1000000,
    this.durationSeconds = 0,
  });

  int get totalSegments => segmentIndices.length;
}

class DashUtils {
  static DashManifest parseMpd(String manifest) {
    print('[DashUtils] Parsing manifest (len: ${manifest.length})');
    
    // Manual attribute extractor with multi-character boundary handling
    String? getAttr(String content, String name) {
      final key = '$name=';
      int idx = content.indexOf(key);
      if (idx == -1) {
        idx = content.indexOf('$name =');
        if (idx == -1) return null;
      }

      int valStart = content.indexOf('=', idx) + 1;
      // Skip whitespace and quotes
      while (valStart < content.length && (content[valStart] == ' ' || content[valStart] == '"' || content[valStart] == "'")) {
        valStart++;
      }
      
      int valEnd = valStart;
      while (valEnd < content.length && 
             content[valEnd] != '"' && 
             content[valEnd] != "'" && 
             content[valEnd] != ' ' && 
             content[valEnd] != '>') {
        valEnd++;
      }

      final val = content.substring(valStart, valEnd).trim();
      return val.isEmpty ? null : val;
    }

    // 1. Core Templates
    String? initUrl = getAttr(manifest, 'initialization')?.replaceAll('&amp;', '&');
    String? mediaTemplate = getAttr(manifest, 'media')?.replaceAll('&amp;', '&');
    
      if (initUrl == null || mediaTemplate == null) {
        final initMatch = RegExp('initialization\\s*=\\s*["\']?(https?://[^"\'\\s>]+)', caseSensitive: false).firstMatch(manifest);
        final mediaMatch = RegExp('media\\s*=\\s*["\']?(https?://[^"\'\\s>]+)', caseSensitive: false).firstMatch(manifest);
        initUrl ??= initMatch?.group(1)?.replaceAll('&amp;', '&');
        mediaTemplate ??= mediaMatch?.group(1)?.replaceAll('&amp;', '&');
     }

    print('[DashUtils] Found Init: ${initUrl ?? "MISSING"}');
    print('[DashUtils] Found Media: ${mediaTemplate ?? "MISSING"}');

    if (initUrl == null || mediaTemplate == null) throw Exception('Invalid DASH manifest: Missing templates');

    // 2. Metadata
    final bStr = getAttr(manifest, 'bandwidth');
    final dStr = getAttr(manifest, 'mediaPresentationDuration');
    print('[DashUtils] BW: $bStr, Duration: $dStr');

    int bandwidth = int.tryParse(bStr ?? '') ?? 1000000;
    double durationSeconds = 0;
    
    if (dStr != null) {
      final h = double.tryParse(RegExp(r'(\d+)H').firstMatch(dStr)?.group(1) ?? '0') ?? 0;
      final m = double.tryParse(RegExp(r'(\d+)M').firstMatch(dStr)?.group(1) ?? '0') ?? 0;
      final s = double.tryParse(RegExp(r'([\d.]+)S?').firstMatch(dStr.contains('M') ? dStr.split('M').last : dStr)?.group(1) ?? '0') ?? 0;
      durationSeconds = h * 3600 + m * 60 + s;
      print('[DashUtils] Parsed Duration: $durationSeconds s');
    }

    // 3. Segments
    final List<int> segmentIndices = [0];
    int segmentCounter = 1;
    final sMatches = RegExp(r'<[^>]*?S\s+([^>]+)>', caseSensitive: false).allMatches(manifest);
    
    for (final match in sMatches) {
        final attrs = match.group(1)!;
        final dVal = getAttr(attrs, 'd');
        final rVal = getAttr(attrs, 'r');
        if (dVal != null) {
            final r = int.tryParse(rVal ?? '0') ?? 0;
            for (int k = 0; k <= r; k++) {
              segmentIndices.add(segmentCounter++);
            }
        }
    }

    print('[DashUtils] Total Segments: ${segmentIndices.length}');
    return DashManifest(
      initUrl: initUrl,
      mediaTemplate: mediaTemplate,
      segmentIndices: segmentIndices,
      bandwidth: bandwidth,
      durationSeconds: durationSeconds,
    );
  }

  static String getSegmentUrl(DashManifest manifest, int index) {
    if (index == 0) return manifest.initUrl;
    return manifest.mediaTemplate.replaceAll(r'$Number$', index.toString());
  }
}
