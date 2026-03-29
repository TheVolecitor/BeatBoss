import 'package:flutter/foundation.dart';
import '../../features/import/playlist_import_dialog.dart'; // For ImportItem class
import 'dab_api_service.dart';

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
    required DabApiService api,
    required String libraryId,
    required List<ImportItem> tracks,
  }) async {
    if (_isImporting) return;

    _reset();
    _isImporting = true;
    _totalTracks = tracks.length;
    notifyListeners();

    for (var i = 0; i < tracks.length; i++) {
      if (_shouldStop) {
        _statusMessage = 'Import Cancelled';
        _isImporting = false;
        notifyListeners();
        return;
      }

      final item = tracks[i];
      _statusMessage = 'Importing: ${item.title}';
      notifyListeners();

      print(
          '[ImportService] Processing Track ${i + 1}/$_totalTracks: ${item.title}');

      try {
        String query = '${item.title} ${item.subtitle}'
            .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
            .trim();

        final results = await api.search(query, limit: 1);

        if (_shouldStop) break; // Check again after await

        if (results != null && results.tracks.isNotEmpty) {
          final track = results.tracks.first;
          final success = await api.addTrackToLibrary(libraryId, track);

          if (success) {
            _importedCount++;
          } else {
            print('[ImportService] Failed to add track: ${item.title}');
          }
        } else {
          print('[ImportService] No results for: $query');
        }
      } catch (e) {
        print('[ImportService] Error for ${item.title}: $e');
        if (e.toString().contains('429')) {
          print(
              '[ImportService] Rate limit (429)! Waiting 4 seconds strictly...');
          await Future.delayed(const Duration(seconds: 4));
          // Decrement i to retry the exact same track
          i--;
          continue; // Skip the standard delay below and restart the loop for this track
        }
      }

      if (_shouldStop) break;

      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 800));
    }

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
