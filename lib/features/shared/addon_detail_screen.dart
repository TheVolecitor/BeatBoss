import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/models.dart';
import '../../core/models/addon_models.dart';
import 'track_list_tile.dart';
import 'batch_download_dialog.dart';
import '../player/player_bar.dart';


enum AddonDetailType { artist, album, playlist }

class AddonDetailScreen extends StatefulWidget {
  final String id;
  final AddonDetailType type;
  final String addonId;
  final String? initialTitle;
  final String? initialArtwork;

  const AddonDetailScreen({
    super.key,
    required this.id,
    required this.type,
    required this.addonId,
    this.initialTitle,
    this.initialArtwork,
  });

  @override
  State<AddonDetailScreen> createState() => _AddonDetailScreenState();
}

class _AddonDetailScreenState extends State<AddonDetailScreen> {
  bool _isLoading = true;
  String? _title;
  String? _subtitle;
  String? _artwork;
  List<Track> _tracks = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = widget.initialTitle;
    _artwork = widget.initialArtwork;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final addonService = context.read<AddonService>();
    
    try {
      if (widget.type == AddonDetailType.album) {
        final album = await addonService.getAlbumDetail(widget.id, addonId: widget.addonId);
        if (album != null) {
          setState(() {
            _title = album.title;
            _subtitle = album.artist;
            _artwork = album.artworkURL;
            _tracks = album.tracks?.map((at) => _mapToTrack(at)).toList() ?? [];
            _isLoading = false;
          });
        }
      } else if (widget.type == AddonDetailType.artist) {
        final artist = await addonService.getArtistDetail(widget.id, addonId: widget.addonId);
        if (artist != null) {
          setState(() {
            _title = artist.name;
            _subtitle = 'Artist';
            _artwork = artist.artworkURL;

            _tracks = artist.topTracks?.map((at) => _mapToTrack(at)).toList() ?? [];
            _isLoading = false;
          });
        }
      } else if (widget.type == AddonDetailType.playlist) {
        final playlist = await addonService.getPlaylistDetail(widget.id, addonId: widget.addonId);
        if (playlist != null) {
          setState(() {
            _title = playlist.title;
            _subtitle = playlist.creator ?? 'Playlist';
            _artwork = playlist.artworkURL;
            _tracks = playlist.tracks?.map((at) => _mapToTrack(at)).toList() ?? [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load details: $e';
          _isLoading = false;
        });
      }
    }
  }

  Track _mapToTrack(AddonTrack at) {
    return Track(
      id: at.id,
      title: at.title,
      artist: at.artist,
      albumTitle: at.album,
      duration: at.duration,
      albumCover: at.artworkURL,
      addonId: widget.addonId,
      infoText: at.infoText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkMode;
    final player = context.read<AudioPlayerService>();
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: isDesktop ? null : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: isDesktop 
        ? _buildDesktopSplitPane(context, isDark, player)
        : _buildMobileView(context, isDark, player),
      bottomNavigationBar: const PlayerBar(),
    );
  }

  Widget _buildDesktopSplitPane(BuildContext context, bool isDark, AudioPlayerService player) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-screen Glassmorphic Backdrop
        if (_artwork != null)
          CachedNetworkImage(
            imageUrl: _artwork!,
            fit: BoxFit.cover,
            memCacheWidth: 400,
            errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
          )
        else
          Container(color: Colors.grey[900]),
        
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.7), // Full screen blur
          ),
        ),

        // Foreground Content
        Row(
          children: [
            // Left Sidebar
            SizedBox(
              width: 350,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Back button & Download
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const BackButton(color: Colors.white),
                          if (_tracks.isNotEmpty)
                            IconButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => BatchDownloadDialog(tracks: _tracks),
                                );
                              },
                              icon: const Icon(Icons.download_rounded, color: Colors.white),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.transparent,
                              ),
                              tooltip: 'Download All',
                            ),
                        ],
                      ),
                      const Spacer(),
                      // Center Artwork
                      Center(
                        child: _artwork != null
                          ? Hero(
                              tag: widget.id,
                              child: Container(
                                height: 240,
                                width: 240,
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 30,
                                      offset: const Offset(0, 15),
                                    )
                                  ],
                                  borderRadius: BorderRadius.circular(widget.type == AddonDetailType.artist ? 120 : 16),
                                  image: DecorationImage(
                                    image: CachedNetworkImageProvider(_artwork!, maxWidth: 400),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              height: 240,
                              width: 240,
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(widget.type == AddonDetailType.artist ? 120 : 16),
                              ),
                              child: const Icon(Icons.music_note, size: 80, color: Colors.white24),
                            ),
                      ),
                      const SizedBox(height: 32),
                      // Title & Subtitle (Centered)
                      Center(
                        child: Column(
                          children: [
                            if (_subtitle != null)
                              Text(
                                _subtitle!.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            const SizedBox(height: 8),
                            Text(
                              _title ?? 'Loading...', 
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Actions (Play All)
                      if (_tracks.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => player.playAll(_tracks),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('PLAY ALL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
            
            // Right Pane (Track List)
            Expanded(
              child: SafeArea(
                child: _buildTracksList(isDark),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileView(BuildContext context, bool isDark, AudioPlayerService player) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 350,
          pinned: true,
          backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (_artwork != null)
                  CachedNetworkImage(
                    imageUrl: _artwork!,
                    fit: BoxFit.cover,
                    memCacheWidth: 400,
                  ),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
                  ),
                ),
                SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_artwork != null)
                        Container(
                          height: 180,
                          width: 180,
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              )
                            ],
                            borderRadius: BorderRadius.circular(widget.type == AddonDetailType.artist ? 90 : 16),
                            image: DecorationImage(
                              image: CachedNetworkImageProvider(_artwork!, maxWidth: 400),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          _title ?? 'Loading...', 
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (_tracks.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => BatchDownloadDialog(tracks: _tracks),
                  );
                },
              ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () => player.playAll(_tracks),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('PLAY ALL', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return TrackListTile(
                  track: _tracks[index],
                  tracks: _tracks,
                  index: index,
                  showInfoText: true,
                );
              },
              childCount: _tracks.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTracksList(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
    } else if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    } else if (_tracks.isEmpty) {
      return const Center(child: Text('No tracks found', style: TextStyle(color: Colors.white54)));
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ListView.builder(
        itemCount: _tracks.length,
        itemBuilder: (context, index) {
          return TrackListTile(
            track: _tracks[index],
            tracks: _tracks,
            index: index,
            showInfoText: true,
          );
        },
      ),
    );
  }
}
