import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/local_library_service.dart';
import '../../core/models/models.dart';
import '../../core/models/addon_models.dart';
import '../../core/services/history_service.dart';
import '../../core/services/last_fm_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/utils/app_toast.dart';
import '../import/playlist_import_dialog.dart';
import '../search/search_screen.dart';

/// Home Screen - displays play history and welcome message
class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const HomeScreen({super.key, this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
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
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final lastFm = context.read<LastFmService>();
    // If authenticated and no recs, fetch them
    if (lastFm.isAuthenticated &&
        _recommendations.isEmpty &&
        !_loadingRecommendations) {
      _fetchRecommendations();
    }
  }

  Future<void> _fetchRecommendations() async {
    if (!mounted) return;

    final lastFm = context.read<LastFmService>();
    final addonService = context.read<AddonService>();

    if (!lastFm.isAuthenticated) {
      if (mounted) setState(() => _recommendations = []);
      return;
    }

    if (mounted) setState(() => _loadingRecommendations = true);

    try {
      final rawRecs = await lastFm.getRecommendations();
      if (!mounted) return;

      // Parallelize searches using active addon
      final searchFutures = rawRecs.take(10).map((rec) async {
        final query = "${rec['name']} ${rec['artist']}";
        try {
          // Use captured addonService to avoid context lookup after await
          final results = await addonService.search(query, limit: 1);
          if (results != null && results.tracks.isNotEmpty) {
            return _mapTrack(results.tracks.first);
          }
        } catch (e) {
          print('Search error for $query: $e');
        }
        return null;
      });

      final results = await Future.wait(searchFutures);
      if (!mounted) return;

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
    final isDark = settings.isDarkMode;

    return _buildHomeContent(isDark, settings);
  }

  Track _mapTrack(AddonTrack at) {
    return Track(
      id: at.id,
      title: at.title,
      artist: at.artist,
      albumTitle: at.album,
      albumCover: at.artworkURL,
      duration: at.duration,
      addonId: at.addonId,
      addonTrackId: at.id,
      streamURL: at.streamURL,
    );
  }

  Widget _buildHomeContent(bool isDark, SettingsService settings) {
    final history = context.watch<HistoryService>();
    final playHistory = history.recentlyPlayed;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          // Greeting
          Text(
            'Discover Music',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
            ),
          ),
          Text(
            'Welcome to BeatBoss',
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          _buildSearchBar(isDark, history.recentSearches),
          const SizedBox(height: 25),

          // Play history section
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

          // Last.FM Connect Prompt
          if (!context.watch<LastFmService>().isAuthenticated) ...[
            _buildLastFmConnectCard(context, isDark),
            const SizedBox(height: 30),
          ],

          // Recommendations Section
          if (context.watch<LastFmService>().isAuthenticated) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recommended for You',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Recommendations',
                  onPressed:
                      _loadingRecommendations ? null : _fetchRecommendations,
                ),
              ],
            ),
            const SizedBox(height: 15),
            if (_loadingRecommendations)
              const SizedBox(
                height: 220,
                child: Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.primaryGreen),
                ),
              )
            else if (_recommendations.isEmpty)
              const SizedBox(
                height: 100,
                child: Center(
                  child: Text('No recommendations found yet.'),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 150,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                ),
                itemCount: _recommendations.length,
                itemBuilder: (context, index) {
                  return _RecentTrackCard(
                    track: _recommendations[index],
                    isDark: isDark,
                  );
                },
              ),
            const SizedBox(height: 30),
          ],

          // Quick actions
          const Text(
            'Quick Actions',
            style: TextStyle(
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
                icon: Icons.library_music,
                label: 'Your Library',
                isDark: isDark,
                onTap: () => widget.onNavigate?.call(1), // Switch to Library
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
              // Navigate to Settings (Index 2)
              widget.onNavigate?.call(2);
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

  Widget _buildSearchBar(bool isDark, List<String> searchHistory) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          readOnly: true,
          onTap: () {
            widget.onNavigate?.call(3);
          },
          decoration: InputDecoration(
            hintText: 'Search for tracks...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (searchHistory.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('Recent Searches',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                  letterSpacing: 0.5,
                )),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: searchHistory.length > 8 ? 8 : searchHistory.length,
              itemBuilder: (context, index) {
                final query = searchHistory[index];
                return GestureDetector(
                  onTap: () => widget.onNavigate?.call(3),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [
                                Colors.white.withOpacity(0.1),
                                Colors.white.withOpacity(0.05)
                              ]
                            : [
                                Colors.black.withOpacity(0.05),
                                Colors.black.withOpacity(0.02)
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withOpacity(0.05),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        query,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ]
      ],
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
                              color: Colors.black.withValues(alpha: 0.5),
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
                                AppToast.show(context, 'Added to Queue');
                                break;
                              case 'play_next':
                                player.playNext(track);
                                AppToast.show(context, 'Will play next');
                                break;
                              case 'download':
                                final addonService =
                                    context.read<AddonService>();
                                final downloadManager =
                                    context.read<DownloadManagerService>();
                                addonService
                                    .getStreamUrl(
                                        track.addonTrackId ?? track.id,
                                        addonId: track.addonId)
                                    .then((url) {
                                  if (url != null && context.mounted) {
                                    downloadManager.downloadTrack(
                                        track: track, streamUrl: url);
                                    AppToast.show(context, 'Download started');
                                  } else if (context.mounted) {
                                    AppToast.show(
                                        context, 'Failed to get download URL',
                                        isError: true);
                                  }
                                });
                                break;
                              case 'add_library':
                                _showLibraryPicker(context, track);
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
                            const PopupMenuItem(
                              value: 'add_library',
                              child: Row(
                                children: [
                                  Icon(Icons.library_add, size: 20),
                                  SizedBox(width: 10),
                                  Text('Add to Library'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'download',
                              child: Row(
                                children: [
                                  Icon(Icons.download, size: 20),
                                  SizedBox(width: 10),
                                  Text('Download'),
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

  void _showLibraryPicker(BuildContext context, Track track) async {
    final addonService = context.read<AddonService>();
    final localService = context.read<LocalLibraryService>();

    final cloudLibraries = await addonService.getLibraries();
    final localLibraries = localService.getLibraries();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bContext) {
        if (cloudLibraries.isEmpty && localLibraries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              heightFactor: 1,
              child: Text('No libraries found. Create one first!'),
            ),
          );
        }

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 20),
          children: [
            if (localLibraries.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('LOCAL LIBRARIES',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),
              ...localLibraries.map((lib) => ListTile(
                    leading:
                        const Icon(Icons.folder, color: AppTheme.primaryGreen),
                    title: Text(lib.name),
                    onTap: () async {
                      Navigator.pop(bContext);
                      final success =
                          await localService.addTrackToLibrary(lib.id, track);
                      if (context.mounted) {
                        AppToast.show(
                          context,
                          success ? 'Added to ${lib.name}' : 'Failed to add',
                          isError: !success,
                        );
                      }
                    },
                  )),
            ],
            if (cloudLibraries.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('CLOUD LIBRARIES',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),
              ...cloudLibraries.map((lib) => ListTile(
                    leading:
                        const Icon(Icons.cloud, color: AppTheme.primaryGreen),
                    title: Text(lib.name),
                    onTap: () async {
                      Navigator.pop(bContext);
                      final success = await addonService
                          .addTracksToLibrary(lib.id, [track]);
                      if (context.mounted) {
                        AppToast.show(
                          context,
                          success ? 'Added to ${lib.name}' : 'Failed to add',
                          isError: !success,
                        );
                      }
                    },
                  )),
            ],
          ],
        );
      },
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
