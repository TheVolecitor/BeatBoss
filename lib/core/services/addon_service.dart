import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../models/addon_models.dart';
import '../models/models.dart';
import '../recommendations/rec_models.dart';
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

  // Broadcast stream of addon notices (manifest, stream 503/429, etc.)
  final StreamController<({AddonManifest addon, AddonNotice notice})>
      _noticeController = StreamController.broadcast();
  Stream<({AddonManifest addon, AddonNotice notice})> get onNotice =>
      _noticeController.stream;

  final Map<String, DateTime> _recentNotices = {};

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 1),
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  ));

  AddonService({required SettingsService settingsService})
      : _settings = settingsService;

  // ========== Getters ==========

  List<AddonManifest> get installedAddons => List.unmodifiable(_installedAddons);

  bool isAddonEnabled(String addonId) => _settings.isAddonEnabled(addonId);

  Future<void> setAddonEnabled(String addonId, bool enabled) async {
    await _settings.setAddonEnabled(addonId, enabled);
    if (!enabled && _activeAddonId == addonId) {
      final fallback = _installedAddons
          .where((a) => a.id != addonId && isAddonEnabled(a.id) && a.supportsSearch)
          .firstOrNull;
      _activeAddonId = fallback?.id;
      if (_activeAddonId != null) {
        await _settings.setActiveAddonId(_activeAddonId!);
      }
    } else if (enabled && _activeAddonId == null) {
      final target = _getManifest(addonId);
      if (target != null && target.supportsSearch) {
        _activeAddonId = addonId;
        await _settings.setActiveAddonId(addonId);
      }
    }
    notifyListeners();
  }

  String? get activeAddonId => _activeAddonId;

  AddonManifest? get activeAddon {
    if (_activeAddonId != null) {
      final match = _installedAddons
          .where((a) => a.id == _activeAddonId && isAddonEnabled(a.id))
          .firstOrNull;
      if (match != null) return match;
    }
    return _installedAddons.where((a) => isAddonEnabled(a.id)).firstOrNull;
  }

  bool get hasSearchCapableAddon =>
      _installedAddons.any((a) => isAddonEnabled(a.id) && a.supportsSearch);

  String displayNameFor(AddonManifest manifest) =>
      _settings.getAddonDisplayName(manifest.id) ?? manifest.name;

  List<AddonManifest> getAddonsForResource(String resource) {
    return _installedAddons.where((a) => a.resources.contains(resource)).toList();
  }

  /// Query parameters for declared addon settings (sent verbatim on every request).
  Map<String, dynamic> _settingsQuery(AddonManifest manifest) {
    if (manifest.settings.isEmpty) return const {};
    final stored = _settings.getAddonSettings(manifest.id);
    final params = <String, dynamic>{};
    for (final field in manifest.settings) {
      final val = field.perNetwork
          ? (stored['${field.key}_wifi'] ?? stored[field.key] ?? field.defaultValue)
          : (stored[field.key] ?? field.defaultValue);
      if (val != null) params[field.key] = val.toString();
    }
    return params;
  }

  void _emitNoticeFromData(AddonManifest manifest, dynamic rawData,
      {bool isManifest = false}) {
    if (!manifest.supportsNotifications ||
        !_settings.getAddonNotificationsEnabled(manifest.id)) {
      return;
    }
    final map = _toMap(rawData);
    if (map['notice'] is! Map) return;
    final notice = AddonNotice.fromJson(
        Map<String, dynamic>.from(map['notice'] as Map));
    if (notice.message.isEmpty) return;

    if (isManifest && notice.id != null) {
      if (_settings.hasSeenAddonNoticeId(manifest.id, notice.id!)) return;
      _settings.markAddonNoticeIdSeen(manifest.id, notice.id!);
    } else {
      final dedupeKey = '${manifest.id}:${notice.message}';
      final last = _recentNotices[dedupeKey];
      final now = DateTime.now();
      if (last != null && now.difference(last) < const Duration(seconds: 60)) {
        return;
      }
      _recentNotices[dedupeKey] = now;
    }
    _noticeController.add((addon: manifest, notice: notice));
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

  Future<void> reorderAddons(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _installedAddons.length) return;
    if (newIndex < 0 || newIndex > _installedAddons.length) return;
    
    final item = _installedAddons.removeAt(oldIndex);
    _installedAddons.insert(newIndex, item);
    
    await _settings.saveAddons(_installedAddons);
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

    Map<String, dynamic> data = _toMap(response.data);
    if (data.isEmpty) {
      throw Exception('Failed to parse manifest: Invalid format or empty response');
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
    _emitNoticeFromData(manifest, data, isManifest: true);

    // Auto-activate if first search-capable addon
    if (_activeAddonId == null && manifest.supportsSearch) {
      _activeAddonId = manifest.id;
      await _settings.setActiveAddonId(manifest.id);
    }

    notifyListeners();
    return manifest;
  }

  /// Re-fetch and reinstall an existing addon's manifest in place (preserving
  /// its priority order and user settings).
  Future<AddonManifest> reloadAddon(String addonId) async {
    final index = _installedAddons.indexWhere((a) => a.id == addonId);
    if (index < 0) throw Exception('Addon not found');
    final existing = _installedAddons[index];

    if (existing.addonType == AddonType.user) {
      final handler = _userHandlers[addonId];
      if (handler == null) return existing;
      final fresh = handler.manifest;
      _installedAddons[index] = fresh;
      await _settings.saveAddons(_installedAddons);
      notifyListeners();
      return fresh;
    }

    final baseUrl = existing.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Addon has no URL to reload');
    }

    final manifestUrl = '$baseUrl/manifest.json';
    final response = await _dio.get(manifestUrl);
    if (response.statusCode != 200 || response.data == null) {
      throw Exception('Failed to fetch manifest from $manifestUrl');
    }

    final data = _toMap(response.data);
    if (data.isEmpty) {
      throw Exception('Failed to parse manifest: Invalid format or empty response');
    }

    final fresh = AddonManifest.fromEclipseJson(data, baseUrl: baseUrl);
    _installedAddons[index] = fresh;
    await _settings.saveAddons(_installedAddons);
    _emitNoticeFromData(fresh, data, isManifest: true);
    notifyListeners();
    return fresh;
  }

  /// Preview a manifest from a URL without installing it.
  Future<AddonManifest> previewManifest(String url) async {
    final baseUrl = _normalizeBaseUrl(url);
    final manifestUrl = '$baseUrl/manifest.json';

    final response = await _dio.get(manifestUrl);
    if (response.statusCode != 200 || response.data == null) {
      throw Exception('Could not reach $manifestUrl');
    }

    Map<String, dynamic> data = _toMap(response.data);
    if (data.isEmpty) {
      throw Exception('Could not parse manifest data');
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
    if (!isAddonEnabled(manifest.id)) return null;

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
          ..._settingsQuery(manifest),
          'q': query,
          if (limit != null) 'limit': limit,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        _emitNoticeFromData(manifest, response.data);
        final data = _toMap(response.data);
        if (data.isNotEmpty) {
          return AddonSearchResult.fromJson(data, addonId: manifest.id);
        }
      }
    } on DioException catch (e) {
      if (e.response?.data != null) {
        _emitNoticeFromData(manifest, e.response!.data);
      }
      print('[AddonService] Server search error for ${manifest.id}: $e');
    } catch (e) {
      print('[AddonService] Server search error for ${manifest.id}: $e');
    }
    return null;
  }

  // ========== ISRC & Exact Resolve ==========

  bool supportsIsrcFor([String? addonId]) {
    final id = addonId ?? _activeAddonId;
    if (id == null) return false;
    final manifest = _getManifest(id);
    return manifest != null &&
        isAddonEnabled(manifest.id) &&
        manifest.addonType == AddonType.server &&
        manifest.supportsIsrc;
  }

  bool supportsResolveFor([String? addonId]) {
    final id = addonId ?? _activeAddonId;
    if (id == null) return false;
    final manifest = _getManifest(id);
    return manifest != null &&
        isAddonEnabled(manifest.id) &&
        manifest.addonType == AddonType.server &&
        manifest.supportsResolve;
  }

  /// Calls GET /resolve-isrc?isrc={isrc} on [addonId] (or active addon).
  /// Returns the addon trackId if found, or null if unsupported / not found.
  Future<String?> resolveIsrc(String isrc, {String? addonId}) async {
    final clean = isrc.trim();
    if (clean.isEmpty) return null;
    final id = addonId ?? _activeAddonId;
    if (id == null) return null;
    final manifest = _getManifest(id);
    if (manifest == null ||
        !isAddonEnabled(manifest.id) ||
        manifest.addonType != AddonType.server ||
        !manifest.supportsIsrc) {
      return null;
    }
    try {
      final response = await _dio.get(
        '${manifest.baseUrl}/resolve-isrc',
        queryParameters: {
          ..._settingsQuery(manifest),
          'isrc': clean,
        },
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (response.data != null) _emitNoticeFromData(manifest, response.data);
      if (response.statusCode == 200 && response.data != null) {
        final data = _toMap(response.data);
        final trackId = (data['trackId'] ?? data['id'])?.toString().trim();
        return (trackId != null && trackId.isNotEmpty) ? trackId : null;
      }
    } catch (e) {
      print('[AddonService] resolve-isrc error for ${manifest.id}: $e');
    }
    return null;
  }

  /// Calls GET /resolve on [addonId] (or active addon) if it declares "resolve".
  /// Returns `(handled: true, track: ...)` when the addon implements /resolve
  /// (even when track is null because the addon confirmed it doesn't have it).
  Future<({bool handled, AddonTrack? track})> resolveTrack(
    RecTrack rec, {
    String? addonId,
  }) async {
    final id = addonId ?? _activeAddonId;
    if (id == null) return (handled: false, track: null);
    final manifest = _getManifest(id);
    if (manifest == null ||
        !isAddonEnabled(manifest.id) ||
        manifest.addonType != AddonType.server ||
        !manifest.supportsResolve) {
      return (handled: false, track: null);
    }
    try {
      final response = await _dio.get(
        '${manifest.baseUrl}/resolve',
        queryParameters: {
          ..._settingsQuery(manifest),
          if (rec.isrc != null && rec.isrc!.isNotEmpty) 'isrc': rec.isrc,
          'title': rec.title,
          'artist': rec.artist,
          if (rec.durationMs != null) 'durationMs': rec.durationMs,
        },
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (response.data != null) _emitNoticeFromData(manifest, response.data);
      if (response.statusCode == 200 && response.data != null) {
        final data = _toMap(response.data);
        final item = data['item'];
        if (item is Map) {
          return (
            handled: true,
            track: AddonTrack.fromJson(
              Map<String, dynamic>.from(item),
              addonId: manifest.id,
            ),
          );
        }
        return (handled: true, track: null);
      }
    } catch (e) {
      print('[AddonService] resolve error for ${manifest.id}: $e');
    }
    return (handled: false, track: null);
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
  /// When [isrc] is provided, fallback addons that support ISRC lookup resolve
  /// by ISRC before attempting to stream.
  Future<AddonStreamResult?> getStreamResult(
    String trackId, {
    String? addonId,
    String? isrc,
    String? title,
    String? artist,
  }) async {
    // 1. If explicit addon provided, try it first
    if (addonId != null) {
      final manifest = _getManifest(addonId);
      if (manifest != null && isAddonEnabled(manifest.id) && manifest.supportsStream) {
        final res = await _tryStreamResult(manifest, trackId);
        if (res != null) return res;
      }
    }

    // 2. Otherwise iterate top-to-bottom prioritizing based on reorderable list
    for (final manifest in _installedAddons) {
      if (addonId != null && manifest.id == addonId) continue;
      if (isAddonEnabled(manifest.id) && manifest.supportsStream) {
        var targetId = trackId;
        if (addonId != null) {
          final resolved = await _resolveFallbackTrackId(
            manifest,
            isrc: isrc,
            title: title,
            artist: artist,
          );
          if (resolved == null || resolved.isEmpty) continue;
          targetId = resolved;
        }
        final res = await _tryStreamResult(manifest, targetId);
        if (res != null) return res;
      }
    }

    return null;
  }

  /// Resolves a foreign track onto [manifest] using ISRC -> /resolve -> search,
  /// never reusing another addon's trackId.
  Future<String?> _resolveFallbackTrackId(
    AddonManifest manifest, {
    String? isrc,
    String? title,
    String? artist,
  }) async {
    if (isrc != null && isrc.trim().isNotEmpty && manifest.supportsIsrc) {
      final byIsrc = await resolveIsrc(isrc, addonId: manifest.id);
      if (byIsrc != null && byIsrc.isNotEmpty) return byIsrc;
    }

    final cleanTitle = title?.trim() ?? '';
    if (cleanTitle.isEmpty) return null;

    if (manifest.supportsResolve) {
      final hit = await resolveTrack(
        RecTrack(title: cleanTitle, artist: artist?.trim() ?? '', isrc: isrc),
        addonId: manifest.id,
      );
      if (hit.handled) return hit.track?.id;
    }

    if (manifest.supportsSearch) {
      final q = '${artist?.trim() ?? ''} $cleanTitle'.trim();
      final res = await search(q, addonId: manifest.id, limit: 5);
      if (res != null && res.tracks.isNotEmpty) {
        return res.tracks.first.id;
      }
    }

    return null;
  }

  Future<AddonStreamResult?> _tryStreamResult(AddonManifest manifest, String trackId) async {
    final res = manifest.addonType == AddonType.user
        ? await _userHandlers[manifest.id]?.getStreamResult(trackId)
        : await _serverGetStreamResult(manifest, trackId);
    return res?.withProviderAddon(manifest.id);
  }

  Future<AddonStreamResult?> _serverGetStreamResult(
      AddonManifest manifest, String trackId) async {
    const maxAttempts = 4;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await _dio.get(
          '${manifest.baseUrl}/stream/$trackId',
          queryParameters: _settingsQuery(manifest),
          options: Options(
            validateStatus: (s) =>
                s != null && (s == 200 || s == 503 || (s >= 400 && s < 500)),
          ),
        );
        if (response.data != null) _emitNoticeFromData(manifest, response.data);

        if (response.statusCode == 200 && response.data != null) {
          final data = _toMap(response.data);
          return AddonStreamResult.fromJson(data);
        }
        if (response.statusCode == 503 && attempt < maxAttempts - 1) {
          final retryRaw = response.headers.value('retry-after');
          final retrySecs =
              (int.tryParse(retryRaw ?? '') ?? 5).clamp(1, 30);
          await Future.delayed(Duration(seconds: retrySecs));
          continue;
        }
        return null;
      } catch (e) {
        print('[AddonService] Server stream error for ${manifest.id}/$trackId: $e');
        return null;
      }
    }
    return null;
  }


  // ========== Catalog Endpoints ==========

  /// Fetch catalog (tracks/albums/artists/playlists) to populate the home screen
  Future<AddonSearchResult?> getCatalog({String? addonId}) async {
    for (final manifest in _installedAddons) {
      if (addonId != null && manifest.id != addonId) continue;
      if (!isAddonEnabled(manifest.id)) continue;

      if (manifest.supportsCatalog &&
          manifest.addonType == AddonType.server &&
          manifest.catalogs.isNotEmpty) {
        // Eclipse spec: manifest declares `catalogs` rows -> GET /catalog/{id}?skip=0
        final tracks = <AddonTrack>[];
        final albums = <AddonAlbum>[];
        final artists = <AddonArtist>[];
        final playlists = <AddonPlaylist>[];
        for (final cat in manifest.catalogs) {
          try {
            final response = await _dio.get(
              '${manifest.baseUrl}/catalog/${cat.id}',
              queryParameters: {
                ..._settingsQuery(manifest),
                'skip': 0,
              },
            );
            if (response.statusCode == 200 && response.data != null) {
              _emitNoticeFromData(manifest, response.data);
              final data = _toMap(response.data);
              final items = (data['items'] as List<dynamic>?) ?? const [];
              for (final raw in items.whereType<Map>()) {
                final map = Map<String, dynamic>.from(raw);
                final itemType = map['type']?.toString() ?? cat.type;
                switch (itemType) {
                  case 'album':
                    albums.add(AddonAlbum.fromJson(map, addonId: manifest.id));
                  case 'artist':
                    artists.add(AddonArtist.fromJson(map, addonId: manifest.id));
                  case 'playlist':
                    playlists.add(
                        AddonPlaylist.fromJson(map, addonId: manifest.id));
                  default:
                    tracks.add(AddonTrack.fromJson(map, addonId: manifest.id));
                }
              }
            }
          } catch (e) {
            print('[AddonService] Catalog ${cat.id} error for ${manifest.id}: $e');
          }
        }
        final result = AddonSearchResult(
          tracks: tracks,
          albums: albums,
          artists: artists,
          playlists: playlists,
        );
        if (!result.isEmpty) return result;
      }
    }
    return null;
  }

  Future<AddonAlbum?> getAlbumDetail(String albumId, {String? addonId}) async {
    final id = addonId ?? _activeAddonId;
    if (id == null) return null;
    final manifest = _getManifest(id);
    if (manifest == null) return null;

    if (manifest.addonType == AddonType.user) {
      return _userHandlers[id]?.getAlbumDetail(albumId);
    }
    try {
      final response = await _dio.get(
        '${manifest.baseUrl}/album/$albumId',
        queryParameters: _settingsQuery(manifest),
      );
      if (response.statusCode == 200 && response.data != null) {
        _emitNoticeFromData(manifest, response.data);
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
      final response = await _dio.get(
        '${manifest.baseUrl}/artist/$artistId',
        queryParameters: _settingsQuery(manifest),
      );
      if (response.statusCode == 200 && response.data != null) {
        _emitNoticeFromData(manifest, response.data);
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
      final response = await _dio.get(
        '${manifest.baseUrl}/playlist/$playlistId',
        queryParameters: _settingsQuery(manifest),
      );
      if (response.statusCode == 200 && response.data != null) {
        _emitNoticeFromData(manifest, response.data);
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

  /// Fetch lyrics prioritizing the top-to-bottom order of installed addons.
  Future<String?> getLyrics(String artist, String title,
      {String? addonId, String? album, int? duration, String? trackId}) async {
    final syncedRe = RegExp(r'\[\d+:\d+\.?\d*\]');
    String? plainFallback;

    // 1. If explicit addon provided, try it first (prefer synced; keep plain as fallback).
    if (addonId != null) {
      final lyrics = await _fetchLyricsFromAddon(addonId, artist, title,
          album: album, duration: duration, trackId: trackId);
      if (lyrics != null && lyrics.isNotEmpty) {
        if (syncedRe.hasMatch(lyrics)) return lyrics;
        plainFallback ??= lyrics;
      }
    }

    // 2. Iterate top-to-bottom over installed addons supporting lyrics
    for (final addon in _installedAddons) {
      if (addonId != null && addon.id == addonId) continue;
      if (isAddonEnabled(addon.id) && addon.supportsLyrics) {
        final lyrics = await _fetchLyricsFromAddon(addon.id, artist, title,
            album: album, duration: duration, trackId: trackId);
        if (lyrics != null && lyrics.isNotEmpty) {
          if (syncedRe.hasMatch(lyrics)) return lyrics;
          plainFallback ??= lyrics;
        }
      }
    }

    return plainFallback;
  }

  Future<String?> _fetchLyricsFromAddon(
      String addonId, String artist, String title,
      {String? album, int? duration, String? trackId}) async {
    final handler = _userHandlers[addonId];
    if (handler != null) {
      return handler.getLyrics(artist, title,
          album: album, duration: duration, trackId: trackId);
    }


    final manifest = _getManifest(addonId);
    if (manifest == null || manifest.baseUrl == null) return null;

    try {
      final response = await _dio.get(
        '${manifest.baseUrl}/lyrics',
        queryParameters: {'artist': artist, 'title': title},
      );
      if (response.data != null) {
        final data = _toMap(response.data);
        if (data.containsKey('lyrics')) {
          return data['lyrics'].toString();
        }
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
        if (response.data is List) {
          final List<dynamic> list = response.data;
          return list.map((l) => MusicLibrary.fromJson(l)).toList();
        } else if (response.data is String && response.data.trim().startsWith('[')) {
          try {
            final List<dynamic> list = jsonDecode(response.data);
            return list.map((l) => MusicLibrary.fromJson(l)).toList();
          } catch (_) {}
        }
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
        if (response.data is List) {
          final List<dynamic> list = response.data;
          return list.map((t) => Track.fromJson(t)).toList();
        } else if (response.data is String && response.data.trim().startsWith('[')) {
          try {
            final List<dynamic> list = jsonDecode(response.data);
            return list.map((t) => Track.fromJson(t)).toList();
          } catch (_) {}
        }
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
      final created =
          await _userHandlers[manifest.id]?.createLibrary(name) ?? false;
      if (created) notifyListeners();
      return created;
    } else {
      try {
        final response = await _dio.post(
          '${manifest.baseUrl}/libraries',
          data: {'name': name},
        );
        final created =
            response.statusCode == 200 || response.statusCode == 201;
        if (created) notifyListeners();
        return created;
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
    try {
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String && data.trim().startsWith('{')) {
        return jsonDecode(data);
      }
    } catch (e) {
      print('[AddonService] JSON decode error: $e');
    }
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

