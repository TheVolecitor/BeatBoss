// Source-agnostic recommendation models. A RecommendationProvider returns
// these; the app turns a RecTrack into a playable Track through the addon
// search (see track_resolver.dart).

/// Normalises a string for use in cache keys and matching.
String normalizeKeyPart(String s) => s.toLowerCase().trim();

class RecTrack {
  final String title;
  final String artist;
  final String? album;
  final String? imageUrl;
  final double? match;
  final String? isrc;
  final int? durationMs;

  const RecTrack({
    required this.title,
    required this.artist,
    this.album,
    this.imageUrl,
    this.match,
    this.isrc,
    this.durationMs,
  });

  /// Stable identity used for de-duplication and resolve caching.
  String get key => '${normalizeKeyPart(artist)}|${normalizeKeyPart(title)}';

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'imageUrl': imageUrl,
        'match': match,
        if (isrc != null) 'isrc': isrc,
        if (durationMs != null) 'durationMs': durationMs,
      };

  factory RecTrack.fromJson(Map<String, dynamic> json) => RecTrack(
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        album: json['album']?.toString(),
        imageUrl: json['imageUrl']?.toString(),
        match: (json['match'] as num?)?.toDouble(),
        isrc: (json['isrc'] is String && (json['isrc'] as String).trim().isNotEmpty)
            ? (json['isrc'] as String).trim()
            : null,
        durationMs: (json['durationMs'] as num?)?.toInt(),
      );
}

class RecArtist {
  final String name;
  final String? imageUrl;
  final double? match;

  const RecArtist({required this.name, this.imageUrl, this.match});

  Map<String, dynamic> toJson() => {
        'name': name,
        'imageUrl': imageUrl,
        'match': match,
      };

  factory RecArtist.fromJson(Map<String, dynamic> json) => RecArtist(
        name: json['name']?.toString() ?? '',
        imageUrl: json['imageUrl']?.toString(),
        match: (json['match'] as num?)?.toDouble(),
      );
}

enum ShelfKind { tracks, artists }

class RecShelf {
  final String id;
  final String title;
  final String? subtitle;
  final ShelfKind kind;
  final List<RecTrack> tracks;
  final List<RecArtist> artists;
  final DateTime fetchedAt;

  const RecShelf({
    required this.id,
    required this.title,
    this.subtitle,
    this.kind = ShelfKind.tracks,
    this.tracks = const [],
    this.artists = const [],
    required this.fetchedAt,
  });

  bool get isEmpty => kind == ShelfKind.tracks ? tracks.isEmpty : artists.isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'kind': kind.name,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'artists': artists.map((a) => a.toJson()).toList(),
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      };

  factory RecShelf.fromJson(Map<String, dynamic> json) => RecShelf(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        subtitle: json['subtitle']?.toString(),
        kind: ShelfKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => ShelfKind.tracks,
        ),
        tracks: (json['tracks'] as List? ?? [])
            .map((t) => RecTrack.fromJson(Map<String, dynamic>.from(t as Map)))
            .toList(),
        artists: (json['artists'] as List? ?? [])
            .map((a) => RecArtist.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList(),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['fetchedAt'] as num?)?.toInt() ?? 0,
        ),
      );
}
