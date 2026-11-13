import 'dart:async';

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
import '../../core/recommendations/rec_models.dart';
import '../../core/recommendations/recommendation_service.dart';
import '../../core/recommendations/track_resolver.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/utils/app_toast.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../import/playlist_import_dialog.dart';
import '../search/search_screen.dart';
import '../shared/horizontal_scroll_wrapper.dart';

/// Home Screen - displays play history and welcome message
class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const HomeScreen({super.key, this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  // Addon catalog
  List<Track> _catalogTracks = [];
  List<AddonAlbum> _recommendedAlbums = [];
  List<AddonPlaylist> _recommendedPlaylists = [];
  bool _loadingRecommendations = false;

  // Personal recommendations (cached shelf + tracks resolved one by one)
  RecShelf? _recShelf;
  List<Track?> _recResolved = [];
  List<bool> _recDone = [];
  StreamSubscription<(int, Track?)>? _resolveSub;

  late final LastFmService _lastFmService;
  late final SettingsService _settingsService;
  late final RecommendationService _recService;
  bool _couldRecommend = false;
  bool _couldUseCatalog = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _lastFmService = context.read<LastFmService>();
    _settingsService = context.read<SettingsService>();
    _recService = context.read<RecommendationService>();

    // Show the cached shelf immediately, before any network call.
    _couldRecommend = _recService.canRecommend;
    _couldUseCatalog = _settingsService.useAddonCatalogRecommendations;
    _applyShelf(_recService.cachedRecommendedShelf, notify: false);

    // Refetch when Last.fm login or the recommendations setting changes.
    _lastFmService.addListener(_onSourceChanged);
    _settingsService.addListener(_onSourceChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchRecommendations());
  }

  @override
  void dispose() {
    _lastFmService.removeListener(_onSourceChanged);
    _settingsService.removeListener(_onSourceChanged);
    _resolveSub?.cancel();
    super.dispose();
  }

  void _onSourceChanged() {
    if (!mounted) return;
    final canNow = _recService.canRecommend;
    final catalogNow = _settingsService.useAddonCatalogRecommendations;
    if (canNow == _couldRecommend && catalogNow == _couldUseCatalog) return;

    final turnedOn =
        (canNow && !_couldRecommend) || (catalogNow && !_couldUseCatalog);
    _couldRecommend = canNow;
    _couldUseCatalog = catalogNow;

    // Drop whatever was just switched off.
    if (!canNow || !catalogNow) {
      setState(() {
        if (!canNow) _applyShelf(null, notify: false);
        if (!catalogNow) {
          _catalogTracks = [];
          _recommendedAlbums = [];
          _recommendedPlaylists = [];
        }
      });
    }
    if (turnedOn && !_loadingRecommendations) _fetchRecommendations();
  }

  /// Shows [shelf] and starts resolving its tracks to playable ones. Does
  /// nothing when the same shelf is already shown.
  void _applyShelf(RecShelf? shelf, {bool notify = true}) {
    if (shelf?.fetchedAt == _recShelf?.fetchedAt && shelf?.id == _recShelf?.id) {
      return;
    }
    _resolveSub?.cancel();
    _resolveSub = null;

    void update() {
      _recShelf = shelf;
      _recResolved = List<Track?>.filled(shelf?.tracks.length ?? 0, null);
      _recDone = List<bool>.filled(shelf?.tracks.length ?? 0, false);
    }

    if (notify && mounted) {
      setState(update);
    } else {
      update();
    }
    if (shelf == null || shelf.tracks.isEmpty) return;

    _resolveSub = _recService.resolver.resolveMany(shelf.tracks).listen((event) {
      final (index, track) = event;
      if (!mounted || _recShelf != shelf) return;
      setState(() {
        _recResolved[index] = track;
        _recDone[index] = true;
      });
    });
  }

  Future<void> _fetchRecommendations({bool force = false}) async {
    if (!mounted) return;
    setState(() => _loadingRecommendations = true);

    try {
      final addonService = context.read<AddonService>();

      Future<AddonSearchResult?> loadCatalog() async {
        // Respect the setting: don't even ask the addon for a catalog.
        if (!_settingsService.useAddonCatalogRecommendations) return null;
        try {
          return await addonService.getCatalog();
        } catch (e) {
          print('Error fetching catalog: $e');
          return null;
        }
      }

      // Independent sources: the addon catalog and the personal shelf.
      final catalogFuture = loadCatalog();
      final shelfFuture = _recService.recommendedShelf(force: force);
      final catalog = await catalogFuture;
      final shelf = await shelfFuture;
      if (!mounted) return;

      setState(() {
        _catalogTracks = catalog?.tracks.map(trackFromAddon).toList() ?? [];
        _recommendedAlbums = catalog?.albums ?? [];
        _recommendedPlaylists = catalog?.playlists ?? [];
        _loadingRecommendations = false;
      });
      _applyShelf(shelf);
    } catch (e) {
      print('Error fetching recommendations: $e');
      if (mounted) setState(() => _loadingRecommendations = false);
    }
  }

  /// Plays the resolved recommendations as one queue, starting at [index].
  void _playRecommendation(int index) {
    final playable = <Track>[];
    var start = 0;
    for (var i = 0; i < _recResolved.length; i++) {
      final t = _recResolved[i];
      if (t == null) continue;
      if (i == index) start = playable.length;
      playable.add(t);
    }
    if (playable.isEmpty) return;
    context.read<AudioPlayerService>().playAll(playable, startIndex: start);
  }

  /// Shelf entries to display: resolved ones plus those still resolving.
  /// Entries whose search finished without a match are dropped.
  List<({int index, RecTrack rec, Track? resolved})> get _recVisibleItems {
    final shelf = _recShelf;
    if (shelf == null) return const [];
    return [
      for (var i = 0; i < shelf.tracks.length; i++)
        if (!(_recDone[i] && _recResolved[i] == null))
          (index: i, rec: shelf.tracks[i], resolved: _recResolved[i]),
    ];
  }

  bool get _hasAnyRecommendations =>
      _catalogTracks.isNotEmpty ||
      _recVisibleItems.isNotEmpty ||
      _recommendedAlbums.isNotEmpty ||
      _recommendedPlaylists.isNotEmpty;

  Widget _buildSectionHeader(String title, {bool showRefresh = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        if (showRefresh)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Recommendations',
            onPressed: _loadingRecommendations
                ? null
                : () => _fetchRecommendations(force: true),
          ),
      ],
    );
  }

  Widget _buildTrackGrid({
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.65,
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return _buildHomeContent(isDark, settings);
  }

  Widget _buildHomeContent(bool isDark, SettingsService settings) {
    final history = context.watch<HistoryService>();
    // User requested top 5
    final playHistory = history.recentlyPlayed.take(5).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 20),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 375),
            childAnimationBuilder: (widget) => SlideAnimation(
              verticalOffset: 50.0,
              child: widget,
            ),
            children: <Widget>[
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
            HorizontalScrollWrapper(
              title: 'Recently Played',
              titleStyle: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              listHeight: 220,
              itemWidth: 140,
              itemSpacing: 15,
              builder: (context, controller) => ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: playHistory.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 15),
                    child: _RecentTrackCard(
                      track: playHistory[index],
                      isDark: isDark,
                      width: 140,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 30),
          ],

          // Recommendations Section
          if (true) ...[
            if (_loadingRecommendations && !_hasAnyRecommendations)
              const SizedBox(
                height: 220,
                child: Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.primaryGreen),
                ),
              )
            else if (!_hasAnyRecommendations)
              SizedBox(
                height: 100,
                child: Center(
                  child: Text(
                    (_recService.canRecommend ||
                            settings.useAddonCatalogRecommendations)
                        ? 'No recommendations found yet.'
                        : 'Recommendations are turned off in Settings.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              if (_catalogTracks.isNotEmpty) ...[
                _buildSectionHeader(
                  'From ${context.read<AddonService>().activeAddon?.name ?? 'your addon'}',
                  showRefresh: _recVisibleItems.isEmpty,
                ),
                const SizedBox(height: 15),
                _buildTrackGrid(
                  itemCount: _catalogTracks.length,
                  itemBuilder: (context, index) => _RecentTrackCard(
                    track: _catalogTracks[index],
                    isDark: isDark,
                  ),
                ),
                const SizedBox(height: 30),
              ],
              if (_recVisibleItems.isNotEmpty) ...[
                _buildSectionHeader(
                  _recShelf?.title ?? 'Recommended for you',
                  showRefresh: true,
                ),
                const SizedBox(height: 15),
                _buildTrackGrid(
                  itemCount: _recVisibleItems.length,
                  itemBuilder: (context, i) {
                    final item = _recVisibleItems[i];
                    final resolved = item.resolved;
                    if (resolved != null) {
                      return _RecentTrackCard(
                        track: resolved,
                        isDark: isDark,
                        onTap: () => _playRecommendation(item.index),
                      );
                    }
                    // Not resolved yet: show the Last.fm title/artist as a
                    // placeholder that can't be played.
                    return _RecentTrackCard(
                      track: Track(
                        id: item.rec.key,
                        title: item.rec.title,
                        artist: item.rec.artist,
                        albumCover: item.rec.imageUrl,
                      ),
                      isDark: isDark,
                      onTap: () {},
                      showMenu: false,
                    );
                  },
                ),
                const SizedBox(height: 30),
              ],
              if (_recommendedAlbums.isNotEmpty) ...[
                HorizontalScrollWrapper(
                  title: 'Albums',
                  titleStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  trailing: (_catalogTracks.isEmpty && _recVisibleItems.isEmpty)
                      ? IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh Recommendations',
                          onPressed: _loadingRecommendations
                              ? null
                              : () => _fetchRecommendations(force: true),
                        )
                      : null,
                  listHeight: 210,
                  itemWidth: 140,
                  itemSpacing: 15,
                  builder: (context, controller) => ListView.builder(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    itemCount: _recommendedAlbums.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 15),
                        child: AddonAlbumCard(album: _recommendedAlbums[index], isDark: isDark),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 30),
              ],
              if (_recommendedPlaylists.isNotEmpty) ...[
                HorizontalScrollWrapper(
                  title: 'Playlists',
                  titleStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  listHeight: 210,
                  itemWidth: 140,
                  itemSpacing: 15,
                  builder: (context, controller) => ListView.builder(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    itemCount: _recommendedPlaylists.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 15),
                        child: AddonPlaylistCard(playlist: _recommendedPlaylists[index], isDark: isDark),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ],
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
        ),
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

  /// Overrides the default tap (play just this track).
  final VoidCallback? onTap;

  /// Whether to show the overflow menu. Off for placeholder cards.
  final bool showMenu;

  const _RecentTrackCard({
    required this.track,
    required this.isDark,
    this.width,
    this.onTap,
    this.showMenu = true,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.read<AudioPlayerService>();

    return GestureDetector(
      onTap: onTap ?? () => player.playSingleTrack(track),
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
                        memCacheWidth: 400,
                        placeholder: (_, __) =>
                            Container(color: AppTheme.darkCard),
                        errorWidget: (_, __, ___) => Container(
                          color: AppTheme.darkCard,
                          child: const Icon(Icons.music_note,
                              size: 40, color: Colors.white30),
                        ),
                      ),
                    ),
                    if (showMenu)
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    track.artist,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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
          padding: EdgeInsets.fromLTRB(
              0, 20, 0, 20 + MediaQuery.of(bContext).viewPadding.bottom),
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
