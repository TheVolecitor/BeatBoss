import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';

import 'settings_service.dart';
import '../models/models.dart';

/// Download Manager Service - mirrors Python DownloadManager class
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

      // Format selection: FLAC for Hi-Res, M4A for others
      // Note: This assumes the streamUrl actually provides that format relative to the metadata.
      final isHiRes = track.audioQuality?.isHiRes ?? false;
      final extension = isHiRes ? 'flac' : 'm4a';

      final filePath =
          '$downloadDir${Platform.pathSeparator}$safeName.$extension';

      print('[Download] Starting: $filePath');

      await _dio.download(
        streamUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total) * 100;
            _activeDownloads[trackId] = progress;
            onProgress?.call(progress);
            notifyListeners();
          }
        },
      );

      // Register download in settings (with metadata)
      await _settingsService.registerDownload(trackId, filePath, track: track);

      _activeDownloads.remove(trackId);
      notifyListeners();

      print('[Download] Complete: $filePath');
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
