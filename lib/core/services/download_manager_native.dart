// Native-only download helpers. Contains all dart:io, audiotags, permission_handler
// and DASH code. This file is ONLY compiled when dart.library.html is NOT present (native).
// dart2js will NEVER compile this file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audiotags/audiotags.dart';

import '../models/models.dart';
import '../utils/flac_utils.dart';
import '../utils/dash_utils.dart';
import '../utils/web_metadata_writer.dart';
import 'settings_service.dart';
import 'dash_native_parser.dart' as dnp;

/// Request storage permissions on Android/iOS.
Future<void> requestNativePermissions({
  required bool isAndroid,
  required bool isIOS,
}) async {
  if (isAndroid) {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    if (!status.isGranted) {
      await Permission.audio.request();
      await Permission.manageExternalStorage.request();
    }
  } else if (isIOS) {
    await Permission.storage.request();
  }
}

/// Write ID3/FLAC metadata tags to a downloaded file.
Future<void> writeNativeMetadata(String filePath, Track track, Dio dio) async {
  final file = File(filePath);
  if (!await file.exists()) return;

  final dir = file.parent;
  final extension = file.path.split('.').last;
  final safeTempName = 'temp_${DateTime.now().millisecondsSinceEpoch}.$extension';
  final safeTempPath = '${dir.path}${Platform.pathSeparator}$safeTempName';
  final safeFile = File(safeTempPath);

  try {
    if (await safeFile.exists()) await safeFile.delete();
    await file.rename(safeTempPath);

    try {
      final tag = Tag(
        title: track.title,
        trackArtist: track.artist,
        album: track.albumTitle,
        year: null,
        genre: null,
        trackNumber: null,
        trackTotal: null,
        discNumber: null,
        discTotal: null,
        pictures: [],
      );

      if (extension == 'm4a' || extension == 'mp4') {
        print('[Metadata] Using WebMetadataWriter (Pure Dart MP4) for native M4A/MP4 tags...');
        final bytes = await safeFile.readAsBytes();
        final newBytes = await WebMetadataWriter.injectMetadata(bytes, track, dio);
        await safeFile.writeAsBytes(newBytes);
        print('[Metadata] Tags written successfully via WebMetadataWriter');
      } else if (extension == 'flac') {
        // NEVER use AudioTags/TagLib on FLAC — it rewrites the file and
        // truncates the audio payload. Use pure-Dart Vorbis Comment injection.
        print('[Metadata] Using FlacUtils (Pure Dart) for FLAC tags...');
        Uint8List? coverBytes;
        String coverMime = 'image/jpeg';
        if (track.albumCover != null && track.albumCover!.isNotEmpty) {
          try {
            final response = await dio.get(
              track.albumCover!,
              options: Options(responseType: ResponseType.bytes),
            );
            if (response.statusCode == 200) {
              coverBytes = Uint8List.fromList(response.data as List<int>);
              coverMime = response.headers.value('content-type') ?? 'image/jpeg';
            }
          } catch (e) {
            print('[Metadata] Error fetching cover art for FLAC: $e');
          }
        }
        await FlacUtils.injectMetadataAndFix(
          safeFile,
          title: track.title,
          artist: track.artist,
          album: track.albumTitle,
          coverBytes: coverBytes,
          coverMimeType: coverMime,
        );
        print('[Metadata] FLAC tags written successfully via FlacUtils');
      } else {
        if (track.albumCover != null && track.albumCover!.isNotEmpty) {
          try {
            final response = await dio.get(
              track.albumCover!,
              options: Options(responseType: ResponseType.bytes),
            );
            if (response.statusCode == 200) {
              final coverBytes = Uint8List.fromList(response.data as List<int>);
              final mimeType = response.headers.value('content-type') ?? 'image/jpeg';
              tag.pictures.add(Picture(
                bytes: coverBytes,
                mimeType: mimeType == 'image/png' ? MimeType.png : MimeType.jpeg,
                pictureType: PictureType.coverFront,
              ));
            }
          } catch (e) {
            print('[Metadata] Error fetching cover art: $e');
          }
        }
        
        await AudioTags.write(safeTempPath, tag);
        print('[Metadata] Tags written successfully via AudioTags');
      }
    } catch (e) {
      print('[Metadata] AudioTags write failed: $e');
    }
  } catch (e) {
    print('[Metadata] Rename error: $e');
  } finally {
    if (await safeFile.exists()) {
      try {
        if (await file.exists()) await file.delete();
        await safeFile.rename(filePath);
      } catch (e) {
        print('[Metadata] CRITICAL: Failed to restore filename: $e');
      }
    }
  }
}



/// Download a DASH manifest (segmented audio).
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
    
    if (isDataUri) {
      final manifestBase64 = manifestDataUri.split(',').last;
      final manifestContent = utf8.decode(base64Decode(manifestBase64));
      final manifest = DashUtils.parseMpd(manifestContent);
      initUrl = manifest.initUrl;
      for (int index in manifest.segmentIndices) {
        segmentUrls.add(DashUtils.getSegmentUrl(manifest, index));
      }
    } else {
      // It's a standard HTTP URL, use DashNativeParser
      final manifest = await dnp.DashNativeParser.parse(manifestDataUri);
      initUrl = manifest.initSegmentUrl;
      segmentUrls = manifest.mediaSegmentUrls;
    }

    final totalSegments = segmentUrls.length;
    final List<Uint8List?> segmentBuffers = List.filled(segmentUrls.length, null);
    Uint8List? initBuffer;
    int completed = 0;

    // 1. Fetch Init Segment if present
    if (initUrl != null && initUrl.isNotEmpty) {
      final response = await dio.get<List<int>>(initUrl, options: Options(responseType: ResponseType.bytes));
      if (response.statusCode == 200 || response.statusCode == 206) {
        initBuffer = Uint8List.fromList(response.data!);
      }
    }

    // 2. Fetch Media Segments
    const int batchSize = 10;
    for (int i = 0; i < segmentUrls.length; i += batchSize) {
      final end = (i + batchSize < segmentUrls.length) ? i + batchSize : segmentUrls.length;
      final batch = segmentUrls.sublist(i, end);
      
      final results = await Future.wait(batch.asMap().entries.map((entry) async {
        final batchIndex = entry.key;
        final url = entry.value;
        final response = await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
        return MapEntry(batchIndex + i, response.data!); // Keep original index
      }));

      for (final entry in results) {
        segmentBuffers[entry.key] = Uint8List.fromList(entry.value);
      }
      completed += batch.length;
      final progress = (completed / totalSegments) * 100;
      activeDownloads[trackId] = progress;
      onProgress?.call(progress);
      notifyCallback();
    }

    // 3. Remux fragmented MP4 to raw FLAC
    print('[Download] Remuxing fragmented MP4 to raw FLAC stream...');
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
      flacBuilder.add(mutableMeta);
    }
    flacBuilder.add(rawAudio);
    
    final finalBytes = flacBuilder.takeBytes();

    // 4. Save to file
    final finalPath = '$downloadDir${Platform.pathSeparator}$safeName.flac';
    final file = File(finalPath);
    await file.writeAsBytes(finalBytes);



    // 5. Write Metadata
    await writeNativeMetadata(finalPath, track, dio);
    await settingsService.registerDownload(trackId, finalPath, track: track);

    activeDownloads.remove(trackId);
    notifyCallback();
    onComplete?.call(true, null);
    return true;
  } catch (e) {
    print('[Download] DASH Error: $e');
    activeDownloads.remove(trackId);
    notifyCallback();
    onComplete?.call(false, e.toString());
    return false;
  }
}

/// Rename a file from [from] to [to].
Future<void> renameFile(String from, String to) async {
  final file = File(from);
  await file.rename(to);
}

/// Trigger web download — no-op on native.
Future<bool> triggerWebDownload(String url, String filename, {Track? track}) async => false;
