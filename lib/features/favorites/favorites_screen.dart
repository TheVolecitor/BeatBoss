import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/models.dart';

import '../shared/track_list_tile.dart';
import '../shared/batch_download_dialog.dart';

/// Favorites Screen - display liked songs
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Track> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    // Listen for auth changes
    final api = context.read<DabApiService>();
    api.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    context.read<DabApiService>().removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final api = context.read<DabApiService>();
    if (api.isLoggedIn && _favorites.isEmpty) {
      _loadFavorites();
    } else if (!api.isLoggedIn) {
      if (mounted) setState(() => _favorites = []);
    }
  }

  Future<void> _loadFavorites() async {
    final api = context.read<DabApiService>();
    if (!api.isLoggedIn) return;

    setState(() => _isLoading = true);
    final favs = await api.getFavorites();

    if (!mounted) return;
    setState(() {
      _favorites = favs;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final player = context.read<AudioPlayerService>();
    // Use watch to rebuild on auth changes
    final api = context.watch<DabApiService>();
    final isDark = settings.isDarkMode;

    // Show loading if auto-logging in
    if (api.isAutoLoggingIn) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
      );
    }

    // Show login prompt if not logged in
    if (!api.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite,
              size: 80,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 20),
            Text(
              'Sign in to access your Liked Songs',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            // Retry Button
            OutlinedButton.icon(
              onPressed: () {
                final api = context.read<DabApiService>();
                final user = context.read<SettingsService>().getUser();
                if (user != null && user.token != null) {
                  api.autoLogin(user.token!);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'No saved credentials found. Please go to Home to sign in.')),
                  );
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh / Retry'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Liked Songs',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_favorites.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  iconSize: 50,
                  color: AppTheme.primaryGreen,
                  onPressed: () => player.playAll(_favorites),
                ),
              if (_favorites.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  iconSize: 28, // Slightly smaller than play
                  color: isDark ? Colors.white70 : Colors.black54,
                  tooltip: 'Download All',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          BatchDownloadDialog(tracks: _favorites),
                    );
                  },
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                color: isDark ? Colors.white54 : Colors.black45,
                onPressed: _loadFavorites,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.primaryGreen))
                : _favorites.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.favorite_border,
                              size: 60,
                              color: isDark ? Colors.white24 : Colors.black26,
                            ),
                            const SizedBox(height: 15),
                            Text(
                              'No liked songs yet',
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Like songs to see them here',
                              style: TextStyle(
                                color: isDark ? Colors.white30 : Colors.black38,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _favorites.length,
                        itemBuilder: (context, index) {
                          return TrackListTile(
                            track: _favorites[index],
                            tracks: _favorites,
                            index: index,
                            isFavorite: true,
                            onRemove: () {
                              // If unliked from here, reload logic
                              _loadFavorites();
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
