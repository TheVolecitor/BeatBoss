import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'dart:async';

import 'settings_service.dart';
import '../models/models.dart';
import '../utils/platform_helper.dart'; // compile-time conditional

// Native-only imports (not compiled on web)
import 'download_manager_native.dart'
    if (dart.library.js_interop) 'download_manager_web.dart' as _dm;

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
    if (kIsWeb) return;
    try {
      final downloadPath = await _settingsService.getDownloadLocation();
      await PlatformHelper.cleanupTempFiles(downloadPath);
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

    final safeName = _sanitizeFilename('$artist - $title');

    // 1. DASH DETECTION (High Priority)
    final bool isDash = streamUrl.startsWith('data:application/dash+xml') || 
                        streamUrl.contains('.mpd') || 
                        (track.addonId?.contains('dash') ?? false); // Hint from provider logic if applicable

    if (isDash) {
        print('[Download] DASH manifest detected. Using segmented downloader.');
        final downloadDir = kIsWeb ? '' : await _settingsService.getDownloadLocation();
        return await _downloadDashTrack(
          track: track,
          manifestDataUri: streamUrl,
          downloadDir: downloadDir,
          safeName: safeName,
          onProgress: onProgress,
          onComplete: onComplete,
        );
    }

    // ── WEB: standard direct download ──────────────────────────────────────
    if (kIsWeb) {
      _activeDownloads[trackId] = 0;
      notifyListeners();
      try {
        final success = await _dm.triggerWebDownload(streamUrl, '$safeName.m4a', track: track);
        _activeDownloads.remove(trackId);
        notifyListeners();
        onComplete?.call(success, success ? null : 'Browser download failed');
        return success;
      } catch (e) {
        _activeDownloads.remove(trackId);
        notifyListeners();
        onComplete?.call(false, e.toString());
        return false;
      }
    }

    // ── NATIVE: standard file download ──────────────────────────────────────
    await _nativeRequestPermissions();
    _activeDownloads[trackId] = 0;
    notifyListeners();

    try {
      final downloadDir = await _settingsService.getDownloadLocation();
      await PlatformHelper.ensureDir(downloadDir);

      final tempPath = '$downloadDir${PlatformHelper.pathSeparator}$safeName.tmp';

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
      if (!PlatformHelper.fileExists(tempPath)) {
        throw Exception('Download failed - file not found');
      }

      // Determine extension from Content-Type
      final contentType = response.headers.value('content-type');
      String extension = _detectExtension(contentType);

      print('[Download] Detected format: $extension (ContentType: $contentType)');

      final finalPath = '$downloadDir${PlatformHelper.pathSeparator}$safeName$extension';

      // Rename .tmp -> .extension
      await PlatformHelper.renameFile(tempPath, finalPath);

      // Write Metadata (Try-Catch Wrapper)
      print('[Download] Writing metadata to $finalPath...');
      await Future.delayed(const Duration(milliseconds: 500)); // Wait for file handle release
      
      await _writeMetadata(finalPath, track);

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

  Future<void> _nativeRequestPermissions() async {
    if (kIsWeb) return;
    // Permission requests are native-only (permission_handler)
    // We call them via the native helper to avoid dart:html/dart:io conflicts
    await _dm.requestNativePermissions(
      isAndroid: PlatformHelper.isAndroid,
      isIOS: PlatformHelper.isIOS,
    );
  }

  Future<void> _writeMetadata(String filePath, Track track) async {
    if (kIsWeb) return;
    // Delegated to native-only helper (audiotags/FlacUtils)
    await _dm.writeNativeMetadata(filePath, track, _dio);
  }

  Future<bool> _downloadDashTrack({
    required Track track,
    required String manifestDataUri,
    required String downloadDir,
    required String safeName,
    void Function(double progress)? onProgress,
    void Function(bool success, String? error)? onComplete,
  }) async {
    if (kIsWeb) {
      return _dm.downloadDashTrack(
        track: track,
        manifestDataUri: manifestDataUri,
        downloadDir: downloadDir,
        safeName: safeName,
        settingsService: _settingsService,
        dio: _dio,
        activeDownloads: _activeDownloads,
        notifyCallback: notifyListeners,
        onProgress: onProgress,
        onComplete: onComplete,
      );
    }
    return _dm.downloadDashTrack(
      track: track,
      manifestDataUri: manifestDataUri,
      downloadDir: downloadDir,
      safeName: safeName,
      settingsService: _settingsService,
      dio: _dio,
      activeDownloads: _activeDownloads,
      notifyCallback: notifyListeners,
      onProgress: onProgress,
      onComplete: onComplete,
    );
  }

  /// Delete a downloaded track
  Future<bool> deleteDownload(String trackId) async {
    if (kIsWeb) return false;
    final path = _settingsService.getLocalPath(trackId);
    if (path == null) return false;
    try {
      PlatformHelper.deleteFile(path);
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
