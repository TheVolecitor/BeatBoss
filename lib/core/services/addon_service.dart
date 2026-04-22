import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../models/addon_models.dart';
import '../models/models.dart';
import 'settings_service.dart';


import 'user_addon_handler.dart';

/// AddonService — the central addon router for BeatBoss.
///
/// Manages two types of addons:
///   1. Server-based — remote HTTP servers following the Eclipse Music spec.
///      The app fetches /manifest.json then calls /search, /stream/{id}, etc.
///   2. User-based — device-side Dart handlers (UserAddonHandler).
///
/// UI reads from this service via Provider. Audio playback routes through
/// getStreamUrl(). Search routes through search().
class AddonService extends ChangeNotifier {
  final SettingsService _settings;

  // Registered device-side handlers (keyed by addon ID)
  final Map<String, UserAddonHandler> _userHandlers = {};

  // Installed addon manifests (from Hive via SettingsService)
  List<AddonManifest> _installedAddons = [];

  // Currently active addon ID for search
  String? _activeAddonId;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  ));

  AddonService({required SettingsService settingsService})
      : _settings = settingsService;

  // ========== Getters ==========

  List<AddonManifest> get installedAddons => List.unmodifiable(_installedAddons);

  String? get activeAddonId => _activeAddonId;

  AddonManifest? get activeAddon {
    if (_activeAddonId == null) return null;
    try {
      return _installedAddons.firstWhere((a) => a.id == _activeAddonId);
    } catch (_) {
      return _installedAddons.isNotEmpty ? _installedAddons.first : null;
    }
  }

  bool get hasSearchCapableAddon =>
      _installedAddons.any((a) => a.supportsSearch);

  List<AddonManifest> getAddonsForResource(String resource) {
    return _installedAddons.where((a) => a.resources.contains(resource)).toList();
  }

  // ========== Init ==========

  /// Called at app startup. Loads saved addons and pre-installs built-ins.
  Future<void> initAddons() async {
    _installedAddons = _settings.loadAddons();
    _activeAddonId = _settings.getActiveAddonId();

    // Pre-install any registered user handler whose manifest isn't stored yet
    for (final handler in _userHandlers.values) {
      final m = handler.manifest;
      if (!_installedAddons.any((a) => a.id == m.id)) {
        // Only re-install if it hasn't been explicitly removed by the user
        if (!_settings.isBuiltinRemoved(m.id)) {
          _installedAddons.add(m);
        }
      }
    }

    // No auto-activation by default. User must select an addon.
    if (_activeAddonId != null &&
        !_installedAddons.any((a) => a.id == _activeAddonId)) {
      _activeAddonId = null;
    }

    await _settings.saveAddons(_installedAddons);
    notifyListeners();
  }

  // ========== Handler Registration ==========

  /// Register a device-side addon handler. Call this at startup before initAddons().
  void registerUserHandler(String addonId, UserAddonHandler handler) {
    _userHandlers[addonId] = handler;
  }

  UserAddonHandler? getUserAddonHandler(String addonId) =>
      _userHandlers[addonId];

  // ========== Active Addon ==========

  Future<void> setActiveAddon(String addonId) async {
    if (!_installedAddons.any((a) => a.id == addonId)) return;
    _activeAddonId = addonId;
    await _settings.setActiveAddonId(addonId);
    notifyListeners();
  }

  // ========== Install / Uninstall ==========

  /// Install an addon by URL. Fetches the manifest, validates it, and stores.
  /// Returns the installed manifest on success or throws on error.
  Future<AddonManifest> installAddon(String url) async {
    // Normalize URL
    final baseUrl = _normalizeBaseUrl(url);
    final manifestUrl = '$baseUrl/manifest.json';

    // Fetch manifest
    final response = await _dio.get(manifestUrl);
    if (response.statusCode != 200 || response.data == null) {
      throw Exception('Failed to fetch manifest from $manifestUrl');
    }

    Map<String, dynamic> data;
    if (response.data is String) {
      data = jsonDecode(response.data);
    } else if (response.data is Map) {
      data = Map<String, dynamic>.from(response.data);
    } else {
      throw Exception('Invalid manifest format');
    }

    // Validate required fields
    final id = data['id']?.toString();
    final name = data['name']?.toString();
    final version = data['version']?.toString();
    final resources = data['resources'];

    if (id == null || id.isEmpty) throw Exception('Manifest missing required field: id');
    if (name == null || name.isEmpty) throw Exception('Manifest missing required field: name');
    if (version == null) throw Exception('Manifest missing required field: version');
    if (resources == null) throw Exception('Manifest missing required field: resources');

    // Check for duplicate
    if (_installedAddons.any((a) => a.id == id)) {
      throw Exception('Addon "$name" is already installed');
    }

    final manifest = AddonManifest.fromEclipseJson(data, baseUrl: baseUrl);

    _installedAddons.add(manifest);
    await _settings.saveAddons(_installedAddons);

    // Auto-activate if first search-capable addon
    if (_activeAddonId == null && manifest.supportsSearch) {
      _activeAddonId = manifest.id;
      await _settings.setActiveAddonId(manifest.id);
    }

    notifyListeners();
    return manifest;
  }

  /// Preview a manifest from a URL without installing it.
  Future<AddonManifest> previewManifest(String url) async {
    final baseUrl = _normalizeBaseUrl(url);
    final manifestUrl = '$baseUrl/manifest.json';

    final response = await _dio.get(manifestUrl);
    if (response.statusCode != 200 || response.data == null) {
      throw Exception('Could not reach $manifestUrl');
    }

    Map<String, dynamic> data;
    if (response.data is String) {
      data = jsonDecode(response.data);
    } else if (response.data is Map) {
      data = Map<String, dynamic>.from(response.data);
    } else {
      throw Exception('Invalid manifest format');
    }

    return AddonManifest.fromEclipseJson(data, baseUrl: baseUrl);
  }

  Future<void> uninstallAddon(String addonId) async {
    final addon = _installedAddons.firstWhere(
      (a) => a.id == addonId,
      orElse: () => throw Exception('Addon not found'),
    );

    if (addon.isBuiltIn) {
      await _settings.markBuiltinRemoved(addonId);
    }

    _installedAddons.removeWhere((a) => a.id == addonId);
    await _settings.saveAddons(_installedAddons);

    if (_activeAddonId == addonId) {
      _activeAddonId = _installedAddons.isNotEmpty ? _installedAddons.first.id : null;
      if (_activeAddonId != null) {
        await _settings.setActiveAddonId(_activeAddonId!);
      }
    }

    notifyListeners();
  }

  // ========== Search ==========

  /// Search using the specified addon (defaults to active addon).
  Future<AddonSearchResult?> search(String query, {String? addonId, int? limit}) async {
    final id = addonId ?? _activeAddonId;
    if (id == null) return null;

    final manifest = _installedAddons.firstWhere(
      (a) => a.id == id,
      orElse: () => throw Exception('Addon $id not found'),
    );

    if (manifest.addonType == AddonType.user) {
      return _userHandlers[id]?.search(query); // User handlers handle limit internally if they want
    } else {
      return _serverSearch(manifest, query, limit: limit);
    }
  }

  Future<AddonSearchResult?> _serverSearch(
      AddonManifest manifest, String query, {int? limit}) async {
    try {
      final response = await _dio.get(
        '${manifest.baseUrl}/search',
        queryParameters: {
          'q': query,
          if (limit != null) 'limit': limit,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        Map<String, dynamic> data;
        if (response.data is String) {
          data = jsonDecode(response.data);
        } else {
          data = Map<String, dynamic>.from(response.data);
        }
        return AddonSearchResult.fromJson(data, addonId: manifest.id);
      }
    } catch (e) {
      print('[AddonService] Server search error for ${manifest.id}: $e');
    }
    return null;
  }

  // ========== Stream Resolution ==========

  /// Resolve a playable URL for a track. Checks pre-resolved streamURL first.
  Future<String?> getStreamUrl(String trackId, {String? addonId, String? preResolvedUrl}) async {
    // If the track already has a direct URL (Eclipse spec optional field), use it
    if (preResolvedUrl != null && preResolvedUrl.isNotEmpty) {
      return preResolvedUrl;
    }

    final result = await getStreamResult(trackId, addonId: addonId);
    return result?.url;
  }

  /// Resolve a full stream result (url + metadata) for a track.
  Future<AddonStreamResult?> getStreamResult(String trackId, {String? addonId}) async {
    final id = addonId ?? _activeAddonId;
    if (id == null) return null;

    final manifest = _getManifest(id);
    if (manifest == null) return null;

    if (manifest.addonType == AddonType.user) {
      return await _userHandlers[id]?.getStreamResult(trackId);
    } else {
      return _serverGetStreamResult(manifest, trackId);
    }
  }

  Future<AddonStreamResult?> _serverGetStreamResult(
      AddonManifest manifest, String trackId) async {
    try {
      final response =
          await _dio.get('${manifest.baseUrl}/stream/$trackId');
      if (response.statusCode == 200 && response.data != null) {
        final data = _toMap(response.data);
        return AddonStreamResult.fromJson(data);
      }
    } catch (e) {
      print('[AddonService] Server stream error for ${manifest.id}/$trackId: $e');
    }
    return null;
  }


  // ========== Catalog Endpoints ==========

  Future<AddonAlbum?> getAlbumDetail(String albumId, {String? addonId}) async {
    final id = addonId ?? _activeAddonId;
    if (id == null) return null;
    final manifest = _getManifest(id);
    if (manifest == null) return null;

    if (manifest.addonType == AddonType.user) {
      return _userHandlers[id]?.getAlbumDetail(albumId);
    }
    try {
      final response = await _dio.get('${manifest.baseUrl}/album/$albumId');
      if (response.statusCode == 200 && response.data != null) {
        final data = _toMap(response.data);
        final albumData = data['album'] ?? data;
        return AddonAlbum.fromJson(albumData, addonId: id);
      }
    } catch (e) {
      print('[AddonService] Album detail error: $e');
    }
    return null;
  }

  Future<AddonArtist?> getArtistDetail(String artistId, {String? addonId}) async {
    final id = addonId ?? _activeAddonId;
    if (id == null) return null;
    final manifest = _getManifest(id);
    if (manifest == null) return null;

    if (manifest.addonType == AddonType.user) {
      return _userHandlers[id]?.getArtistDetail(artistId);
    }
    try {
      final response = await _dio.get('${manifest.baseUrl}/artist/$artistId');
      if (response.statusCode == 200 && response.data != null) {
        final data = _toMap(response.data);
        final artistData = data['artist'] ?? data;
        return AddonArtist.fromJson(artistData, addonId: id);
      }
    } catch (e) {
      print('[AddonService] Artist detail error: $e');
    }
    return null;
  }

  Future<AddonPlaylist?> getPlaylistDetail(String playlistId, {String? addonId}) async {
    final id = addonId ?? _activeAddonId;
    if (id == null) return null;
    final manifest = _getManifest(id);
    if (manifest == null) return null;

    if (manifest.addonType == AddonType.user) {
      return _userHandlers[id]?.getPlaylistDetail(playlistId);
    }
    try {
      final response = await _dio.get('${manifest.baseUrl}/playlist/$playlistId');
      if (response.statusCode == 200 && response.data != null) {
        final data = _toMap(response.data);
        final playlistData = data['playlist'] ?? data;
        return AddonPlaylist.fromJson(playlistData, addonId: id);
      }
    } catch (e) {
      print('[AddonService] Playlist detail error: $e');
    }
    return null;
  }


  // ========== Lyrics ==========

  /// Fetch lyrics using the active addon (or a specific one).
  /// Falls back to other addons if the primary one fails.
  Future<String?> getLyrics(String artist, String title,
      {String? addonId, String? album, int? duration}) async {
    // 1. Try LRCLIB first (as it is the new built-in lyrics provider)
    final lrcLibLyrics = await _fetchLyricsFromAddon('net.lrclib', artist, title,
        album: album, duration: duration);
    if (lrcLibLyrics != null && lrcLibLyrics.isNotEmpty) return lrcLibLyrics;

    // 2. Try specified or active addon
    final primaryId = addonId ?? _activeAddonId;
    if (primaryId != null && primaryId != 'net.lrclib') {
      final lyrics = await _fetchLyricsFromAddon(primaryId, artist, title,
          album: album, duration: duration);
      if (lyrics != null && lyrics.isNotEmpty) return lyrics;
    }

    // 3. Fallback: Try all other addons that support lyrics
    for (final addon in _installedAddons) {
      if (addon.id == 'net.lrclib' || addon.id == primaryId) continue;
      if (addon.supportsLyrics) {
        final lyrics = await _fetchLyricsFromAddon(addon.id, artist, title,
            album: album, duration: duration);
        if (lyrics != null && lyrics.isNotEmpty) {
          print('[AddonService] Lyrics fallback: found in ${addon.name}');
          return lyrics;
        }
      }
    }


    return null;
  }

  Future<String?> _fetchLyricsFromAddon(
      String addonId, String artist, String title,
      {String? album, int? duration}) async {
    final handler = _userHandlers[addonId];
    if (handler != null) {
      return handler.getLyrics(artist, title,
          album: album, duration: duration);
    }


    final manifest = _getManifest(addonId);
    if (manifest == null || manifest.baseUrl == null) return null;

    try {
      final response = await _dio.get(
        '${manifest.baseUrl}/lyrics',
        queryParameters: {'artist': artist, 'title': title},
      );
      if (response.data != null && response.data['lyrics'] != null) {
        return response.data['lyrics'].toString();
      }
    } catch (_) {}
    return null;
  }

  // ========== Library (BeatBoss Specific Sync) ==========

  /// Returns true if ANY installed addon supports library sync.
  bool get supportsLibrary => 
      _installedAddons.any((a) => a.supportsLibrary);

  /// Alias for supportsLibrary to match AddonManifest property name
  bool get supportsSync => supportsLibrary;

  /// Find the best addon manifest to use for library operations.
  /// Prioritizes dedicated sync addons (tagged with 'library') over general 
  /// streaming addons (using 'catalog').
  AddonManifest? _getLibraryManifest() {
    // 1. Highest priority: Any addon with the dedicated 'library' resource
    try {
      return _installedAddons.firstWhere((a) => a.supportsSync);
    } catch (_) {}

    // 2. Fallback: The active addon if it supports Catalog (clips/albums)
    final active = activeAddon;
    if (active != null && active.supportsCatalog) {
      return active;
    }

    // 3. Final fallback: First available addon with Catalog support
    try {
      return _installedAddons.firstWhere((a) => a.supportsCatalog);
    } catch (_) {
      return null;
    }
  }

  Future<List<MusicLibrary>> getLibraries() async {
    final manifest = _getLibraryManifest();
    if (manifest == null) return [];

    if (manifest.addonType == AddonType.user) {
      return await _userHandlers[manifest.id]?.getLibraries() ?? [];
    } else {
      return _serverGetLibraries(manifest);
    }
  }

  Future<List<MusicLibrary>> _serverGetLibraries(AddonManifest manifest) async {
    try {
      final response = await _dio.get('${manifest.baseUrl}/libraries');
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data;
        return list.map((l) => MusicLibrary.fromJson(l)).toList();
      }
    } catch (e) {
      print('[AddonService] Server getLibraries error for ${manifest.id}: $e');
    }
    return [];
  }

  Future<List<Track>> getLibraryTracks(String libraryId, {int? limit}) async {
    final manifest = _getLibraryManifest();
    if (manifest == null) return [];

    if (manifest.addonType == AddonType.user) {
      return await _userHandlers[manifest.id]?.getLibraryTracks(libraryId, limit: limit) ?? [];
    } else {
      return _serverGetLibraryTracks(manifest, libraryId, limit: limit);
    }
  }

  Future<List<Track>> _serverGetLibraryTracks(AddonManifest manifest, String libraryId, {int? limit}) async {
    try {
      final response = await _dio.get('${manifest.baseUrl}/libraries/$libraryId');
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data;
        return list.map((t) => Track.fromJson(t)).toList();
      }
    } catch (e) {
      print('[AddonService] Server getLibraryTracks error for ${manifest.id}: $e');
    }
    return [];
  }

  Future<bool> createLibrary(String name) async {
    final manifest = _getLibraryManifest();
    if (manifest == null) return false;

    if (manifest.addonType == AddonType.user) {
      return await _userHandlers[manifest.id]?.createLibrary(name) ?? false;
    } else {
      try {
        final response = await _dio.post(
          '${manifest.baseUrl}/libraries',
          data: {'name': name},
        );
        return response.statusCode == 200 || response.statusCode == 201;
      } catch (e) {
        print('[AddonService] Server createLibrary error for ${manifest.id}: $e');
        return false;
      }
    }
  }

  Future<bool> updateLibrary(String libraryId, {required String name}) async {
    final manifest = _getLibraryManifest();
    if (manifest == null) return false;

    if (manifest.addonType == AddonType.user) {
      return await _userHandlers[manifest.id]?.updateLibrary(libraryId, name: name) ?? false;
    } else {
      try {
        final response = await _dio.post(
          '${manifest.baseUrl}/libraries/$libraryId/update',
          data: {'name': name},
        );
        return response.statusCode == 200;
      } catch (e) {
        print('[AddonService] Server updateLibrary error for ${manifest.id}: $e');
        return false;
      }
    }
  }

  Future<bool> deleteLibrary(String libraryId) async {
    final manifest = _getLibraryManifest();
    if (manifest == null) return false;

    if (manifest.addonType == AddonType.user) {
      return await _userHandlers[manifest.id]?.deleteLibrary(libraryId) ?? false;
    } else {
      try {
        final response = await _dio.delete('${manifest.baseUrl}/libraries/$libraryId');
        return response.statusCode == 200;
      } catch (e) {
        print('[AddonService] Server deleteLibrary error for ${manifest.id}: $e');
        return false;
      }
    }
  }

  Future<bool> addTracksToLibrary(String libraryId, List<Track> tracks) async {
    final manifest = _getLibraryManifest();
    if (manifest == null) return false;

    if (manifest.addonType == AddonType.user) {
      return await _userHandlers[manifest.id]?.addTracksToLibrary(libraryId, tracks) ?? false;
    } else {
      try {
        final response = await _dio.post(
          '${manifest.baseUrl}/libraries/$libraryId/sync',
          data: {'tracks': tracks.map((t) => t.toJson()).toList()},
        );
        return response.statusCode == 200;
      } catch (e) {
        print('[AddonService] Server sync error for ${manifest.id}: $e');
        return false;
      }
    }
  }

  Future<bool> removeTrackFromLibrary(String libraryId, String trackId) async {
    final manifest = _getLibraryManifest();
    if (manifest == null) return false;

    if (manifest.addonType == AddonType.user) {
      return await _userHandlers[manifest.id]?.removeTrackFromLibrary(libraryId, trackId) ?? false;
    } else {
      try {
        final response = await _dio.post(
          '${manifest.baseUrl}/libraries/$libraryId/remove',
          data: {'trackId': trackId},
        );
        return response.statusCode == 200;
      } catch (e) {
        if (e is DioException && e.response?.statusCode == 404) {
          // If 404, the track might not be on the server anyway, consider it "removed" success
          return true;
        }
        print('[AddonService] Server removeTrack error for ${manifest.id}: $e');
        return false;
      }
    }
  }

  void syncFavouritesCloud(Track track, bool isAdding) async {
    try {
      if (isAdding) {
        await addTracksToLibrary('1', [track]);
      } else {
        await removeTrackFromLibrary('1', track.id);
      }
      print('[AddonService] Auto-sync favourite successful: ${track.title} (${isAdding ? 'Added' : 'Removed'})');
    } catch (e) {
      print('[AddonService] Auto-sync favourite failed: $e');
    }
  }

  /// System-protected libraries that cannot be renamed or deleted
  bool isSystemLibrary(String name) {
    final n = name.toLowerCase().trim();
    return n == 'favourites' || n == 'favorites' || n == 'liked songs' || n == 'liked';
  }

  // ========== Helpers ==========

  AddonManifest? _getManifest(String addonId) {
    try {
      return _installedAddons.firstWhere((a) => a.id == addonId);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) return jsonDecode(data);
    return {};
  }

  /// Normalize a URL to a clean base (no trailing slash, strips /manifest.json)
  String _normalizeBaseUrl(String url) {
    var u = url.trim();
    if (u.endsWith('/manifest.json')) {
      u = u.substring(0, u.length - '/manifest.json'.length);
    }
    if (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}

