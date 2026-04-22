import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../models/models.dart';
import 'addon_service.dart';

class LocalLibraryService extends ChangeNotifier {
  static const String _metaBoxName = 'local_libraries_meta';
  static const String _tracksBoxName = 'local_library_tracks';
  static const String _favoritesBoxName = 'local_favorites';

  late Box _metaBox;
  late Box _tracksBox;
  late Box _favoritesBox;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    _metaBox = await Hive.openBox(_metaBoxName);
    _tracksBox = await Hive.openBox(_tracksBoxName);
    _favoritesBox = await Hive.openBox(_favoritesBoxName);

    _initialized = true;
    notifyListeners();
  }

  // ========== LIBRARIES ==========

  List<MusicLibrary> getLibraries() {
    if (!_initialized) return [];

    final List<MusicLibrary> libs = [];
    for (var key in _metaBox.keys) {
      final data = _metaBox.get(key);
      if (data != null && data is Map) {
        // Build Track count manually to ensure accuracy
        final tracksData = _tracksBox.get(key);
        int trackCount = 0;
        if (tracksData != null && tracksData is List) {
          trackCount = tracksData.length;
        }

        libs.add(MusicLibrary(
          id: key.toString(),
          name: data['name'] ?? 'Unnamed',
          trackCount: trackCount,
        ));
      }
    }
    return libs..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<MusicLibrary> createLibrary(String name) async {
    final id = 'local_${DateTime.now().millisecondsSinceEpoch}';

    await _metaBox.put(id, {'name': name});
    await _tracksBox.put(id, []); // Initialize empty track list

    notifyListeners();
    return MusicLibrary(id: id, name: name, trackCount: 0);
  }

  Future<bool> updateLibrary(String libraryId, String newName) async {
    if (!_metaBox.containsKey(libraryId)) return false;

    await _metaBox.put(libraryId, {'name': newName});
    notifyListeners();
    return true;
  }

  Future<bool> deleteLibrary(String libraryId) async {
    if (!_metaBox.containsKey(libraryId)) return false;

    await _metaBox.delete(libraryId);
    await _tracksBox.delete(libraryId);

    notifyListeners();
    return true;
  }

  // ========== TRACKS ==========

  List<Track> getLibraryTracks(String libraryId) {
    if (!_initialized) return [];

    final tracksData = _tracksBox.get(libraryId);
    if (tracksData != null && tracksData is List) {
      return tracksData
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  Future<bool> addTrackToLibrary(String libraryId, Track track) async {
    if (!_initialized || !_tracksBox.containsKey(libraryId)) return false;

    final List<dynamic> currentTracks = _tracksBox.get(libraryId) ?? [];

    // Avoid duplicates by ID
    if (currentTracks.any((t) => t['id'] == track.id)) {
      return true; // Already exists
    }

    currentTracks.add(track.toJson());
    await _tracksBox.put(libraryId, currentTracks);

    notifyListeners();
    return true;
  }

  // ========== FAVOURITES ==========

  List<Track> getFavourites() {
    if (!_initialized) return [];
    final List<dynamic> favs = _favoritesBox.values.toList();
    return favs
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  bool isFavourite(String trackId) {
    if (!_initialized) return false;
    return _favoritesBox.containsKey(trackId);
  }

  Future<void> toggleFavourite(Track track,
      {AddonService? addonService}) async {
    if (!_initialized) return;
    bool isAdding = true;
    if (_favoritesBox.containsKey(track.id)) {
      await _favoritesBox.delete(track.id);
      isAdding = false;
    } else {
      await _favoritesBox.put(track.id, track.toJson());
    }
    notifyListeners();

    if (addonService != null &&
        (addonService.supportsSync || addonService.supportsLibrary)) {
      // Background sync to cloud via helper
      addonService.syncFavouritesCloud(track, isAdding);
    }
  }

  Future<bool> removeTrackFromLibrary(String libraryId, String trackId) async {
    if (!_initialized || !_tracksBox.containsKey(libraryId)) return false;

    final List<dynamic> currentTracks = _tracksBox.get(libraryId) ?? [];

    final initialLength = currentTracks.length;
    currentTracks.removeWhere((t) => t['id'] == trackId);

    if (currentTracks.length != initialLength) {
      await _tracksBox.put(libraryId, currentTracks);
      notifyListeners();
      return true;
    }

    return false;
  }

  // ========== EXPORT / IMPORT ==========

  Future<String?> exportLibraries() async {
    if (!_initialized) return null;

    final Map<String, dynamic> exportData = {
      'version': 1,
      'libraries': [],
    };

    final libs = getLibraries();
    for (var lib in libs) {
      final tracks = getLibraryTracks(lib.id);
      exportData['libraries'].add({
        'id': lib.id,
        'name': lib.name,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      });
    }

    final jsonString = jsonEncode(exportData);

    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select an output file:',
        fileName: 'beatboss_libraries.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputFile == null) return null; // Cancelled

      final file = File(outputFile);
      await file.writeAsString(jsonString);
      return outputFile;
    } catch (e) {
      print('Export error: $e');
      return null;
    }
  }

  Future<int> importLibraries() async {
    if (!_initialized) return 0;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select library export file:',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        final exportData = jsonDecode(jsonString);

        if (exportData['version'] == 1 && exportData['libraries'] is List) {
          int importedCount = 0;
          final List<dynamic> libraries = exportData['libraries'];

          for (var libData in libraries) {
            String libId = libData['id'] ??
                'local_${DateTime.now().millisecondsSinceEpoch}_$importedCount';
            String libName = libData['name'] ?? 'Imported Library';
            List<dynamic> tracksData = libData['tracks'] ?? [];

            // Prevent overwriting existing by appending if name exists?
            // Actually, keep original ID to allow syncing
            await _metaBox.put(libId, {'name': libName});

            // Merge tracks
            List<dynamic> existingTracks = _tracksBox.get(libId) ?? [];
            for (var trackMap in tracksData) {
              if (trackMap is Map<String, dynamic>) {
                // simple duplicate check
                if (!existingTracks.any((t) => t['id'] == trackMap['id'])) {
                  existingTracks.add(trackMap);
                }
              }
            }
            await _tracksBox.put(libId, existingTracks);
            importedCount++;
          }

          notifyListeners();
          return importedCount;
        }
      }
    } catch (e) {
      print('Import error: $e');
    }
    return 0; // Error or cancelled
  }
}
