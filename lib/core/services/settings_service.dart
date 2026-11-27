import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/hive/hive_provider.dart';
import 'dart:convert';
import '../utils/platform_helper.dart'; // compile-time conditional

import '../models/models.dart';
import '../models/addon_models.dart';
import '../theme/app_theme.dart';
import 'stream_cache/cache_models.dart';

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
  // New: Store Track metadata (ID -> JSON)
  static const String _keyDownloadedTracksMeta = 'downloaded_tracks_meta';
  // Addon system
  static const String _keyAddonsList = 'addons_list';
  static const String _keyActiveAddonId = 'active_addon_id';
  static const String _keyRemovedBuiltins = 'removed_builtins';
  static const String _keyAccentColor = 'accent_color';
  static const String _keySeekbarStyle = 'seekbar_style';

  // Local stream cache
  static const String _keyLocalCacheEnabled = 'local_cache_enabled';
  static const String _keyLocalCacheMaxMb = 'local_cache_max_mb';
  static const String _keyStreamCacheIndex = 'stream_cache_index';

  // New settings
  static const String _keyUseLastFmRecommendations = 'use_lastfm_recs';
  static const String _keyRecProvider = 'rec_provider';
  static const String _keyUseAddonCatalogRecs = 'use_addon_catalog_recs';
  static const String _keyAutoplaySimilar = 'autoplay_similar';
  static const String _keyEnablePrefetch = 'enable_prefetch';
  static const String _keyPrefetchDuration = 'prefetch_duration';
  static const String _keyCrossfadeDuration = 'crossfade_duration';
  static const String _keyFullscreenLeftPaneProportion = 'fullscreen_left_pane_proportion';

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _initialized = true;
    AppTheme.accentColor = Color(accentColorValue);
    notifyListeners();
  }

  int get accentColorValue =>
      _box.get(_keyAccentColor, defaultValue: 0xFF1DB954) as int;

  Future<void> setAccentColor(int argb) async {
    await _box.put(_keyAccentColor, argb);
    AppTheme.accentColor = Color(argb);
    notifyListeners();
  }

  /// Fullscreen player seekbar style: 'normal', 'sleek', 'waveform', 'heartbeat'.
  String get seekbarStyle =>
      (_box.get(_keySeekbarStyle, defaultValue: 'normal') as String?) ?? 'normal';

  Future<void> setSeekbarStyle(String style) async {
    await _box.put(_keySeekbarStyle, style);
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

  // ========== UI Settings ==========
  double get fullscreenLeftPaneProportion => _box.get(_keyFullscreenLeftPaneProportion, defaultValue: 0.5);

  Future<void> setFullscreenLeftPaneProportion(double value) async {
    await _box.put(_keyFullscreenLeftPaneProportion, value.clamp(0.2, 0.8));
    notifyListeners();
  }

  // ========== Local Stream Cache ==========
  bool get localCacheEnabled =>
      _box.get(_keyLocalCacheEnabled, defaultValue: false) == true;

  Future<void> setLocalCacheEnabled(bool enabled) async {
    await _box.put(_keyLocalCacheEnabled, enabled);
    notifyListeners();
  }

  /// Maximum size of the stream cache in MB.
  int get localCacheMaxMb {
    final value = _box.get(_keyLocalCacheMaxMb, defaultValue: kDefaultCacheSizeMb);
    return value is int && value > 0 ? value : kDefaultCacheSizeMb;
  }

  Future<void> setLocalCacheMaxMb(int mb) async {
    await _box.put(_keyLocalCacheMaxMb, mb);
    notifyListeners();
  }

  /// Cache index: key -> [StreamCacheEntry] JSON.
  Map<String, dynamic> getStreamCacheIndex() {
    final data = _box.get(_keyStreamCacheIndex, defaultValue: '{}');
    try {
      return Map<String, dynamic>.from(jsonDecode(data));
    } catch (e) {
      return {};
    }
  }

  /// Persists the cache index without notifying settings listeners (it
  /// changes on every cache hit).
  Future<void> saveStreamCacheIndex(Map<String, dynamic> index) async {
    await _box.put(_keyStreamCacheIndex, jsonEncode(index));
  }

  // ========== Download Location ==========
  Future<String> getDownloadLocation() async {
    // On web, downloads go directly via browser download dialog
    if (kIsWeb) return 'browser';

    String? saved = _box.get(_keyDownloadLocation);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }

    // Default: platform-specific Music folder
    if (PlatformHelper.isAndroid) {
      return '/storage/emulated/0/Music/BeatBoss';
    } else if (PlatformHelper.isWindows) {
      return _getWindowsMusicPath();
    } else if (PlatformHelper.isLinux || PlatformHelper.isMacOS) {
      return _getUnixMusicPath();
    }
    return 'downloads';
  }

  String _getWindowsMusicPath() =>
      PlatformHelper.getEnv('USERPROFILE', fallback: '') + r'\Music\BeatBoss';

  String _getUnixMusicPath() =>
      PlatformHelper.getEnv('HOME', fallback: '') + '/Music/BeatBoss';

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

  Future<void> registerDownload(String trackId, String filePath,
      {Track? track}) async {
    final downloads = getDownloadedTracks();
    downloads[trackId] = filePath;
    await _box.put(_keyDownloadedTracks, jsonEncode(downloads));

    if (track != null) {
      final meta = getDownloadedTracksMeta();
      meta[trackId] = track.toJson();
      await _box.put(_keyDownloadedTracksMeta, jsonEncode(meta));
    }
    notifyListeners();
  }

  // Get metadata map
  Map<String, dynamic> getDownloadedTracksMeta() {
    final data = _box.get(_keyDownloadedTracksMeta, defaultValue: '{}');
    try {
      return Map<String, dynamic>.from(jsonDecode(data));
    } catch (e) {
      return {};
    }
  }

  // Get list of downloaded tracks
  List<Track> getDownloadedTracksList() {
    final meta = getDownloadedTracksMeta();
    final fileMap = getDownloadedTracks();

    // Filter out tracks that definitely don't have files (orphaned meta),
    // or keep them if you trust sync. Best to intersect.

    List<Track> tracks = [];
    meta.forEach((key, value) {
      if (fileMap.containsKey(key)) {
        try {
          tracks.add(Track.fromJson(value));
        } catch (e) {
          print("Error parsing track meta for $key: $e");
        }
      }
    });

    // Sort by name or date? Unordered for now.
    return tracks;
  }

  Future<void> unregisterDownload(String trackId) async {
    final downloads = getDownloadedTracks();
    downloads.remove(trackId);
    await _box.put(_keyDownloadedTracks, jsonEncode(downloads));

    // Remove meta
    final meta = getDownloadedTracksMeta();
    meta.remove(trackId);
    await _box.put(_keyDownloadedTracksMeta, jsonEncode(meta));

    notifyListeners();
  }

  String? getLocalPath(String trackId) {
    return getDownloadedTracks()[trackId];
  }

  bool isDownloaded(String trackId) {
    if (kIsWeb) return false; // No local files on web
    final path = getLocalPath(trackId);
    if (path == null) return false;
    return PlatformHelper.fileExists(path);
  }

  int get downloadedCount => getDownloadedTracks().length;

  Future<int> getStorageSize() async {
    if (kIsWeb) return 0; // No local filesystem on web
    final downloads = getDownloadedTracks();
    int total = 0;
    for (final path in downloads.values) {
      total += PlatformHelper.fileSize(path);
    }
    return total;
  }

  Future<void> clearCache() async {
    final downloads = getDownloadedTracks();
    if (!kIsWeb) {
      for (final path in downloads.values) {
        try {
          PlatformHelper.deleteFile(path);
        } catch (e) {
          print('Error deleting $path: $e');
        }
      }
    }
    await _box.put(_keyDownloadedTracks, '{}');
    notifyListeners();
  }

  // ========== Addon System ==========

  List<AddonManifest> loadAddons() {
    final dataString = _box.get(_keyAddonsList);
    if (dataString == null || dataString.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(dataString);
      return jsonList.map((item) => AddonManifest.fromJson(item)).toList();
    } catch (e) {
      print('[SettingsService] Failed to load addons: $e');
      return [];
    }
  }

  Future<void> saveAddons(List<AddonManifest> addons) async {
    final jsonList = addons.map((a) => a.toJson()).toList();
    await _box.put(_keyAddonsList, jsonEncode(jsonList));
  }

  String? getActiveAddonId() {
    return _box.get(_keyActiveAddonId);
  }

  Future<void> setActiveAddonId(String id) async {
    await _box.put(_keyActiveAddonId, id);
  }

  Map<String, dynamic> getAddonSettings(String addonId) {
    final raw = _box.get('addon_settings_$addonId');
    if (raw is! String || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> setAddonSetting(String addonId, String key, dynamic value) async {
    final map = getAddonSettings(addonId);
    map[key] = value;
    await _box.put('addon_settings_$addonId', jsonEncode(map));
    notifyListeners();
  }

  String? getAddonDisplayName(String addonId) {
    final v = _box.get('addon_name_$addonId');
    return (v is String && v.trim().isNotEmpty) ? v.trim() : null;
  }

  Future<void> setAddonDisplayName(String addonId, String? name) async {
    if (name == null || name.trim().isEmpty) {
      await _box.delete('addon_name_$addonId');
    } else {
      await _box.put('addon_name_$addonId', name.trim());
    }
    notifyListeners();
  }

  bool getAddonNotificationsEnabled(String addonId) =>
      _box.get('addon_notices_$addonId', defaultValue: true) == true;

  Future<void> setAddonNotificationsEnabled(String addonId, bool enabled) async {
    await _box.put('addon_notices_$addonId', enabled);
    notifyListeners();
  }

  bool isAddonEnabled(String addonId) =>
      _box.get('addon_enabled_$addonId', defaultValue: true) == true;

  Future<void> setAddonEnabled(String addonId, bool enabled) async {
    await _box.put('addon_enabled_$addonId', enabled);
    notifyListeners();
  }

  bool hasSeenAddonNoticeId(String addonId, String noticeId) {
    final list = _box.get('addon_seen_notices_$addonId');
    return list is List && list.contains(noticeId);
  }

  Future<void> markAddonNoticeIdSeen(String addonId, String noticeId) async {
    final list = List<String>.from(
        (_box.get('addon_seen_notices_$addonId') as List?) ?? const []);
    if (!list.contains(noticeId)) {
      list.add(noticeId);
      await _box.put('addon_seen_notices_$addonId', list);
    }
  }

  // ========== Removed Built-ins ==========

  List<String> getRemovedBuiltins() {
    final data = _box.get(_keyRemovedBuiltins, defaultValue: []);
    return List<String>.from(data);
  }

  bool isBuiltinRemoved(String id) {
    return getRemovedBuiltins().contains(id);
  }

  Future<void> markBuiltinRemoved(String id) async {
    final removed = getRemovedBuiltins();
    if (!removed.contains(id)) {
      removed.add(id);
      await _box.put(_keyRemovedBuiltins, removed);
      notifyListeners();
    }
  }

  Future<void> markBuiltinRestored(String id) async {
    final removed = getRemovedBuiltins();
    if (removed.contains(id)) {
      removed.remove(id);
      await _box.put(_keyRemovedBuiltins, removed);
      notifyListeners();
    }
  }

  // ========== New Playback & Last.fm Settings ==========

  bool get useLastFmRecommendations => _box.get(_keyUseLastFmRecommendations, defaultValue: false);
  Future<void> setUseLastFmRecommendations(bool value) async {
    await _box.put(_keyUseLastFmRecommendations, value);
    notifyListeners();
  }

  /// Value of [recProviderId] that switches every recommendation source off:
  /// no personal recommendations, no autoplay, no radio.
  static const String recSourceOff = 'off';

  /// Which recommendation source is active (see `RecommendationProvider.id`),
  /// or [recSourceOff].
  String get recProviderId => _box.get(_keyRecProvider, defaultValue: 'lastfm');

  /// A recommendation source is switched on (not [recSourceOff]).
  bool get recSourceEnabled => recProviderId != recSourceOff;

  /// Autoplay is effectively on: its own switch, and a source to ask.
  bool get autoplayActive => autoplaySimilar && recSourceEnabled;
  Future<void> setRecProviderId(String value) async {
    await _box.put(_keyRecProvider, value);
    notifyListeners();
  }

  /// Show the active addon's own catalog (tracks, albums, playlists) on the
  /// home screen. Off means the addon isn't asked for a catalog at all.
  bool get useAddonCatalogRecommendations =>
      _box.get(_keyUseAddonCatalogRecs, defaultValue: true);
  Future<void> setUseAddonCatalogRecommendations(bool value) async {
    await _box.put(_keyUseAddonCatalogRecs, value);
    notifyListeners();
  }

  /// When the queue runs out, fill it with songs similar to the one playing.
  /// This sends the song's title and artist to Last.fm, so it has a toggle.
  bool get autoplaySimilar => _box.get(_keyAutoplaySimilar, defaultValue: true);
  Future<void> setAutoplaySimilar(bool value) async {
    await _box.put(_keyAutoplaySimilar, value);
    notifyListeners();
  }

  bool get enablePrefetch => _box.get(_keyEnablePrefetch, defaultValue: true);
  Future<void> setEnablePrefetch(bool value) async {
    await _box.put(_keyEnablePrefetch, value);
    notifyListeners();
  }

  int get prefetchDuration => _box.get(_keyPrefetchDuration, defaultValue: 30);
  Future<void> setPrefetchDuration(int seconds) async {
    await _box.put(_keyPrefetchDuration, seconds);
    notifyListeners();
  }

  int get crossfadeDuration => _box.get(_keyCrossfadeDuration, defaultValue: 0);
  Future<void> setCrossfadeDuration(int seconds) async {
    await _box.put(_keyCrossfadeDuration, seconds);
    notifyListeners();
  }
}
