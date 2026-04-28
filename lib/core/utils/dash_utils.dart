import 'dart:typed_data';

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

    // 1. Find Best Representation (Highest Bandwidth)
    final repMatches = RegExp(r'<Representation\s+([^>]+)>(.*?)<\/Representation>', dotAll: true, caseSensitive: false).allMatches(manifest);
    String bestRepContent = manifest; // Fallback to whole manifest
    int maxBW = -1;

    for (final match in repMatches) {
      final attrs = match.group(1)!;
      final bw = int.tryParse(getAttr(attrs, 'bandwidth') ?? '0') ?? 0;
      if (bw > maxBW) {
        maxBW = bw;
        bestRepContent = match.group(0)!;
      }
    }

    String? initUrl = getAttr(bestRepContent, 'initialization')?.replaceAll('&amp;', '&');
    String? mediaTemplate = getAttr(bestRepContent, 'media')?.replaceAll('&amp;', '&');
    
    if (initUrl == null || mediaTemplate == null) {
      final initMatch = RegExp('initialization\\s*=\\s*["\']?(https?://[^"\'\\s>]+)', caseSensitive: false).firstMatch(bestRepContent);
      final mediaMatch = RegExp('media\\s*=\\s*["\']?(https?://[^"\'\\s>]+)', caseSensitive: false).firstMatch(bestRepContent);
      initUrl ??= initMatch?.group(1)?.replaceAll('&amp;', '&');
      mediaTemplate ??= mediaMatch?.group(1)?.replaceAll('&amp;', '&');
    }

    print('[DashUtils] Chosen BW: $maxBW');
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

    // 3. Segments (Only from the CHOSEN representation)
    final List<int> segmentIndices = [0]; // Initialization segment (0.mp4)
    int segmentCounter = 1;
    
    // Extract the SegmentTimeline specifically from the best representation
    final timelineMatch = RegExp(r'<SegmentTimeline>(.*?)<\/SegmentTimeline>', dotAll: true, caseSensitive: false).firstMatch(bestRepContent);
    if (timelineMatch != null) {
      final timelineContent = timelineMatch.group(1)!;
      final sMatches = RegExp(r'<S\s+([^>]+)>', caseSensitive: false).allMatches(timelineContent);
      
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
    }

    print('[DashUtils] Total Segments for Chosen Representation: ${segmentIndices.length}');
    return DashManifest(
      initUrl: initUrl,
      mediaTemplate: mediaTemplate,
      segmentIndices: segmentIndices,
      bandwidth: maxBW,
      durationSeconds: durationSeconds,
    );
  }

  static String getSegmentUrl(DashManifest manifest, int index) {
    if (index == 0) return manifest.initUrl;
    return manifest.mediaTemplate.replaceAll(r'$Number$', index.toString());
  }

  /// Extracts the raw data from a specific MP4 box (e.g., 'mdat', 'dfLa')
  static Uint8List? extractBoxData(Uint8List bytes, String boxType) {
    int offset = 0;
    while (offset + 8 <= bytes.length) {
      final size = ByteData.view(bytes.buffer, bytes.offsetInBytes + offset, 4).getUint32(0);
      if (size < 8) break;
      
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      
      if (type == boxType) {
        return bytes.sublist(offset + 8, offset + size);
      }

      // Recursive search for containers
      if (['moov', 'trak', 'mdia', 'minf', 'stbl', 'stsd', 'fLaC'].contains(type)) {
        int innerStart = offset + 8;
        if (type == 'stsd') innerStart += 8; // Skip stsd version/flags
        if (type == 'fLaC') innerStart += 28; // Skip fLaC visual entry fields
        
        if (innerStart < offset + size) {
          final found = extractBoxData(bytes.sublist(innerStart, offset + size), boxType);
          if (found != null) return found;
        }
      }

      offset += size;
    }
    return null;
  }
}
