import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/models.dart';
import '../../core/models/addon_models.dart';
import '../shared/track_list_tile.dart';
import '../import/playlist_import_dialog.dart';
import '../../core/services/history_service.dart';
import '../shared/addon_detail_screen.dart';
import '../shared/horizontal_scroll_wrapper.dart';

/// Search Screen - searches active addon and displays unified results
class SearchScreen extends StatefulWidget {
  final Function(int)? onNavigate;
  const SearchScreen({super.key, this.onNavigate});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  AddonSearchResult? _results;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void focusSearch() {
    _focusNode.requestFocus();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) return;

    context.read<HistoryService>().addSearch(query);

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final addonService = context.read<AddonService>();
      final results = await addonService.search(query);

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

  Track _mapToAddonTrack(AddonTrack at) {
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
      infoText: at.infoText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final addonService = context.watch<AddonService>();
    final isDark = settings.isDarkMode;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: isDark ? Colors.white : Colors.black,
                    onPressed: () => widget.onNavigate?.call(0),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Search',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
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

          const SizedBox(height: 12),
          
          if (addonService.activeAddon != null)
            _buildAddonSelector(context, addonService, isDark),

          const SizedBox(height: 12),

          TextField(
            controller: _searchController,
            focusNode: _focusNode,
            autofocus: true,
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

          Expanded(
            child: _buildResults(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildAddonSelector(BuildContext context, AddonService addonService, bool isDark) {
    final active = addonService.activeAddon!;
    return InkWell(
      onTap: () => _showAddonPicker(context, addonService),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black12,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active.icon != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  active.icon!, 
                  width: 16, 
                  height: 16, 
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.extension, 
                    size: 16, 
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ] else ...[
              Icon(Icons.extension, size: 16, color: isDark ? Colors.white70 : Colors.black87),
              const SizedBox(width: 8),
            ],
            Text(
              'Searching via ${active.name}',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: isDark ? Colors.white70 : Colors.black87),
          ],
        ),
      ),
    );
  }

  void _showAddonPicker(BuildContext context, AddonService addonService) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final searchAddons = addonService.installedAddons.where((a) => a.supportsSearch).toList();
        return ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(
              0, 8, 0, 8 + MediaQuery.of(context).viewPadding.bottom),
          itemCount: searchAddons.length,
          itemBuilder: (context, index) {
            final addon = searchAddons[index];
            return ListTile(
              leading: addon.icon != null
                  ? Image.network(
                      addon.icon!, 
                      width: 24, 
                      height: 24,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.extension),
                    )
                  : const Icon(Icons.extension),
              title: Text(addon.name),
              trailing: addonService.activeAddonId == addon.id
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                addonService.setActiveAddon(addon.id);
                Navigator.pop(context);
                if (_searchController.text.isNotEmpty) {
                  _search(_searchController.text);
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildResults(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
    }

    final addonService = context.watch<AddonService>();
    if (addonService.activeAddonId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.extension_off, size: 80, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 20),
            Text(
              'No active search provider',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Please select or install an addon to search.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                if (widget.onNavigate != null) {
                  widget.onNavigate!(4); // Index 4 is Addons
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Go to Addons tab to enable a search provider')),
                  );
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Please install an addon'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Text('Error: $_error', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45)),
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
              Icon(Icons.search, size: 80, color: isDark ? Colors.white24 : Colors.black26),
              const SizedBox(height: 20),
              Text(
                'Search for your favourite music',
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 16),
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
                    leading: Icon(Icons.history, color: isDark ? Colors.white54 : Colors.black45),
                    title: Text(term, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                    onTap: () {
                      _searchController.text = term;
                      _search(term);
                    },
                    trailing: IconButton(
                        icon: Icon(Icons.north_west, size: 16, color: isDark ? Colors.white30 : Colors.black26),
                        onPressed: () { _searchController.text = term; }),
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
        child: Text('No results found', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45)),
      );
    }

    // Map AddonTrack to Track for the player queue
    final allMappedTracks = _results!.tracks.map((t) => _mapToAddonTrack(t)).toList();
    
    // Split tracks into Top 3 and More
    final topTracks = allMappedTracks.take(3).toList();
    final moreTracks = allMappedTracks.length > 3 ? allMappedTracks.sublist(3) : <Track>[];

    return CustomScrollView(
      slivers: [
        // 1. Top Results (First 3 Tracks)
        if (topTracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Top Results', style: _sectionStyle(isDark)),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return TrackListTile(
                  track: topTracks[index],
                  tracks: allMappedTracks, // Pass full list for contiguous playback
                  index: index,
                  showInfoText: true,
                );
              },
              childCount: topTracks.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 25)),
        ],

        if (_results!.artists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: HorizontalScrollWrapper(
              title: 'Artists',
              titleStyle: _sectionStyle(isDark),
              listHeight: 140,
              itemWidth: 100, // Artists have 100 width
              itemSpacing: 15,
              builder: (context, controller) => ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: _results!.artists.length,
                itemBuilder: (context, index) {
                  final artist = _results!.artists[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 15),
                    child: AddonArtistCard(artist: artist, isDark: isDark),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 25)),
        ],

        if (_results!.albums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: HorizontalScrollWrapper(
              title: 'Albums',
              titleStyle: _sectionStyle(isDark),
              listHeight: 210,
              itemWidth: 140, // Albums have 140 width
              itemSpacing: 15,
              builder: (context, controller) => ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: _results!.albums.length,
                itemBuilder: (context, index) {
                  final album = _results!.albums[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 15),
                    child: AddonAlbumCard(album: album, isDark: isDark),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 25)),
        ],

        if (_results!.playlists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: HorizontalScrollWrapper(
              title: 'Playlists',
              titleStyle: _sectionStyle(isDark),
              listHeight: 210,
              itemWidth: 140, // Playlists have 140 width
              itemSpacing: 15,
              builder: (context, controller) => ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: _results!.playlists.length,
                itemBuilder: (context, index) {
                  final playlist = _results!.playlists[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 15),
                    child: AddonPlaylistCard(playlist: playlist, isDark: isDark),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 25)),
        ],

        // 5. More Tracks
        if (moreTracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('More Tracks', style: _sectionStyle(isDark)),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return TrackListTile(
                  track: moreTracks[index],
                  tracks: allMappedTracks, // Pass full list
                  index: index + 3, // Offset index for proper queue position
                  showInfoText: true,
                );
              },
              childCount: moreTracks.length,
            ),
          ),
        ],
      ],
    );

  }

  TextStyle _sectionStyle(bool isDark) => TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      );
}

class AddonAlbumCard extends StatelessWidget {
  final AddonAlbum album;
  final bool isDark;

  const AddonAlbumCard({super.key, required this.album, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddonDetailScreen(
              id: album.id,
              type: AddonDetailType.album,
              addonId: album.addonId,
              initialTitle: album.title,
              initialArtwork: album.artworkURL,
            ),
          ),
        );
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
                color: isDark ? Colors.white10 : Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: album.artworkURL != null
                  ? Hero(
                      tag: album.id,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: album.artworkURL!,
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error),
                        ),
                      ),
                    )
                  : const Icon(Icons.album, size: 60, color: Colors.white24),
            ),
            const SizedBox(height: 8),
            Text(
              album.title,
              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    album.artist,
                    style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (album.infoText != null && album.infoText!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      album.infoText!,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AddonArtistCard extends StatelessWidget {
  final AddonArtist artist;
  final bool isDark;

  const AddonArtistCard({super.key, required this.artist, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddonDetailScreen(
              id: artist.id,
              type: AddonDetailType.artist,
              addonId: artist.addonId,
              initialTitle: artist.name,
              initialArtwork: artist.artworkURL,
            ),
          ),
        );
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 15),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black12,
                shape: BoxShape.circle,
              ),
              child: artist.artworkURL != null
                  ? Hero(
                      tag: artist.id,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(70),
                        child: CachedNetworkImage(
                          imageUrl: artist.artworkURL!,
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error),
                        ),
                      ),
                    )
                  : const Icon(Icons.person, size: 60, color: Colors.white24),
            ),
            const SizedBox(height: 8),
            Text(
              artist.name,
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (artist.infoText != null && artist.infoText!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  artist.infoText!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AddonPlaylistCard extends StatelessWidget {
  final AddonPlaylist playlist;
  final bool isDark;

  const AddonPlaylistCard({super.key, required this.playlist, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddonDetailScreen(
              id: playlist.id,
              type: AddonDetailType.playlist,
              addonId: playlist.addonId,
              initialTitle: playlist.title,
              initialArtwork: playlist.artworkURL,
            ),
          ),
        );
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
                color: isDark ? Colors.white10 : Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: playlist.artworkURL != null
                  ? Hero(
                      tag: playlist.id,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: playlist.artworkURL!,
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error),
                        ),
                      ),
                    )
                  : const Icon(Icons.queue_music, size: 60, color: Colors.white24),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.title,
              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    playlist.creator ?? 'Playlist',
                    style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (playlist.infoText != null && playlist.infoText!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      playlist.infoText!,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
