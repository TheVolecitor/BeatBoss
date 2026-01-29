/// Track model matching DAB API response structure
class Track {
  final String id;
  final String title;
  final String artist;
  final String? albumTitle;
  final String? albumCover;
  final String? albumId;
  final int? duration; // Seconds
  final AudioQuality? audioQuality;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    this.albumTitle,
    this.albumCover,
    this.albumId,
    this.duration,
    this.audioQuality,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    // Handle both string and int IDs
    final idVal = json['id']?.toString() ?? '';

    return Track(
      id: idVal,
      title: json['title'] ?? 'Unknown Title',
      artist: json['artist'] ?? 'Unknown Artist',
      albumTitle: json['albumTitle'] ?? json['album'],
      albumCover: json['albumCover'] ?? json['image'] ?? json['cover'],
      albumId: json['albumId']?.toString(),
      duration: json['duration'],
      audioQuality: json['audioQuality'] != null
          ? AudioQuality.fromJson(json['audioQuality'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'albumTitle': albumTitle,
      'albumCover': albumCover,
      'albumId': albumId,
      'duration': duration,
      'audioQuality': audioQuality?.toJson(),
    };
  }

  // Helpers for UI which likely expects 'album' and 'image'
  String get displayImage => albumCover ?? '';
  bool get isHiRes => audioQuality?.isHiRes ?? false;
  String? get album => albumTitle;
  String? get image => albumCover;
}

class AudioQuality {
  final bool isHiRes;
  final int? maximumBitDepth;
  final double? maximumSamplingRate;

  AudioQuality({
    this.isHiRes = false,
    this.maximumBitDepth,
    this.maximumSamplingRate,
  });

  factory AudioQuality.fromJson(Map<String, dynamic> json) {
    return AudioQuality(
      isHiRes: json['isHiRes'] ?? false,
      maximumBitDepth: json['maximumBitDepth'],
      maximumSamplingRate: json['maximumSamplingRate']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'isHiRes': isHiRes,
        'maximumBitDepth': maximumBitDepth,
        'maximumSamplingRate': maximumSamplingRate,
      };

  String get displayText =>
      isHiRes && maximumBitDepth != null && maximumSamplingRate != null
          ? '${maximumBitDepth}bit / ${maximumSamplingRate}kHz'
          : '';
}

/// Album model
class Album {
  final String id;
  final String title;
  final String artist;
  final String? cover;
  final int? trackCount;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.cover,
    this.trackCount,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Unknown Album',
      artist: json['artist'] ?? json['artistName'] ?? 'Unknown Artist',
      cover: json['cover'] ?? json['image'],
      trackCount: json['trackCount'] ?? json['numberOfTracks'],
    );
  }
}

/// Library (Collection) model
class MusicLibrary {
  final String id;
  final String name;
  final int? trackCount;

  MusicLibrary({
    required this.id,
    required this.name,
    this.trackCount,
  });

  factory MusicLibrary.fromJson(Map<String, dynamic> json) {
    return MusicLibrary(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unnamed Library',
      trackCount: json['trackCount'],
    );
  }
}

/// Search results model
class SearchResults {
  final List<Track> tracks;
  final List<Album> albums;
  final Pagination? pagination;

  SearchResults({
    this.tracks = const [],
    this.albums = const [],
    this.pagination,
  });

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    return SearchResults(
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((t) => Track.fromJson(t))
              .toList() ??
          [],
      albums: (json['albums'] as List<dynamic>?)
              ?.map((a) => Album.fromJson(a))
              .toList() ??
          [],
      pagination: json['pagination'] != null
          ? Pagination.fromJson(json['pagination'])
          : null,
    );
  }

  bool get isEmpty => tracks.isEmpty && albums.isEmpty;
}

/// Pagination model
class Pagination {
  final int page;
  final int limit;
  final int total;
  final bool hasMore;

  Pagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 20,
      total: json['total'] ?? 0,
      hasMore: json['hasMore'] ?? false,
    );
  }
}

/// User model
class User {
  final int id; // Changed to int per spec
  final String email;
  final String? username;
  final String? token; // Client-side logic only

  User({
    required this.id,
    required this.email,
    this.username,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Handle id safely
    int parsedId = 0;
    if (json['id'] is int) {
      parsedId = json['id'];
    } else if (json['id'] is String) {
      parsedId = int.tryParse(json['id']) ?? 0;
    }

    return User(
      id: parsedId,
      email: json['email'] ?? '',
      username: json['username'],
      token: json['token'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'token': token,
      };
}

/// YouTube playlist item model
class YouTubePlaylistItem {
  final String videoId;
  final String title;
  final String channel;

  YouTubePlaylistItem({
    required this.videoId,
    required this.title,
    required this.channel,
  });
}

/// Lyrics line model
class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine({required this.timestamp, required this.text});
}
