// Web-only download helpers.
// On web, we must use a proxy and Blob URLs since browsers ignore 'download' on cross-origin URLs.
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/dio.dart';

import '../models/models.dart';
import 'settings_service.dart';
import '../utils/dash_utils.dart';
import '../utils/web_metadata_writer.dart';
import 'dash_native_parser.dart' as dnp;

const String _proxyBase =
    'https://webdownloadproxy.thevolecitor.workers.dev/?url=';

/// Triggers a browser file download by fetching through a CORS proxy.
Future<bool> triggerWebDownload(String url, String filename,
    {Track? track}) async {
  try {
    final proxyUrl = '$_proxyBase${Uri.encodeComponent(url)}';

    final dio = Dio();
    final response = await dio.get<List<int>>(
      proxyUrl,
      options: Options(responseType: ResponseType.bytes),
    );

    if (response.data == null) return false;
    Uint8List bytes = Uint8List.fromList(response.data!);

    // Inject metadata if track info is provided
    if (track != null) {
      bytes = await WebMetadataWriter.injectMetadata(bytes, track, dio);
    }

    return await triggerWebDownloadBlob(bytes, filename);
  } catch (e) {
    print('[WebDownload] Error: $e');
    return false;
  }
}

/// DASH download for Web: fetches segments via proxy and combines into one file.
Future<bool> downloadDashTrack({
  required Track track,
  required String manifestDataUri,
  required String downloadDir,
  required String safeName,
  required SettingsService settingsService,
  required Dio dio,
  required Map<String, double> activeDownloads,
  required void Function() notifyCallback,
  void Function(double progress)? onProgress,
  void Function(bool success, String? error)? onComplete,
}) async {
  final trackId = track.id;
  try {
    final bool isDataUri = manifestDataUri.startsWith('data:');
    
    List<String> segmentUrls = [];
    String? initUrl;
    String extension = '.flac'; // Default for legacy FLAC manifests
    
    if (isDataUri) {
      final manifestBase64 = manifestDataUri.split(',').last;
      final manifestContent = utf8.decode(base64Decode(manifestBase64));
      final manifest = DashUtils.parseMpd(manifestContent);
      initUrl = manifest.initUrl;
      for (int index in manifest.segmentIndices) {
        segmentUrls.add(DashUtils.getSegmentUrl(manifest, index));
      }
    } else {
      final manifest = await dnp.DashNativeParser.parse(manifestDataUri);
      initUrl = manifest.initSegmentUrl;
      segmentUrls = manifest.mediaSegmentUrls;
      extension = '.m4a'; // standard DASH streams are fMP4
    }

    final totalSegments = segmentUrls.length;

    final List<Uint8List?> segmentBuffers = List.filled(segmentUrls.length, null);
    Uint8List? initBuffer;
    int completed = 0;

    // Fetch Init Segment
    if (initUrl != null && initUrl.isNotEmpty) {
      try {
        final resp = await dio.get<List<int>>(initUrl, options: Options(responseType: ResponseType.bytes));
        if (resp.data != null) initBuffer = Uint8List.fromList(resp.data!);
      } catch (e) {
        print('[WebDash] Error fetching init segment: $e');
      }
    }

    // Fetch media segments in parallel chunks
    const int chunkSize = 10;
    for (int i = 0; i < segmentUrls.length; i += chunkSize) {
      final end = (i + chunkSize < segmentUrls.length) ? i + chunkSize : segmentUrls.length;
      final futures = <Future<void>>[];

      for (int j = i; j < end; j++) {
        final index = j;
        futures.add(() async {
          try {
            final url = segmentUrls[index];
            Response<List<int>>? response;
            try {
              response = await dio.get<List<int>>(
                url,
                options: Options(responseType: ResponseType.bytes, sendTimeout: const Duration(seconds: 5)),
              );
            } catch (e) {
              final proxyUrl = '$_proxyBase${Uri.encodeComponent(url)}';
              response = await dio.get<List<int>>(
                proxyUrl,
                options: Options(responseType: ResponseType.bytes),
              );
            }

            if (response.data != null) {
              segmentBuffers[index] = Uint8List.fromList(response.data!);
            }
          } catch (e) {
            print('[WebDash] Error fetching segment $index: $e');
          } finally {
            completed++;
            final progress = (completed / totalSegments) * 100;
            activeDownloads[trackId] = progress;
            onProgress?.call(progress);
            notifyCallback();
          }
        }());
      }
      await Future.wait(futures);
    }

    Uint8List finalBytes;

    if (extension == '.flac') {
      // Legacy HiFi-API: Remuxing fragmented MP4 to raw FLAC stream
      print('[WebDash] Remuxing fragmented MP4 to raw FLAC stream...');
      final audioBuilder = BytesBuilder(copy: false);
      for (int i = 0; i < segmentBuffers.length; i++) {
        final buf = segmentBuffers[i];
        if (buf == null) continue;
        final mdata = DashUtils.extractBoxData(buf, 'mdat');
        if (mdata != null) {
          audioBuilder.add(mdata);
        }
      }
      final rawAudio = audioBuilder.takeBytes();

      final flacBuilder = BytesBuilder(copy: false);
      flacBuilder.add(Uint8List.fromList([0x66, 0x4C, 0x61, 0x43])); // fLaC Magic
      Uint8List? flacMetadata;
      if (initBuffer != null) {
        final raw = DashUtils.extractBoxData(initBuffer, 'dfLa');
        if (raw != null && raw.length > 4) {
          flacMetadata = raw.sublist(4);
        }
      }

      if (flacMetadata != null) {
        final mutableMeta = Uint8List.fromList(flacMetadata);
        _clearLastBlockFlag(mutableMeta);
        flacBuilder.add(mutableMeta);
      }
      flacBuilder.add(rawAudio);
      finalBytes = flacBuilder.takeBytes();

      // Inject metadata for FLAC
      try {
        finalBytes = await WebMetadataWriter.injectMetadata(finalBytes, track, dio);
      } catch (e) {
        print('[WebDash] Metadata injection failed: $e');
      }
    } else {
      // Standard HTTP DASH (.m4a): Direct fMP4 concatenation
      print('[WebDash] Concatenating fMP4 segments for .m4a download...');
      final audioBuilder = BytesBuilder(copy: false);
      if (initBuffer != null) audioBuilder.add(initBuffer);
      for (int i = 0; i < segmentBuffers.length; i++) {
        final buf = segmentBuffers[i];
        if (buf != null) audioBuilder.add(buf);
      }
      finalBytes = audioBuilder.takeBytes();
      print('[Metadata] Skipping ID3 tags for Web M4A download as requested/unsupported.');
    }

    final success = await triggerWebDownloadBlob(finalBytes, '$safeName$extension');

    activeDownloads.remove(trackId);
    notifyCallback();
    onComplete?.call(success, success ? null : 'Download failed');
    return success;
  } catch (e) {
    print('[WebDash] Error: $e');
    activeDownloads.remove(trackId);
    notifyCallback();
    onComplete?.call(false, e.toString());
    return false;
  }
}

/// Walk the raw FLAC metadata block bytes and clear the isLast bit on the
/// final block, so additional blocks can be appended by WebMetadataWriter.
void _clearLastBlockFlag(Uint8List meta) {
  int offset = 0;
  int lastBlockOffset = -1;
  while (offset + 4 <= meta.length) {
    final headerByte = meta[offset];
    final isLast = (headerByte & 0x80) != 0;
    final length =
        (meta[offset + 1] << 16) | (meta[offset + 2] << 8) | meta[offset + 3];
    lastBlockOffset = offset;
    if (isLast) break;
    offset += 4 + length;
  }
  if (lastBlockOffset >= 0) {
    // Clear bit 7 (isLast flag) on the last block's header byte
    meta[lastBlockOffset] = meta[lastBlockOffset] & 0x7F;
    print(
        '[WebDash] Cleared isLast flag on metadata block at offset $lastBlockOffset');
  }
}

/// Helper for Blobs on Web
Future<bool> triggerWebDownloadBlob(Uint8List bytes, String filename) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    anchor.click();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (e) {
    print('[WebBlob] Error: $e');
    return false;
  }
}

Future<void> requestNativePermissions(
    {required bool isAndroid, required bool isIOS}) async {}
Future<void> writeNativeMetadata(String filePath, Track track, Dio dio) async {}
Future<void> renameFile(String from, String to) async {}
