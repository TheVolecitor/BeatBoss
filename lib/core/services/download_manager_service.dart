import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';

import 'settings_service.dart';
import '../models/models.dart';

import 'package:audiotags/audiotags.dart';
import '../utils/flac_utils.dart';
import '../utils/dash_utils.dart';

class DownloadManagerService extends ChangeNotifier {
  final SettingsService _settingsService;
  final Dio _dio = Dio();

  // Active downloads: trackId -> progress (0-100)
  final Map<String, double> _activeDownloads = {};

  Map<String, double> get activeDownloads => Map.unmodifiable(_activeDownloads);
  bool get hasActiveDownloads => _activeDownloads.isNotEmpty;

  DownloadManagerService({required SettingsService settingsService})
      : _settingsService = settingsService;

  /// Sanitize filename for safe filesystem storage
  String _sanitizeFilename(String filename) {
    return filename
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Check if track is downloaded
  bool isDownloaded(String trackId) {
    return _settingsService.isDownloaded(trackId);
  }

  /// Check if track is currently downloading
  bool isDownloading(String trackId) {
    return _activeDownloads.containsKey(trackId);
  }

  /// Get download progress (0-100)
  double? getProgress(String trackId) {
    return _activeDownloads[trackId];
  }

  /// Get local file path for track
  String? getLocalPath(String trackId) {
    return _settingsService.getLocalPath(trackId);
  }

  /// Cleanup temporary playback files on startup
  Future<void> cleanupTemporaryFiles() async {
    try {
      final downloadPath = await _settingsService.getDownloadLocation();
      final dir = Directory(downloadPath);
      if (!await dir.exists()) return;

      final tempFiles = dir.listSync().where((f) =>
          f is File &&
          f.path.contains('playback_safe_') &&
          f.path.endsWith('.flac'));

      int count = 0;
      for (final file in tempFiles) {
        try {
          file.deleteSync();
          count++;
        } catch (e) {
          // Ignore
        }
      }
      if (count > 0)
        print('[DownloadManager] Cleaned up $count temporary playback files.');
    } catch (e) {
      print('[DownloadManager] Cleanup error: $e');
    }
  }

  /// Download a track
  Future<bool> downloadTrack({
    required Track track,
    required String streamUrl,
    void Function(double progress)? onProgress,
    void Function(bool success, String? error)? onComplete,
  }) async {
    final trackId = track.id;
    final title = track.title;
    final artist = track.artist;
    if (_activeDownloads.containsKey(trackId)) {
      print('[Download] Track $trackId already downloading');
      return false;
    }

    // Request permissions on mobile
    if (Platform.isAndroid || Platform.isIOS) {
      if (Platform.isAndroid) {
        // Android 13+ needs granular permissions, older needs storage
        // Simple check: try requesting storage first
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }

        // If storage denied, it might be Android 13+ requiring audio/manage
        if (!status.isGranted) {
          await Permission.audio.request();
          await Permission.manageExternalStorage.request();
        }
      } else {
        await Permission.storage.request();
      }
    }

    _activeDownloads[trackId] = 0;
    notifyListeners();

    try {
      final downloadDir = await _settingsService.getDownloadLocation();

      // Create directory if it doesn't exist
      final dir = Directory(downloadDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final safeName = _sanitizeFilename('$artist - $title');
      
      // Check if it's a DASH manifest
      if (streamUrl.startsWith('data:application/dash+xml')) {
          print('[Download] DASH manifest detected. Using segmented downloader.');
          return await _downloadDashTrack(
            track: track,
            manifestDataUri: streamUrl,
            downloadDir: downloadDir,
            safeName: safeName,
            onProgress: onProgress,
            onComplete: onComplete,
          );
      }

      final tempPath = '$downloadDir${Platform.pathSeparator}$safeName.tmp';

      print('[Download] Starting: $tempPath');

      final response = await _dio.download(
        streamUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total) * 100;
            _activeDownloads[trackId] = progress;
            onProgress?.call(progress);
            notifyListeners();
          }
        },
      );

      // 2. Detect Format & Rename
      final file = File(tempPath);
      if (!await file.exists()) {
        throw Exception('Download failed - file not found');
      }

      // Determine extension from Content-Type
      final contentType = response.headers.value('content-type');
      String extension = _detectExtension(contentType);

      print(
          '[Download] Detected format: $extension (ContentType: $contentType)');

      final finalPath =
          '$downloadDir${Platform.pathSeparator}$safeName$extension';

      // Rename .tmp -> .extension
      await file.rename(finalPath);

      // 3. Write Metadata (Try-Catch Wrapper)
      print('[Download] Writing metadata to $finalPath...');

      // Wait for file handle release
      await Future.delayed(const Duration(milliseconds: 500));

      // Skip M4A tagging if user explicitly requested avoidance (or just catch error)
      // "avoid m4a as it doesnt have any metadata support"
      if (extension == '.m4a') {
        print('[Metadata] Skipping tagging for M4A as requested/unsupported.');
      } else {
        await _writeMetadata(finalPath, track);
      }

      // Register download in settings (with metadata)
      await _settingsService.registerDownload(trackId, finalPath, track: track);

      _activeDownloads.remove(trackId);
      notifyListeners();

      print('[Download] Complete: $finalPath');
      onComplete?.call(true, null);
      return true;
    } catch (e) {
      print('[Download] Error: $e');
      _activeDownloads.remove(trackId);
      notifyListeners();
      onComplete?.call(false, e.toString());
      return false;
    }
  }

  /// Helper to detect extension from Content-Type
  String _detectExtension(String? contentType) {
    if (contentType == null) return '.m4a'; // Default

    if (contentType.contains('audio/flac') ||
        contentType.contains('application/x-flac')) {
      return '.flac';
    }
    if (contentType.contains('audio/mp4') ||
        contentType.contains('audio/x-m4a')) {
      return '.m4a';
    }
    if (contentType.contains('audio/mpeg')) {
      return '.mp3';
    }
    if (contentType.contains('audio/ogg') ||
        contentType.contains('application/ogg') ||
        contentType.contains('video/ogg')) {
      return '.ogg';
    }
    if (contentType.contains('audio/opus') ||
        contentType.contains('audio/webm')) {
      // Common for YouTube streams
      return '.opus';
    }

    return '.m4a'; // Default fallback
  }

  Future<void> _writeMetadata(String filePath, Track track) async {
    // TEMP FILE STRATEGY
    // Solution: Rename file to a safe, simple name in the same directory, write tags, then rename back.

    final file = File(filePath);
    if (!await file.exists()) return;

    final dir = file.parent;
    final extension = file.path.split('.').last;
    final safeTempName =
        'temp_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final safeTempPath = '${dir.path}${Platform.pathSeparator}$safeTempName';
    final safeFile = File(safeTempPath);

    try {
      // 1. Rename to Safe Path
      if (await safeFile.exists()) {
        await safeFile.delete();
      }
      print('[Metadata] Renaming to safe path: $safeTempName');
      await file.rename(safeTempPath);

      // 2. Fetch Cover Art
      // Note: AudioTags expects a Picture object or equivalent. Checking API...
      // Actually with audiotags 1.4.x via FFI/Lofty, we usually write tags using Tag class.

      /* 
         AudioTags.write(path: String, tag: Tag) 
         Picture needs: pictureType, mimeType, bytes
      */

      // 3. Write Metadata using AudioTags
      try {
        final tag = Tag(
          title: track.title,
          trackArtist: track.artist, // Changed from artist to trackArtist
          album: track.albumTitle,
          year: null,
          genre: null,
          trackNumber: null,
          trackTotal: null,
          discNumber: null,
          discTotal: null,
          pictures: [],
        );

        if (track.albumCover != null && track.albumCover!.isNotEmpty) {
          try {
            final response = await _dio.get(
              track.albumCover!,
              options: Options(responseType: ResponseType.bytes),
            );
            if (response.statusCode == 200) {
              final coverBytes = Uint8List.fromList(response.data as List<int>);
              final mimeType =
                  response.headers.value('content-type') ?? 'image/jpeg';

              // Add picture to tag (no resizing)
              tag.pictures.add(Picture(
                bytes: coverBytes,
                mimeType:
                    mimeType == 'image/png' ? MimeType.png : MimeType.jpeg,
                pictureType: PictureType.coverFront,
              ));
            }
          } catch (e) {
            print('[Metadata] Error fetching cover art: $e');
          }
        }

        // AudioTags.write takes positional arguments: (path, tag)
        await AudioTags.write(safeTempPath, tag);
        print('[Metadata] Tags written successfully via AudioTags');

        // 4. Structural Cleanup (Fix flags/gaps/seektable)
        // User requested robust fix for "Incorrect LAST-METADATA-BLOCK" and gaps.
        // We do this AFTER adding tags (which might have messed up flags or added padding).
        await FlacUtils.cleanupFlacStructure(safeFile);
      } catch (e) {
        print('[Metadata] AudioTags write failed: $e');
      }
    } catch (e) {
      print('[Metadata] Error in renaming/handling: $e');
    } finally {
      // 4. Rename Back (Always restore)
      if (await safeFile.exists()) {
        try {
          print('[Metadata] Restoring filename...');
          if (await file.exists()) {
            await file.delete();
          }
          await safeFile.rename(filePath);
        } catch (e) {
          print('[Metadata] CRITICAL: Failed to restore filename: $e');
        }
      }
    }
  }

  Future<bool> _downloadDashTrack({
    required Track track,
    required String manifestDataUri,
    required String downloadDir,
    required String safeName,
    void Function(double progress)? onProgress,
    void Function(bool success, String? error)? onComplete,
  }) async {
    final trackId = track.id;
    try {
      final manifestBase64 = manifestDataUri.split(',').last;
      final manifestContent = utf8.decode(base64Decode(manifestBase64));

      // 1. Parse MPD via Utility
      final DashManifest manifest = DashUtils.parseMpd(manifestContent);
      final totalSegments = manifest.totalSegments;
      print('[Download] DASH: Downloading $totalSegments segments...');

      final finalPath = '$downloadDir${Platform.pathSeparator}$safeName.flac';
      final file = File(finalPath);
      final sink = file.openWrite();

      int completed = 0;
      
      // Process in small batches to avoid memory pressure or overloading
      const int batchSize = 10;
      for (int i = 0; i < manifest.segmentIndices.length; i += batchSize) {
        final end = (i + batchSize < manifest.segmentIndices.length) ? i + batchSize : manifest.segmentIndices.length;
        final batch = manifest.segmentIndices.sublist(i, end);

        await Future.wait(batch.map((index) async {
          final url = DashUtils.getSegmentUrl(manifest, index);
          
          final response = await _dio.get(url, options: Options(responseType: ResponseType.bytes));
          if (response.statusCode == 200) {
              // We need to write in order, so we can't write directly to sink in parallel
              // But we can download in parallel. This batching keeps it simple.
          }
          return MapEntry(index, response.data);
        })).then((results) {
            // Sort by index to maintain order
            results.sort((a, b) => a.key.compareTo(b.key));
            for (final entry in results) {
                sink.add(entry.value);
            }
            completed += batch.length;
            final progress = (completed / totalSegments) * 100;
            _activeDownloads[trackId] = progress;
            onProgress?.call(progress);
            notifyListeners();
        });
      }

      await sink.flush();
      await sink.close();

      // Write Metadata
      await _writeMetadata(finalPath, track);
      await _settingsService.registerDownload(trackId, finalPath, track: track);

      _activeDownloads.remove(trackId);
      notifyListeners();
      onComplete?.call(true, null);
      return true;
    } catch (e) {
      print('[Download] DASH Error: $e');
      _activeDownloads.remove(trackId);
      notifyListeners();
      onComplete?.call(false, e.toString());
      return false;
    }
  }

  /// Delete a downloaded track
  Future<bool> deleteDownload(String trackId) async {
    final path = _settingsService.getLocalPath(trackId);
    if (path == null) return false;

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      await _settingsService.unregisterDownload(trackId);
      notifyListeners();
      return true;
    } catch (e) {
      print('[Download] Delete error: $e');
      return false;
    }
  }

  /// Cancel an active download
  void cancelDownload(String trackId) {
    _activeDownloads.remove(trackId);
    notifyListeners();
  }
}
