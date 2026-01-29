import 'package:dio/dio.dart';
import '../models/models.dart';

/// DAB API Service - mirrors Python DabAPI class exactly
class DabApiService {
  static const String _baseUrl = 'https://dabmusic.xyz/api';

  final Dio _dio;
  User? _user;

  User? get user => _user;
  bool get isLoggedIn => _user != null && _user!.token != null;

  DabApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': '*/*',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        )) {
    // Add retry interceptor
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        if (error.response?.statusCode == 503 ||
            error.type == DioExceptionType.connectionTimeout) {
          // Retry once
          try {
            final response = await _dio.fetch(error.requestOptions);
            return handler.resolve(response);
          } catch (e) {
            return handler.next(error);
          }
        }
        return handler.next(error);
      },
    ));
  }

  void setUser(User user) {
    _user = user;
    if (user.token != null) {
      // API uses Cookies, so we set the Cookie header
      _dio.options.headers['Cookie'] = user.token;
      // Fallback for Bearer if mixed usage (rare for this API)
      // _dio.options.headers['Authorization'] = 'Bearer ${user.token}';
    }
  }

  void clearUser() {
    _user = null;
    _dio.options.headers.remove('Cookie');
    _dio.options.headers.remove('Authorization');
  }

  // ========== SEARCH ==========
  Future<SearchResults?> search(String query,
      {int limit = 50, int offset = 0, String type = 'track'}) async {
    try {
      final response = await _dio.get('/search', queryParameters: {
        'q': query,
        'limit': limit,
        'offset':
            offset, // Using offset based on earlier user input, though spec implies page
        'type': type,
      });
      if (response.statusCode == 200) {
        return SearchResults.fromJson(response.data);
      }
    } catch (e) {
      print('[DAB API] Search error: $e');
    }
    return null;
  }

  // ========== STREAM URL ==========
  Future<String?> getStreamUrl(String trackId) async {
    try {
      final response = await _dio.get('/stream',
          queryParameters: {'trackId': trackId, 'quality': '27'});
      if (response.statusCode == 200 && response.data != null) {
        // User observed 'url', Spec says 'streamUrl'. Checking both.
        return response.data['url'] ?? response.data['streamUrl'];
      }
    } catch (e) {
      print('[DAB API] Stream URL error: $e');
    }
    return null;
  }

  // ========== AUTH ==========
  // Login/Signup methods remain as updated in previous steps

  Future<User?> login(String email, String password) async {
    try {
      print('[DAB API] Attempting login for $email...'); // DEBUG
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      print('[DAB API] Login Status: ${response.statusCode}'); // DEBUG

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        print('[DAB API] Login keys: ${data.keys}'); // DEBUG

        // User data is nested in 'user' key
        final userData = data['user'];
        if (userData != null) {
          // Extract session cookie - Robust Search
          String? cookie;
          List<String>? cookies;
          // Try direct lookup
          cookies = response.headers['set-cookie'];

          // Fallback: iterate if not found
          if (cookies == null || cookies.isEmpty) {
            response.headers.map.forEach((key, value) {
              if (key.toLowerCase() == 'set-cookie') {
                cookies = value;
              }
            });
          }

          if (cookies != null && cookies!.isNotEmpty) {
            print('[DAB API] Found Cookies: $cookies'); // DEBUG
            cookie = cookies!.join('; ');
          } else {
            print(
                '[DAB API] WARNING: No set-cookie header found in: ${response.headers.map.keys}'); // DEBUG
          }

          // Inject cookie as token
          if (cookie != null) {
            userData['token'] = cookie;
          } else {
            if (data['token'] != null) userData['token'] = data['token'];
          }

          final user = User.fromJson(userData);
          print('[DAB API] User Parsed. Token: ${user.token}'); // DEBUG

          setUser(user);
          return user;
        } else {
          print('[DAB API] Error: user key missing');
        }
      }
    } catch (e) {
      print('[DAB API] Login error: $e');
    }
    return null;
  }

  Future<User?> signup(String email, String password, String username) async {
    try {
      final response = await _dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'username': username,
        'inviteCode': '', // Spec requires inviteCode
      });
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Auto-login after signup
        return await login(email, password);
      }
    } catch (e) {
      print('[DAB API] Signup error: $e');
    }
    return null;
  }

  Future<User?> autoLogin(String token) async {
    try {
      _dio.options.headers['Authorization'] = 'Bearer $token'; // Fallback
      _dio.options.headers['Cookie'] = token; // Primary

      final response = await _dio.get('/auth/me');
      if (response.statusCode == 200 && response.data != null) {
        final userData =
            response.data; // Spec says CurrentUserResponse { user: ... } ??
        // Actually spec says CurrentUserResponse { user: ... }
        // Let's check response structure:
        Map<String, dynamic> userMap;
        if (userData['user'] != null) {
          userMap = userData['user'];
        } else {
          // Fallback if top level
          userMap = userData;
        }

        userMap['token'] = token;
        final user = User.fromJson(userMap);
        _user = user;
        return user;
      }
    } catch (e) {
      print('[DAB API] Auto-login error: $e');
      _dio.options.headers.remove('Authorization');
      _dio.options.headers.remove('Cookie');
    }
    return null;
  }

  // ========== LIBRARIES ==========
  Future<List<MusicLibrary>> getLibraries() async {
    try {
      final response = await _dio.get('/libraries');
      if (response.statusCode == 200 && response.data != null) {
        // Spec: LibrariesResponse { libraries: [...] }
        final List<dynamic> list = response.data['libraries'] ?? [];
        return list.map((l) => MusicLibrary.fromJson(l)).toList();
      }
    } catch (e) {
      print('[DAB API] Get libraries error: $e');
    }
    return [];
  }

  Future<List<Track>> getLibraryTracks(String libraryId,
      {int page = 1, int limit = 50}) async {
    try {
      final response =
          await _dio.get('/libraries/$libraryId', queryParameters: {
        'page': page,
        'limit': limit,
      });
      if (response.statusCode == 200 && response.data != null) {
        // Spec: LibraryDetailsResponse { library: { ... tracks: [...] } }
        if (response.data['library'] != null &&
            response.data['library']['tracks'] != null) {
          final List<dynamic> list = response.data['library']['tracks'];
          return list.map((t) => Track.fromJson(t)).toList();
        }
      }
    } catch (e) {
      print('[DAB API] Get library tracks error: $e');
    }
    return [];
  }

  Future<MusicLibrary?> createLibrary(String name) async {
    try {
      // Spec: CreateLibraryRequest { name, description, isPublic }
      final response = await _dio.post('/libraries', data: {
        'name': name,
        'description': 'Created via Flutter App',
        'isPublic': false
      });
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Spec: CreateLibraryResponse { message, library }
        return MusicLibrary.fromJson(response.data['library']);
      }
    } catch (e) {
      print('[DAB API] Create library error: $e');
    }
    return null;
  }

  Future<bool> updateLibrary(String libraryId, {String? name}) async {
    try {
      final response =
          await _dio.patch('/libraries/$libraryId', data: {'name': name});
      return response.statusCode == 200;
    } catch (e) {
      print('[DAB API] Update library error: $e');
      return false;
    }
  }

  Future<bool> deleteLibrary(String libraryId) async {
    try {
      final response = await _dio.delete('/libraries/$libraryId');
      return response.statusCode == 200;
    } catch (e) {
      print('[DAB API] Delete library error: $e');
      return false;
    }
  }

  Future<bool> addTrackToLibrary(String libraryId, Track track) async {
    try {
      // Spec: AddTrackToLibraryRequest { track: Track }
      final response = await _dio.post('/libraries/$libraryId/tracks',
          data: {'track': track.toJson()});
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('[DAB API] Add track to library error: $e');
      return false;
    }
  }

  Future<bool> removeTrackFromLibrary(String libraryId, String trackId) async {
    try {
      // Spec: DELETE /libraries/{id}/tracks/{trackId}
      final response =
          await _dio.delete('/libraries/$libraryId/tracks/$trackId');
      return response.statusCode == 200;
    } catch (e) {
      print('[DAB API] Remove track from library error: $e');
      return false;
    }
  }

  // ========== FAVORITES ==========
  Future<List<Track>> getFavorites() async {
    try {
      final response = await _dio.get('/favorites');
      if (response.statusCode == 200 && response.data != null) {
        // Spec: FavoritesResponse { favorites: [...] }
        final List<dynamic> list = response.data['favorites'] ?? [];
        return list.map((t) => Track.fromJson(t)).toList();
      }
    } catch (e) {
      print('[DAB API] Get favorites error: $e');
    }
    return [];
  }

  Future<bool> addFavorite(Track track) async {
    try {
      // Spec: AddToFavoritesRequest { track: Track }
      final response =
          await _dio.post('/favorites', data: {'track': track.toJson()});
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('[DAB API] Add favorite error: $e');
      return false;
    }
  }

  Future<bool> removeFavorite(String trackId) async {
    try {
      // Spec: DELETE /favorites?trackId=...
      final response = await _dio
          .delete('/favorites', queryParameters: {'trackId': trackId});
      return response.statusCode == 200;
    } catch (e) {
      print('[DAB API] Remove favorite error: $e');
      return false;
    }
  }

  // ========== ALBUMS ==========
  Future<List<Track>> getAlbumTracks(String albumId) async {
    try {
      // Spec: GET /album?albumId=... OR GET /album/{id}
      // Assuming existing call was getting details.
      // Spec says /album?albumId=... returns AlbumResponse { album: ... }
      // The Album object has a 'tracks' array.
      final response =
          await _dio.get('/album', queryParameters: {'albumId': albumId});
      if (response.statusCode == 200 && response.data != null) {
        if (response.data['album'] != null &&
            response.data['album']['tracks'] != null) {
          final List<dynamic> list = response.data['album']['tracks'];
          return list.map((t) => Track.fromJson(t)).toList();
        }
      }
    } catch (e) {
      print('[DAB API] Get album tracks error: $e');
    }
    return [];
  }

  // ========== LYRICS ==========
  Future<String?> getLyrics(String artist, String title) async {
    try {
      final response = await _dio.get('/lyrics', queryParameters: {
        'artist': artist,
        'title': title,
      });
      if (response.statusCode == 200 && response.data != null) {
        // Spec: LyricsResponse { lyrics: ..., unsynced: ... }
        return response.data['lyrics'];
      }
    } catch (e) {
      print('[DAB API] Get lyrics error: $e');
    }
    return null;
  }
}
