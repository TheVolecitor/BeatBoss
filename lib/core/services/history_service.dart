import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

class HistoryService with ChangeNotifier {
  static const String _fileName = 'dab_history.json';

  List<Track> _recentlyPlayed = [];
  List<String> _recentSearches = [];

  List<Track> get recentlyPlayed => _recentlyPlayed;
  List<String> get recentSearches => _recentSearches;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _load();
    _initialized = true;
  }

  Future<void> addPlayed(Track track) async {
    // Remove if exists to move to top
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);

    if (_recentlyPlayed.length > 5) {
      _recentlyPlayed = _recentlyPlayed.sublist(0, 5);
    }

    notifyListeners();
    await _save();
  }

  Future<void> addSearch(String query) async {
    if (query.trim().isEmpty) return;

    _recentSearches.removeWhere((s) => s.toLowerCase() == query.toLowerCase());
    _recentSearches.insert(0, query);

    if (_recentSearches.length > 5) {
      _recentSearches = _recentSearches.sublist(0, 5);
    }

    notifyListeners();
    await _save();
  }

  Future<void> clearHistory() async {
    _recentlyPlayed.clear();
    _recentSearches.clear();
    notifyListeners();
    await _save();
  }

  Future<String?> _getFilePath() async {
    try {
      Directory? directory;
      if (Platform.isWindows) {
        // Use user's download path or document path
        // path_provider getDownloadsDirectory works on Windows
        directory = await getDownloadsDirectory();
      } else if (Platform.isAndroid) {
        // Use internal app storage for history to ensure it works without permissions
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null) {
        return '${directory.path}${Platform.pathSeparator}$_fileName';
      }
    } catch (e) {
      print("Error getting path: $e");
    }
    return null;
  }

  Future<void> _save() async {
    try {
      final path = await _getFilePath();
      if (path == null) return;

      final data = {
        'recent_played': _recentlyPlayed.map((t) => t.toJson()).toList(),
        'recent_search': _recentSearches,
      };

      final file = File(path);
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      print("Error saving history: $e");
    }
  }

  Future<void> _load() async {
    try {
      final path = await _getFilePath();
      if (path == null) return;

      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);

        if (data is Map<String, dynamic>) {
          if (data['recent_played'] != null) {
            _recentlyPlayed = (data['recent_played'] as List)
                .map((item) => Track.fromJson(item))
                .toList();
          }
          if (data['recent_search'] != null) {
            _recentSearches = List<String>.from(data['recent_search']);
          }
        }
        notifyListeners();
      }
    } catch (e) {
      print("Error loading history: $e");
    }
  }
}
