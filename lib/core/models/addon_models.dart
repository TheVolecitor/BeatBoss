import 'models.dart';

/// Addon type: 'server' (Eclipse-spec HTTP server) or 'user' (device-side handler)
enum AddonType { server, user }

/// What an addon is capable of providing
/// Matches Eclipse spec resource names
class AddonResource {
  static const String search = 'search';
  static const String stream = 'stream';
  static const String catalog = 'catalog'; // /catalog/{id} and /album, /artist, /playlist
  static const String isrc = 'isrc'; // /resolve-isrc?isrc=...
  static const String resolve = 'resolve'; // /resolve?isrc=...&title=...&artist=...
  static const String settings = 'settings'; // manifest settings array
  static const String notifications = 'notifications'; // JSON notice object
  static const String library = 'library'; // BeatBoss/DAB Sync endpoints
  static const String lyrics = 'lyrics'; // BeatBoss-specific, user addons only
}

/// Content type controls which player UI Eclipse / BeatBoss uses
enum AddonContentType { music, audiobook, podcast }

/// A setting field declared in an addon's manifest `settings` array.
class AddonSettingOption {
  final String value;
  final String label;

  const AddonSettingOption({required this.value, required this.label});

  Map<String, dynamic> toJson() => {'value': value, 'label': label};

  factory AddonSettingOption.fromJson(Map<String, dynamic> json) =>
      AddonSettingOption(
        value: json['value']?.toString() ?? '',
        label: json['label']?.toString() ?? json['value']?.toString() ?? '',
      );
}

class AddonSettingField {
  final String key;
  final String type; // select, toggle, text, number
  final String label;
  final String? help;
  final dynamic defaultValue;
  final bool perNetwork;
  final List<AddonSettingOption> options;
  final int? maxLength;
  final String? placeholder;
  final num? min;
  final num? max;
  final num? step;

  const AddonSettingField({
    required this.key,
    required this.type,
    required this.label,
    this.help,
    this.defaultValue,
    this.perNetwork = false,
    this.options = const [],
    this.maxLength,
    this.placeholder,
    this.min,
    this.max,
    this.step,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type,
        'label': label,
        if (help != null) 'help': help,
        if (defaultValue != null) 'default': defaultValue,
        if (perNetwork) 'perNetwork': perNetwork,
        if (options.isNotEmpty) 'options': options.map((o) => o.toJson()).toList(),
        if (maxLength != null) 'maxLength': maxLength,
        if (placeholder != null) 'placeholder': placeholder,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (step != null) 'step': step,
      };

  factory AddonSettingField.fromJson(Map<String, dynamic> json) =>
      AddonSettingField(
        key: json['key']?.toString() ?? '',
        type: json['type']?.toString() ?? 'text',
        label: json['label']?.toString() ?? json['key']?.toString() ?? '',
        help: json['help']?.toString(),
        defaultValue: json['default'],
        perNetwork: json['perNetwork'] == true,
        options: (json['options'] as List<dynamic>?)
                ?.map((o) => AddonSettingOption.fromJson(
                    Map<String, dynamic>.from(o as Map)))
                .toList() ??
            const [],
        maxLength: (json['maxLength'] as num?)?.toInt(),
        placeholder: json['placeholder']?.toString(),
        min: json['min'] as num?,
        max: json['max'] as num?,
        step: json['step'] as num?,
      );
}

/// A catalog row declared in an addon's manifest `catalogs` array.
class AddonCatalogDef {
  final String id;
  final String type; // track, album, artist, playlist
  final String name;

  const AddonCatalogDef({
    required this.id,
    required this.type,
    required this.name,
  });

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'name': name};

  factory AddonCatalogDef.fromJson(Map<String, dynamic> json) =>
      AddonCatalogDef(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'track',
        name: json['name']?.toString() ?? json['id']?.toString() ?? '',
      );
}

/// Notice payload returned in any addon JSON response.
class AddonNotice {
  final String message;
  final String? title;
  final String level; // info, success, warning, error
  final String? id;
  final double? progress; // 0..1
  final int durationSeconds; // 2..10

  const AddonNotice({
    required this.message,
    this.title,
    this.level = 'info',
    this.id,
    this.progress,
    this.durationSeconds = 4,
  });

  factory AddonNotice.fromJson(Map<String, dynamic> json) {
    final rawLevel = json['level']?.toString().toLowerCase() ?? 'info';
    final level = const {'info', 'success', 'warning', 'error'}.contains(rawLevel)
        ? rawLevel
        : 'info';
    final defaultDur = (level == 'warning' || level == 'error') ? 6 : 4;
    final rawDur = (json['duration'] as num?)?.toInt() ?? defaultDur;
    final rawMsg = (json['message']?.toString() ?? '').replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final rawTitle = json['title']?.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return AddonNotice(
      message: rawMsg.length > 120 ? rawMsg.substring(0, 120) : rawMsg,
      title: rawTitle == null || rawTitle.isEmpty
          ? null
          : (rawTitle.length > 40 ? rawTitle.substring(0, 40) : rawTitle),
      level: level,
      id: json['id']?.toString(),
      progress: (json['progress'] as num?)?.toDouble().clamp(0.0, 1.0),
      durationSeconds: rawDur.clamp(2, 10),
    );
  }
}

/// Audiobook chapter from GET /stream/{id}.
class AddonChapter {
  final String title;
  final double startTime; // seconds

  const AddonChapter({required this.title, required this.startTime});

  factory AddonChapter.fromJson(Map<String, dynamic> json) => AddonChapter(
        title: json['title']?.toString() ?? '',
        startTime: (json['startTime'] as num?)?.toDouble() ?? 0.0,
      );
}

class AddonVideoRendition {
  final String url;
  final int? height;
  final String? mimeType;

  const AddonVideoRendition({
    required this.url,
    this.height,
    this.mimeType,
  });

  factory AddonVideoRendition.fromJson(Map<String, dynamic> json) =>
      AddonVideoRendition(
        url: json['url']?.toString() ?? '',
        height: (json['height'] as num?)?.toInt(),
        mimeType: json['mimeType']?.toString(),
      );
}

/// Optional video stream attached to a track's /stream/{id} reply.
class AddonVideo {
  final String? url;
  final String? mimeType;
  final bool muxed;
  final int? width;
  final int? height;
  final bool independent;
  final List<AddonVideoRendition> renditions;

  const AddonVideo({
    this.url,
    this.mimeType,
    this.muxed = true,
    this.width,
    this.height,
    this.independent = false,
    this.renditions = const [],
  });

  String? bestUrl({int maxHeight = 1080}) {
    if (renditions.isNotEmpty) {
      final valid = renditions.where((r) => r.url.isNotEmpty).toList()
        ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
      if (valid.isNotEmpty) {
        final under = valid.where((r) => (r.height ?? 0) <= maxHeight);
        if (under.isNotEmpty) return under.first.url;
        return valid.last.url;
      }
    }
    return (url != null && url!.isNotEmpty) ? url : null;
  }

  factory AddonVideo.fromJson(Map<String, dynamic> json) => AddonVideo(
        url: json['url']?.toString(),
        mimeType: json['mimeType']?.toString(),
        muxed: json['muxed'] != false,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        independent: json['independent'] == true,
        renditions: (json['renditions'] as List<dynamic>?)
                ?.map((r) => AddonVideoRendition.fromJson(
                    Map<String, dynamic>.from(r as Map)))
                .toList() ??
            const [],
      );
}

/// The manifest describes an addon — stored locally after install.
/// For server addons this is fetched from GET /manifest.json.
/// For user addons (like the built-in DAB addon) it is hardcoded in the handler.
class AddonManifest {
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? icon; // URL to square icon image
  final List<String> resources; // e.g. ['search', 'stream', 'catalog']
  final List<String> types; // e.g. ['track', 'album', 'artist', 'playlist']
  final AddonContentType contentType;
  final AddonType addonType;
  final String? baseUrl; // Required for server addons; null for user addons
  final DateTime installedAt;
  final bool isBuiltIn;
  final List<AddonSettingField> settings;
  final List<AddonCatalogDef> catalogs;

  AddonManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.icon,
    required this.resources,
    this.types = const ['track'],
    this.contentType = AddonContentType.music,
    required this.addonType,
    this.baseUrl,
    required this.installedAt,
    this.isBuiltIn = false,
    this.settings = const [],
    this.catalogs = const [],
  });

  bool get supportsSearch => resources.contains(AddonResource.search);
  bool get supportsStream => resources.contains(AddonResource.stream);
  bool get supportsCatalog => resources.contains(AddonResource.catalog);
  bool get supportsIsrc => resources.contains(AddonResource.isrc);
  bool get supportsResolve => resources.contains(AddonResource.resolve);
  bool get supportsSettings =>
      resources.contains(AddonResource.settings) || settings.isNotEmpty;
  bool get supportsNotifications =>
      resources.contains(AddonResource.notifications);

  /// sync / cloud library support — strictly looks for 'library' tag.
  bool get supportsLibrary => resources.contains(AddonResource.library);

  /// dedicated sync support — strictly looks for the 'library' tag
  bool get supportsSync => resources.contains(AddonResource.library);

  bool get supportsLyrics => resources.contains(AddonResource.lyrics);

  String get addonTypeLabel {
    if (isBuiltIn) return 'BUILT-IN';
    switch (addonType) {
      case AddonType.server:
        return 'SERVER';
      case AddonType.user:
        return 'USER';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'icon': icon,
        'resources': resources,
        'types': types,
        'contentType': contentType.name,
        'addonType': addonType.name,
        'baseUrl': baseUrl,
        'installedAt': installedAt.toIso8601String(),
        'isBuiltIn': isBuiltIn,
        if (settings.isNotEmpty)
          'settings': settings.map((s) => s.toJson()).toList(),
        if (catalogs.isNotEmpty)
          'catalogs': catalogs.map((c) => c.toJson()).toList(),
      };

  factory AddonManifest.fromJson(Map<String, dynamic> json) {
    return AddonManifest(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Addon',
      version: json['version'] ?? '0.0.0',
      description: json['description'],
      icon: json['icon'],
      resources: List<String>.from(json['resources'] ?? []),
      types: List<String>.from(json['types'] ?? ['track']),
      contentType: _parseContentType(json['contentType']),
      addonType: json['addonType'] == 'server' ? AddonType.server : AddonType.user,
      baseUrl: json['baseUrl'],
      installedAt: json['installedAt'] != null
          ? DateTime.tryParse(json['installedAt']) ?? DateTime.now()
          : DateTime.now(),
      isBuiltIn: json['isBuiltIn'] ?? false,
      settings: _parseSettings(json['settings']),
      catalogs: _parseCatalogs(json['catalogs']),
    );
  }

  /// Parse manifest from a raw Eclipse-spec /manifest.json response.
  /// The caller provides the baseUrl (from where the manifest was fetched)
  /// and whether to treat this as a server or user addon.
  factory AddonManifest.fromEclipseJson(
    Map<String, dynamic> json, {
    required String baseUrl,
    AddonType addonType = AddonType.server,
  }) {
    return AddonManifest(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Addon',
      version: json['version'] ?? '0.0.0',
      description: json['description'],
      icon: json['icon'],
      resources: List<String>.from(json['resources'] ?? []),
      types: List<String>.from(json['types'] ?? ['track']),
      contentType: _parseContentType(json['contentType']),
      addonType: addonType,
      baseUrl: baseUrl,
      installedAt: DateTime.now(),
      isBuiltIn: false,
      settings: _parseSettings(json['settings']),
      catalogs: _parseCatalogs(json['catalogs']),
    );
  }

  static List<AddonSettingField> _parseSettings(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((s) => AddonSettingField.fromJson(Map<String, dynamic>.from(s)))
        .where((s) => s.key.isNotEmpty)
        .toList();
  }

  static List<AddonCatalogDef> _parseCatalogs(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((c) => AddonCatalogDef.fromJson(Map<String, dynamic>.from(c)))
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  static AddonContentType _parseContentType(dynamic value) {
    switch (value) {
      case 'audiobook':
        return AddonContentType.audiobook;
      case 'podcast':
        return AddonContentType.podcast;
      default:
        return AddonContentType.music;
    }
  }
}

// ---------------------------------------------------------------------------
// Search result models — matches Eclipse Music spec + DAB response fields
// ---------------------------------------------------------------------------

/// A track result from any addon
class AddonTrack {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final int? duration; // seconds
  final String? artworkURL;
  final String? isrc;
  final String? format; // mp3, flac, aac, m4a
  final String? streamURL; // optional — if present, skip /stream call
  final String? artistId;
  final String addonId; // which addon this track belongs to
  final String? infoText;
  final bool? explicit;
  final bool? hiRes;

  AddonTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.artworkURL,
    this.isrc,
    this.format,
    this.streamURL,
    this.artistId,
    required this.addonId,
    this.infoText,
    this.explicit,
    this.hiRes,
  });

  factory AddonTrack.fromJson(Map<String, dynamic> json, {required String addonId}) {
    int? durationSec;
    if (json['duration'] is num) {
      durationSec = (json['duration'] as num).round();
    } else if (json['duration'] != null) {
      durationSec = int.tryParse(json['duration'].toString());
    } else if (json['durationMs'] is num) {
      durationSec = ((json['durationMs'] as num) / 1000).round();
    }

    final rawIsrc = json['isrc']?.toString().trim();
    final isrc = (rawIsrc != null && rawIsrc.isNotEmpty) ? rawIsrc : null;

    return AddonTrack(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Unknown Title',
      artist: json['artist'] ?? json['artistName'] ?? 'Unknown Artist',
      album: json['album'] ?? json['albumTitle'],
      duration: durationSec,
      artworkURL: json['artworkURL'] ?? json['albumCover'] ?? json['image'] ?? json['cover'],
      isrc: isrc,
      format: json['format'],
      streamURL: json['streamURL'] ?? json['url'],
      artistId: json['artistId']?.toString() ?? json['artist_id']?.toString(),
      addonId: addonId,
      infoText: json['infoText'] ?? json['infotext'],
      explicit: json['explicit'] as bool?,
      hiRes: json['hiRes'] as bool?,
    );
  }

  // Convert to core Track model for seamless integration across the app
  Track toTrack() {
    return Track(
      id: '${addonId}_$id', // Ensure uniqueness across addons
      title: title,
      artist: artist,
      albumTitle: album,
      albumCover: artworkURL,
      duration: duration,
      audioQuality: hiRes == true ? AudioQuality(isHiRes: true) : null,
      streamURL: streamURL,
      isrc: isrc,
      artistId: artistId,
      addonId: addonId,
      addonTrackId: id,
      infoText: infoText,
    );
  }
}

/// An album result from any addon
class AddonAlbum {
  final String id;
  final String title;
  final String artist;
  final String? artworkURL;
  final int? trackCount;
  final String? year;
  final List<AddonTrack>? tracks; // populated from /album/{id}
  final String addonId;
  final String? infoText;

  AddonAlbum({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkURL,
    this.trackCount,
    this.year,
    this.tracks,
    required this.addonId,
    this.infoText,
  });

  factory AddonAlbum.fromJson(Map<String, dynamic> json, {required String addonId}) {
    return AddonAlbum(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Unknown Album',
      artist: json['artist'] ?? json['artistName'] ?? 'Unknown Artist',
      artworkURL: json['artworkURL'] ?? json['cover'] ?? json['image'],
      trackCount: json['trackCount'] ?? json['numberOfTracks'],
      year: json['year']?.toString(),
      tracks: (json['tracks'] ?? json['songs'] ?? json['songList']) != null
          ? ((json['tracks'] ?? json['songs'] ?? json['songList']) as List<dynamic>)
              .map((t) => AddonTrack.fromJson(t, addonId: addonId))
              .toList()
          : null,
      addonId: addonId,
      infoText: json['infoText'] ?? json['infotext'],
    );
  }
}

/// An artist result from any addon
class AddonArtist {
  final String id;
  final String name;
  final String? artworkURL;
  final List<String>? genres;
  final String? bio;
  final List<AddonTrack>? topTracks;
  final List<AddonAlbum>? albums;
  final String addonId;
  final String? infoText;

  AddonArtist({
    required this.id,
    required this.name,
    this.artworkURL,
    this.genres,
    this.bio,
    this.topTracks,
    this.albums,
    required this.addonId,
    this.infoText,
  });

  factory AddonArtist.fromJson(Map<String, dynamic> json, {required String addonId}) {
    return AddonArtist(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unknown Artist',
      artworkURL: json['artworkURL'] ?? json['image'],
      genres: json['genres'] != null
          ? List<String>.from(json['genres'])
          : null,
      bio: json['bio'],
      topTracks: (json['topTracks'] ?? json['tracks'] ?? json['songList']) != null
          ? ((json['topTracks'] ?? json['tracks'] ?? json['songList']) as List<dynamic>)
              .map((t) => AddonTrack.fromJson(t, addonId: addonId))
              .toList()
          : null,
      albums: json['albums'] != null
          ? (json['albums'] as List<dynamic>)
              .map((a) => AddonAlbum.fromJson(a, addonId: addonId))
              .toList()
          : null,
      addonId: addonId,
      infoText: json['infoText'] ?? json['infotext'],
    );
  }
}

/// A playlist result from any addon
class AddonPlaylist {
  final String id;
  final String title;
  final String? description;
  final String? artworkURL;
  final String? creator;
  final int? trackCount;
  final List<AddonTrack>? tracks; // populated from /playlist/{id}
  final String addonId;
  final String? infoText;

  AddonPlaylist({
    required this.id,
    required this.title,
    this.description,
    this.artworkURL,
    this.creator,
    this.trackCount,
    this.tracks,
    required this.addonId,
    this.infoText,
  });

  factory AddonPlaylist.fromJson(Map<String, dynamic> json, {required String addonId}) {
    return AddonPlaylist(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Unknown Playlist',
      description: json['description'],
      artworkURL: json['artworkURL'] ?? json['image'],
      creator: json['creator'],
      trackCount: json['trackCount'],
      tracks: json['tracks'] != null
          ? (json['tracks'] as List<dynamic>)
              .map((t) => AddonTrack.fromJson(t, addonId: addonId))
              .toList()
          : null,
      addonId: addonId,
      infoText: json['infoText'] ?? json['infotext'],
    );
  }
}

/// Unified search results container — all arrays are optional
class AddonSearchResult {
  final List<AddonTrack> tracks;
  final List<AddonAlbum> albums;
  final List<AddonArtist> artists;
  final List<AddonPlaylist> playlists;

  AddonSearchResult({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  factory AddonSearchResult.fromJson(Map<String, dynamic> json,
      {required String addonId}) {
    return AddonSearchResult(
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((t) => AddonTrack.fromJson(t, addonId: addonId))
              .toList() ??
          [],
      albums: (json['albums'] as List<dynamic>?)
              ?.map((a) => AddonAlbum.fromJson(a, addonId: addonId))
              .toList() ??
          [],
      artists: (json['artists'] as List<dynamic>?)
              ?.map((a) => AddonArtist.fromJson(a, addonId: addonId))
              .toList() ??
          [],
      playlists: (json['playlists'] as List<dynamic>?)
              ?.map((p) => AddonPlaylist.fromJson(p, addonId: addonId))
              .toList() ??
          [],
    );
  }
}

/// Quality tier derived from stream metadata (16/44.1 = Lossless, above = Hi-Res, eac3 = Dolby Atmos).
enum StreamQualityTier { atmos, hiRes, lossless, standard }

/// Result from GET /stream/{id}
class AddonStreamResult {
  final String url;
  final String? format;
  final String? quality;
  final int? expiresAt; // Unix timestamp
  final String? codec; // flac, aac, he-aac, alac, mp3, opus, vorbis, eac3_joc
  final String? container; // flac, mp3, mp4, fmp4, ogg, wav
  final String? manifest; // none, hls, dash
  final bool encrypted;
  final int? sampleRate;
  final int? bitDepth;
  final List<AddonChapter>? chapters;
  final AddonVideo? video;
  final AddonNotice? notice;
  final String? providerAddonId;

  AddonStreamResult({
    required this.url,
    this.format,
    this.quality,
    this.expiresAt,
    this.codec,
    this.container,
    this.manifest,
    this.encrypted = false,
    this.sampleRate,
    this.bitDepth,
    this.chapters,
    this.video,
    this.notice,
    this.providerAddonId,
  });

  AddonStreamResult withProviderAddon(String addonId) => AddonStreamResult(
        url: url,
        format: format,
        quality: quality,
        expiresAt: expiresAt,
        codec: codec,
        container: container,
        manifest: manifest,
        encrypted: encrypted,
        sampleRate: sampleRate,
        bitDepth: bitDepth,
        chapters: chapters,
        video: video,
        notice: notice,
        providerAddonId: addonId,
      );

  StreamQualityTier get qualityTier {
    final c = codec?.toLowerCase() ?? '';
    final f = format?.toLowerCase() ?? '';
    final q = quality?.toLowerCase() ?? '';
    if (c.contains('eac3') || q.contains('atmos')) {
      return StreamQualityTier.atmos;
    }
    if ((bitDepth != null && bitDepth! > 16) ||
        (sampleRate != null && sampleRate! > 44100) ||
        q.contains('hi-res') ||
        q.contains('hires') ||
        q.contains('hi_res') ||
        q.contains('24bit') ||
        q.contains('24-bit')) {
      return StreamQualityTier.hiRes;
    }
    if ((bitDepth == 16 && (sampleRate == null || sampleRate == 44100)) ||
        c == 'flac' ||
        c == 'alac' ||
        f == 'flac' ||
        q == 'lossless') {
      return StreamQualityTier.lossless;
    }
    return StreamQualityTier.standard;
  }

  /// Short badge label for the player bar, or null when the addon gave no info.
  String? get qualityLabel {
    switch (qualityTier) {
      case StreamQualityTier.atmos:
        return 'Spatial Audio';
      case StreamQualityTier.hiRes:
        return 'Hi-Res';
      case StreamQualityTier.lossless:
        return 'Lossless';
      case StreamQualityTier.standard:
        if (quality != null && quality!.trim().isNotEmpty) {
          return quality!.trim();
        }
        if (codec != null && codec!.trim().isNotEmpty) {
          return codec!.trim().toUpperCase();
        }
        if (format != null && format!.trim().isNotEmpty) {
          return format!.trim().toUpperCase();
        }
        return null;
    }
  }

  /// Full technical detail for tooltips (e.g. "24-bit / 96.0 kHz FLAC").
  String? get qualityDetail {
    final parts = <String>[];
    if (bitDepth != null) parts.add('${bitDepth!}-bit');
    if (sampleRate != null) {
      final khz = sampleRate! / 1000.0;
      parts.add('${khz == khz.roundToDouble() ? khz.toInt() : khz.toStringAsFixed(1)} kHz');
    }
    if (codec != null && codec!.isNotEmpty) {
      parts.add(codec!.toUpperCase());
    } else if (format != null && format!.isNotEmpty) {
      parts.add(format!.toUpperCase());
    }
    if (parts.isEmpty && quality != null && quality!.isNotEmpty) {
      return quality;
    }
    return parts.isEmpty ? null : parts.join(' • ');
  }

  factory AddonStreamResult.fromJson(Map<String, dynamic> json) {
    return AddonStreamResult(
      url: json['url'] ?? '',
      format: json['format'],
      quality: json['quality'],
      expiresAt: (json['expiresAt'] as num?)?.toInt(),
      codec: json['codec']?.toString(),
      container: json['container']?.toString(),
      manifest: json['manifest']?.toString(),
      encrypted: json['encrypted'] == true,
      sampleRate: (json['sampleRate'] as num?)?.toInt(),
      bitDepth: (json['bitDepth'] as num?)?.toInt(),
      chapters: (json['chapters'] as List<dynamic>?)
          ?.whereType<Map>()
          .map((c) => AddonChapter.fromJson(Map<String, dynamic>.from(c)))
          .toList(),
      video: json['video'] is Map
          ? AddonVideo.fromJson(Map<String, dynamic>.from(json['video'] as Map))
          : null,
      notice: json['notice'] is Map
          ? AddonNotice.fromJson(
              Map<String, dynamic>.from(json['notice'] as Map))
          : null,
    );
  }
}
