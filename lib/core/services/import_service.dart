import 'package:flutter/foundation.dart';
import '../../features/import/playlist_import_dialog.dart'; // For ImportItem class
import 'addon_service.dart';
import 'local_library_service.dart';

class ImportService extends ChangeNotifier {
  bool _isImporting = false;
  bool _isBackgrounded = false;
  bool _shouldStop = false;

  int _totalTracks = 0;
  int _importedCount = 0;
  String _statusMessage = '';

  bool get isImporting => _isImporting;
  bool get isBackgrounded => _isBackgrounded;
  int get totalTracks => _totalTracks;
  int get importedCount => _importedCount;
  String get statusMessage => _statusMessage;

  double get progress => _totalTracks == 0 ? 0 : _importedCount / _totalTracks;

  void setBackground(bool value) {
    _isBackgrounded = value;
    notifyListeners();
  }

  void stopImport() {
    _shouldStop = true;
    _statusMessage = 'Stopping import...';
    notifyListeners();
  }

  void _reset() {
    _isImporting = false;
    _isBackgrounded = false;
    _shouldStop = false;
    _totalTracks = 0;
    _importedCount = 0;
    _statusMessage = '';
    notifyListeners();
  }

  Future<void> startImport({
    required AddonService addonService,
    LocalLibraryService? localLibraryService,
    required String libraryId,
    required List<ImportItem> tracks,
  }) async {
    if (_isImporting) return;

    _reset();
    _isImporting = true;
    _totalTracks = tracks.length;
    notifyListeners();

    int nextIndex = 0;
    bool isPausedForRateLimit = false;

    Future<void> worker(int workerId) async {
      while (nextIndex < tracks.length && !_shouldStop) {
        if (isPausedForRateLimit) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        final currentIndex = nextIndex++;
        if (currentIndex >= tracks.length) break;
        
        final item = tracks[currentIndex];

        _statusMessage = 'Importing: ${item.title}';
        notifyListeners();

        print('[ImportWorker-$workerId] Processing Track ${currentIndex + 1}/$_totalTracks: ${item.title}');

        try {
          String query = '${item.title} ${item.subtitle}'
              .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '') // Remove parentheses and brackets
              .replaceAll(RegExp(r'\s+HD(\s+|$)', caseSensitive: false), ' ')
              .replaceAll(RegExp(r'\s+LYRICS(\s+|$)', caseSensitive: false), ' ')
              .replaceAll(RegExp(r'\s+OFFICIAL\s+(VIDEO|AUDIO|MUSIC)(\s+|$)', caseSensitive: false), ' ')
              .replaceAll(RegExp(r'\s+4K(\s+|$)', caseSensitive: false), ' ')
              .trim();

          final results = await addonService.search(query);

          if (_shouldStop) break;

          if (results != null && results.tracks.isNotEmpty) {
            final track = results.tracks.first;
            
            bool success = false;
            // Check if local library
            if (libraryId.startsWith('local_') && localLibraryService != null) {
              success = await localLibraryService.addTrackToLibrary(libraryId, track.toTrack());
            } else {
              // Use generic addon service addition
              success = await addonService.addTracksToLibrary(libraryId, [track.toTrack()]);
            }

            if (success) {
              _importedCount++;
            } else {
              print('[ImportWorker-$workerId] Failed to add track: ${item.title}');
            }
          } else {
            print('[ImportWorker-$workerId] No results for: $query');
          }
        } catch (e) {
          print('[ImportWorker-$workerId] Error for ${item.title}: $e');
          if (e.toString().contains('429')) {
            print('[ImportWorker-$workerId] Rate limit (429)! Triggering global cooldown...');
            isPausedForRateLimit = true;
            nextIndex--; // Put it back in the queue
            await Future.delayed(const Duration(seconds: 5));
            isPausedForRateLimit = false;
          }
        }

        notifyListeners();
        // Subtle variable delay to stagger requests even within threads
        await Future.delayed(Duration(milliseconds: 200 + (workerId * 50)));
      }
    }

    // Spawn 5 parallel workers
    const int workerCount = 5;
    final List<Future<void>> workers = [];
    for (int i = 0; i < workerCount; i++) {
      workers.add(worker(i));
    }

    await Future.wait(workers);

    if (_shouldStop) {
      _statusMessage = 'Import Stopped';
    } else {
      _statusMessage = 'Done!';
    }

    _isImporting = false;
    notifyListeners();

    // Auto-clear background state after a moment if finished
    if (!_shouldStop) {
      await Future.delayed(const Duration(seconds: 3));
      _isBackgrounded = false;
      notifyListeners();
    }
  }
}
