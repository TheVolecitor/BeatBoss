import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/models/models.dart';
import '../../core/services/history_service.dart';
import '../../core/services/last_fm_service.dart';
import '../import/playlist_import_dialog.dart';
import '../downloads/downloads_screen.dart';

/// Home Screen - displays play history and welcome message, or Login if not authenticated
class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const HomeScreen({super.key, this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  // Auth State
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isSignup = false;
  bool _isLoading = false;
  bool _showPassword = false;

  // Recommendations
  List<Track> _recommendations = [];
  bool _loadingRecommendations = false;
  bool _hasInitialFetch = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Listen for auth changes to trigger fetch
    final lastFm = context.read<LastFmService>();
    lastFm.addListener(_onAuthChanged);

    // Initial fetch check
    if (!_hasInitialFetch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchRecommendations();
      });
    }
  }

  @override
  void dispose() {
    context.read<LastFmService>().removeListener(_onAuthChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    final lastFm = context.read<LastFmService>();
    // If authenticated and no recs, fetch them
    if (lastFm.isAuthenticated &&
        _recommendations.isEmpty &&
        !_loadingRecommendations) {
      _fetchRecommendations();
    }
  }

  Future<void> _fetchRecommendations() async {
    final lastFm = context.read<LastFmService>();
    final dabApi = context.read<DabApiService>();

    if (!lastFm.isAuthenticated) {
      if (mounted) setState(() => _recommendations = []);
      return;
    }

    if (mounted) setState(() => _loadingRecommendations = true);

    try {
      final rawRecs = await lastFm.getRecommendations();

      // Parallelize searches
      // Create a list of futures to fetch all simultaneously as requested
      final searchFutures = rawRecs.take(10).map((rec) async {
        final query = "${rec['name']} ${rec['artist']}";
        try {
          final results = await dabApi.search(query, limit: 1);
          if (results != null && results.tracks.isNotEmpty) {
            return results.tracks.first;
          }
        } catch (e) {
          print('Rec search error: $e');
        }
        return null;
      });

      final results = await Future.wait(searchFutures);
      final resolvedTracks = results.whereType<Track>().toList();

      if (mounted) {
        setState(() {
          _recommendations = resolvedTracks;
          _loadingRecommendations = false;
          _hasInitialFetch = true;
        });
      }
    } catch (e) {
      print('Error fetching recommendations: $e');
      if (mounted) setState(() => _loadingRecommendations = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final settings = context.watch<SettingsService>();
    final api = context.watch<DabApiService>(); // Watch for auth changes
    final isDark = settings.isDarkMode;

    // Responsive layout check
    final isMobile = MediaQuery.of(context).size.width < 768;

    if (!api.isLoggedIn) {
      // Check if we have saved user data but failed to login (likely offline)
      // Or if no user data, show downloads as fallback
      final savedUser = settings.getUser();

      if (savedUser != null) {
        // Check if we are currently trying to auto-login
        if (api.isAutoLoggingIn) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppTheme.primaryGreen,
            ),
          );
        }

        // Saved credentials exist - we are likely offline
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off,
                  size: 64, color: isDark ? Colors.white54 : Colors.black54),
              const SizedBox(height: 20),
              Text(
                'You are offline',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Welcome back, ${savedUser.username}',
                style:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54),
              ),
              const SizedBox(height: 30),

              // Actions
              Wrap(
                spacing: 20,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      // Trigger auto-login retry
                      // We need to access token again or just call init on API?
                      // API autoLogin needs token.
                      if (savedUser.token != null) {
                        api.autoLogin(savedUser.token!);
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Connection'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      // Navigate to downloads (Index 6) - Assuming added or using onNavigate
                      // If onNavigate maps to tabs.
                      // OR we just push DownloadsScreen?
                      // The prompt says "Go to downloads".
                      // If we are in AppShell, we might not have a tab for downloads in the bottom bar...
                      // Wait, we added Downloads to AppShell at index 4?
                      // Let's check AppShell indices.
                      // Home=0, Search=1, Library=2, Favorites=3, Downloads=4, Settings=5
                      widget.onNavigate?.call(4);
                    },
                    icon: const Icon(Icons.offline_pin),
                    label: const Text('Go to Downloads'),
                  ),
                ],
              ),

              const SizedBox(height: 40),
              TextButton(
                onPressed: () async {
                  // Allow signing out to verify credentials again if stuck
                  await settings.clearUser();
                  api.clearUser();
                  // Will rebuild and show login card
                },
                child:
                    const Text('Sign Out', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      } else {
        // No saved user - show Downloads screen directly as fallback
        // But wrapped to look okay
        return const DownloadsScreen();
      }
    }

    return _buildHomeContent(isDark, settings);
  }

  Widget _buildHomeContent(bool isDark, SettingsService settings) {
    final history = context.watch<HistoryService>();
    final playHistory = history.recentlyPlayed;

    // Use user name if available
    final api = context.read<DabApiService>();
    final username = api.user?.username ?? 'User';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          Text(
            'Discover Music',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              Text(
                'Welcome back, ',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black45,
                  fontSize: 18,
                ),
              ),
              Text(
                username,
                style: const TextStyle(
                  color: AppTheme.primaryGreen,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // Play history section (Moved to Top)
          if (playHistory.isNotEmpty) ...[
            Text(
              'Recently Played',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: playHistory.length,
                itemBuilder: (context, index) {
                  return _RecentTrackCard(
                    track: playHistory[index],
                    isDark: isDark,
                    width: 140,
                  );
                },
              ),
            ),
            const SizedBox(height: 30),
          ],

          // Last.FM Connect Prompt (Moved below Recent Played)
          if (!context.watch<LastFmService>().isAuthenticated) ...[
            _buildLastFmConnectCard(context, isDark),
            const SizedBox(height: 30),
          ],

          // Recommendations Section (Always show if authenticated)
          if (context.watch<LastFmService>().isAuthenticated) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recommended for You',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  color: isDark ? Colors.white70 : Colors.black54,
                  tooltip: 'Refresh Recommendations',
                  onPressed:
                      _loadingRecommendations ? null : _fetchRecommendations,
                ),
              ],
            ),
            const SizedBox(height: 15),
            if (_loadingRecommendations)
              SizedBox(
                height: 220,
                child: Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.primaryGreen),
                ),
              )
            else if (_recommendations.isEmpty)
              SizedBox(
                height: 100,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No recommendations found yet.',
                        style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54),
                      ),
                      TextButton(
                        onPressed: _fetchRecommendations,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent:
                      150, // Smaller tiles, closer to "Recently Played" size
                  childAspectRatio:
                      0.65, // More vertical space to avoid overflow
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                ),
                itemCount: _recommendations.length,
                itemBuilder: (context, index) {
                  return _RecentTrackCard(
                    track: _recommendations[index],
                    isDark: isDark,
                    // width is null, so it fills grid cell
                  );
                },
              ),
            const SizedBox(height: 30),
          ],

          // Quick actions
          Text(
            'Quick Actions',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _QuickActionCard(
                icon: Icons.search,
                label: 'Search Music',
                isDark: isDark,
                onTap: () => widget.onNavigate?.call(1), // Switch to Search
              ),
              _QuickActionCard(
                icon: Icons.library_music,
                label: 'Your Library',
                isDark: isDark,
                onTap: () => widget.onNavigate?.call(2), // Switch to Library
              ),
              _QuickActionCard(
                icon: Icons.favorite,
                label: 'Liked Songs',
                isDark: isDark,
                onTap: () => widget.onNavigate?.call(3), // Switch to Liked
              ),
              // Import Button (New)
              _QuickActionCard(
                icon: Icons.download_rounded,
                label: 'Import Playlist',
                isDark: isDark,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => const PlaylistImportDialog(),
                  );
                },
              ),
            ],
          ),

          // Empty state when no history
          if (playHistory.isEmpty) ...[
            const SizedBox(height: 50),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.music_note,
                    size: 80,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Start playing music!',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoginCard(
      bool isDark, DabApiService api, SettingsService settings, bool isMobile) {
    return Container(
      width: isMobile ? double.infinity : 400,
      padding: const EdgeInsets.all(30),
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white, // Darker card on dark bg
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isSignup ? Icons.person_add : Icons.login,
              size: 40,
              color: AppTheme.primaryGreen,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isSignup ? 'Create Account' : 'Welcome Back',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),

          // Fields
          if (_isSignup) ...[
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.person_outline),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 15),
          ],

          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: const Icon(Icons.email_outlined),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _passwordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),

          const SizedBox(height: 30),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : () => _submit(api, settings),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2))
                  : Text(
                      _isSignup ? 'Sign Up' : 'Sign In',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 20),

          // Toggle
          TextButton(
            onPressed: () {
              setState(() {
                _isSignup = !_isSignup;
                _error = null; // Clear errors
              });
            },
            child: Text.rich(
              TextSpan(
                text: _isSignup
                    ? 'Already have an account? '
                    : "Don't have an account? ",
                style:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                children: [
                  TextSpan(
                    text: _isSignup ? 'Sign In' : 'Sign Up',
                    style: const TextStyle(
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  String? _error;

  Future<void> _submit(DabApiService api, SettingsService settings) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }

    if (_isSignup && username.isEmpty) {
      setState(() => _error = 'Please enter a username');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      User? user;
      if (_isSignup) {
        user = await api.signup(email, password, username);
      } else {
        user = await api.login(email, password);
      }

      if (user != null) {
        // Success
        await settings.saveUser(user);

        // Auto-refresh play history if user has different one?
        // Usually handled by API calls later.

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Welcome, ${user.username}!'),
              backgroundColor: AppTheme.primaryGreen));
        }
      } else {
        setState(() =>
            _error = 'Authentication failed. Please check your credentials.');
      }
    } catch (e) {
      setState(() => _error = 'An error occurred: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildLastFmConnectCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFB90000).withOpacity(0.1), // Subtle red bg
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.music_note, color: Color(0xFFB90000)),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connect Last.fm',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Get personalized recommendations.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              // Navigate to Settings (Index 5)
              widget.onNavigate?.call(5);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.white : Colors.black,
              side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
            ),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class _RecentTrackCard extends StatelessWidget {
  final Track track;
  final bool isDark;
  final double? width;

  const _RecentTrackCard({
    required this.track,
    required this.isDark,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.read<AudioPlayerService>();

    return GestureDetector(
      onTap: () => player.playSingleTrack(track),
      child: Container(
        width: width,
        margin: const EdgeInsets.only(right: 15, bottom: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album art - Scaled to width (Aspect Ratio 1:1)
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: track.displayImage,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (_, __) =>
                            Container(color: AppTheme.darkCard),
                        errorWidget: (_, __, ___) => Container(
                          color: AppTheme.darkCard,
                          child: const Icon(Icons.music_note,
                              size: 40, color: Colors.white30),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Material(
                        color: Colors.transparent,
                        child: PopupMenuButton<String>(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.more_vert,
                                size: 16, color: Colors.white),
                          ),
                          onSelected: (value) {
                            final player = context.read<AudioPlayerService>();
                            switch (value) {
                              case 'queue':
                                player.addToQueue(track);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Added to Queue')),
                                );
                                break;
                              case 'play_next':
                                player.playNext(track);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Will play next')),
                                );
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'queue',
                              child: Row(
                                children: [
                                  Icon(Icons.queue_music, size: 20),
                                  SizedBox(width: 10),
                                  Text('Add to Queue'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'play_next',
                              child: Row(
                                children: [
                                  Icon(Icons.playlist_play, size: 20),
                                  SizedBox(width: 10),
                                  Text('Play Next'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              track.artist,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primaryGreen),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
