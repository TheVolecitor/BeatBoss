import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

import '../models/models.dart';

/// Settings service - matches original Python Settings class
/// Handles theme, download location, play history, user credentials
class SettingsService extends ChangeNotifier {
  static const String _boxName = 'beatboss_settings';
  late Box _box;
  
  bool _initialized = false;
  bool get isInitialized => _initialized;

  // Settings keys
  static const String _keyTheme = 'theme';
  static const String _keyDownloadLocation = 'download_location';
  static const String _keyPlayHistory = 'play_history';
  static const String _keyUser = 'user';
  static const String _keyDownloadedTracks = 'downloaded_tracks';

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _initialized = true;
    notifyListeners();
  }

  // ========== Theme ==========
  bool get isDarkMode => (_box.get(_keyTheme, defaultValue: 'dark')) == 'dark';
  
  String get theme => _box.get(_keyTheme, defaultValue: 'dark');
  
  Future<void> setTheme(String theme) async {
    await _box.put(_keyTheme, theme);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await setTheme(isDarkMode ? 'light' : 'dark');
  }

  // ========== Download Location ==========
  Future<String> getDownloadLocation() async {
    String? saved = _box.get(_keyDownloadLocation);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    
    // Default: Music folder
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Music/BeatBoss';
    } else if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? '';
      return '$home\\Music\\BeatBoss';
    } else if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return '$home/Music/BeatBoss';
    }
    
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/BeatBoss';
  }

  Future<void> setDownloadLocation(String path) async {
    await _box.put(_keyDownloadLocation, path);
    notifyListeners();
  }

  // ========== Play History ==========
  List<Track> getPlayHistory() {
    final historyJson = _box.get(_keyPlayHistory, defaultValue: '[]');
    try {
      final List<dynamic> list = jsonDecode(historyJson);
      return list.map((t) => Track.fromJson(t)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> setPlayHistory(List<Track> history) async {
    final jsonList = history.map((t) => t.toJson()).toList();
    await _box.put(_keyPlayHistory, jsonEncode(jsonList));
    notifyListeners();
  }

  Future<void> addToPlayHistory(Track track) async {
    final history = getPlayHistory();
    // Remove if already exists
    history.removeWhere((t) => t.id == track.id);
    // Add to front
    history.insert(0, track);
    // Keep last 5
    final trimmed = history.take(5).toList();
    await setPlayHistory(trimmed);
  }

  // ========== User / Auth ==========
  User? getUser() {
    final userJson = _box.get(_keyUser);
    if (userJson != null && userJson.isNotEmpty) {
      try {
        return User.fromJson(jsonDecode(userJson));
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Future<void> saveUser(User user) async {
    await _box.put(_keyUser, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> clearUser() async {
    await _box.delete(_keyUser);
    notifyListeners();
  }

  bool get isLoggedIn => getUser() != null;
  String? get authToken => getUser()?.token;

  // ========== Downloaded Tracks Registry ==========
  Map<String, String> getDownloadedTracks() {
    final data = _box.get(_keyDownloadedTracks, defaultValue: '{}');
    try {
      return Map<String, String>.from(jsonDecode(data));
    } catch (e) {
      return {};
    }
  }

  Future<void> registerDownload(String trackId, String filePath) async {
    final downloads = getDownloadedTracks();
    downloads[trackId] = filePath;
    await _box.put(_keyDownloadedTracks, jsonEncode(downloads));
    notifyListeners();
  }

  Future<void> unregisterDownload(String trackId) async {
    final downloads = getDownloadedTracks();
    downloads.remove(trackId);
    await _box.put(_keyDownloadedTracks, jsonEncode(downloads));
    notifyListeners();
  }

  String? getLocalPath(String trackId) {
    return getDownloadedTracks()[trackId];
  }

  bool isDownloaded(String trackId) {
    final path = getLocalPath(trackId);
    if (path == null) return false;
    return File(path).existsSync();
  }

  int get downloadedCount => getDownloadedTracks().length;

  Future<int> getStorageSize() async {
    final downloads = getDownloadedTracks();
    int total = 0;
    for (final path in downloads.values) {
      final file = File(path);
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }

  Future<void> clearCache() async {
    final downloads = getDownloadedTracks();
    for (final path in downloads.values) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting $path: $e');
      }
    }
    await _box.put(_keyDownloadedTracks, '{}');
    notifyListeners();
  }
}
