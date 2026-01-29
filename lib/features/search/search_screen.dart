import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/models.dart';
import '../shared/track_list_tile.dart';
import '../import/playlist_import_dialog.dart';
import '../../core/services/history_service.dart';

/// Search Screen - search DAB API and display results
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  SearchResults? _results;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) return;

    // Add to history
    context.read<HistoryService>().addSearch(query);

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = context.read<DabApiService>();
      final results = await api.search(query, limit: 50);

      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Search',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => PlaylistImportDialog.show(context),
                icon: const Icon(Icons.playlist_add, color: Colors.black),
                label: const Text('IMPORT',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Search box
          TextField(
            controller: _searchController,
            focusNode: _focusNode,
            decoration: InputDecoration(
              hintText: 'Search for tracks, albums, artists...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _results = null;
                        });
                      },
                    )
                  : null,
            ),
            onSubmitted: _search,
            onChanged: (value) => setState(() {}),
          ),

          const SizedBox(height: 20),

          // Results
          Expanded(
            child: _buildResults(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          'Error: $_error',
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
        ),
      );
    }

    if (_results == null) {
      final history = context.watch<HistoryService>();
      final recents = history.recentSearches;

      if (recents.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search,
                size: 80,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              const SizedBox(height: 20),
              Text(
                'Search for your favorite music',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black45,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      } else {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Recent Searches',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: recents.length,
                itemBuilder: (context, index) {
                  final term = recents[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.history,
                        color: isDark ? Colors.white54 : Colors.black45),
                    title: Text(
                      term,
                      style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    onTap: () {
                      _searchController.text = term;
                      _search(term);
                    },
                    trailing: IconButton(
                        icon: Icon(Icons.north_west,
                            size: 16,
                            color: isDark ? Colors.white30 : Colors.black26),
                        onPressed: () {
                          _searchController.text = term;
                        }),
                  );
                },
              ),
            ),
          ],
        );
      }
    }

    if (_results!.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // Albums section
        if (_results!.albums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Text(
                'Albums',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _results!.albums.length,
                itemBuilder: (context, index) {
                  return _AlbumCard(
                    album: _results!.albums[index],
                    isDark: isDark,
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 25)),
        ],

        // Tracks section
        if (_results!.tracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Tracks',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return TrackListTile(
                  track: _results!.tracks[index],
                  tracks: _results!.tracks,
                  index: index,
                );
              },
              childCount: _results!.tracks.length,
            ),
          ),
        ],
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final Album album;
  final bool isDark;

  const _AlbumCard({required this.album, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // TODO: Navigate to album detail
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 140,
              height: 140,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: album.cover ?? '',
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppTheme.darkCard),
                  errorWidget: (_, __, ___) => Container(
                    color: AppTheme.darkCard,
                    child: const Icon(Icons.album,
                        size: 40, color: Colors.white30),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.title,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              album.artist,
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
