import 'rec_models.dart';

enum RecCapability {
  personalStations,
  similarTracks,
  similarArtists,
  artistTopTracks,
  userTopArtists,
  tagTopTracks,
  charts,
}

enum StationKind { recommended, mix, library }

/// A source of music recommendations (Last.fm today; others can be added and
/// picked in Settings later). Methods a provider doesn't support return an
/// empty list; none of them throw.
abstract class RecommendationProvider {
  /// Stable id stored in settings, e.g. `lastfm`.
  String get id;

  /// Name shown in Settings.
  String get displayName;

  Set<RecCapability> get capabilities;

  /// Whether personal features need the user to be logged in.
  bool get needsLogin;
  bool get isLoggedIn;

  Future<List<RecTrack>> station(StationKind kind);
  Future<List<RecTrack>> similarTracks(String artist, String title,
      {int limit = 50});
  Future<List<RecArtist>> similarArtists(String artist, {int limit = 20});
  Future<List<RecTrack>> artistTopTracks(String artist,
      {int limit = 30, int page = 1});
  Future<List<RecArtist>> userTopArtists(
      {String period = '3month', int limit = 10});
  Future<List<RecTrack>> tagTopTracks(String tag,
      {int limit = 30, int page = 1});
  Future<List<RecTrack>> chartTopTracks({int limit = 50, int page = 1});
}
