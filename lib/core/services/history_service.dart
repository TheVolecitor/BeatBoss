import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../utils/platform_helper.dart'; // compile-time conditional

class HistoryService with ChangeNotifier {
  static const String _fileName = 'dab_history.json';

  List<Track> _recentlyPlayed = [];
  List<String> _recentSearches = [];

  List<Track> get recentlyPlayed => _recentlyPlayed;
  List<String> get recentSearches => _recentSearches;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    if (!kIsWeb) await _load();
    _initialized = true;
  }

  Future<void> addPlayed(Track track) async {
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > 5) {
      _recentlyPlayed = _recentlyPlayed.sublist(0, 5);
    }
    notifyListeners();
    if (!kIsWeb) await _save();
  }

  Future<void> addSearch(String query) async {
    if (query.trim().isEmpty) return;
    _recentSearches.removeWhere((s) => s.toLowerCase() == query.toLowerCase());
    _recentSearches.insert(0, query);
    if (_recentSearches.length > 5) {
      _recentSearches = _recentSearches.sublist(0, 5);
    }
    notifyListeners();
    if (!kIsWeb) await _save();
  }

  Future<void> clearHistory() async {
    _recentlyPlayed.clear();
    _recentSearches.clear();
    notifyListeners();
    if (!kIsWeb) await _save();
  }

  Future<String?> _getFilePath() async {
    if (kIsWeb) return null;
    try {
      return PlatformHelper.getHistoryFilePath(_fileName);
    } catch (e) {
      print('Error getting path: $e');
      return null;
    }
  }

  Future<void> _save() async {
    try {
      final path = await _getFilePath();
      if (path == null) return;
      final data = {
        'recent_played': _recentlyPlayed.map((t) => t.toJson()).toList(),
        'recent_search': _recentSearches,
      };
      await PlatformHelper.writeFile(path, jsonEncode(data));
    } catch (e) {
      print('Error saving history: $e');
    }
  }

  Future<void> _load() async {
    try {
      final path = await _getFilePath();
      if (path == null) return;
      final content = await PlatformHelper.readFile(path);
      if (content == null) return;
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
    } catch (e) {
      print('Error loading history: $e');
    }
  }
}
