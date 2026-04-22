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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkMode;
    final player = context.read<AudioPlayerService>();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(isDark),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))),
            )
          else if (_tracks.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text('No tracks found', style: TextStyle(color: Colors.white54))),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return TrackListTile(
                      track: _tracks[index],
                      tracks: _tracks,
                      index: index,
                    );
                  },
                  childCount: _tracks.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _tracks.isNotEmpty ? Padding(
        padding: const EdgeInsets.only(bottom: 70), // Avoid overlap with PlayerBar
        child: FloatingActionButton.extended(
          onPressed: () => player.playAll(_tracks),
          backgroundColor: AppTheme.primaryGreen,
          icon: const Icon(Icons.play_arrow, color: Colors.black),
          label: const Text('PLAY ALL', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ) : null,
      bottomNavigationBar: const PlayerBar(),
    );
  }

  Widget _buildAppBar(bool isDark) {
    return SliverAppBar(
      expandedHeight: 350, // Increased for a more premium look
      pinned: true,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Blurred Background
            if (_artwork != null)
              CachedNetworkImage(
                imageUrl: _artwork!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
              )
            else
              Container(color: Colors.grey[900]),
            
            // Blur overlay
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.3),
                      (isDark ? AppTheme.darkBackground : AppTheme.lightBackground).withValues(alpha: 0.9),
                      isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
                    ],
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
              ),
            ),
            
            // Foreground Content
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Center Artwork
                  if (_artwork != null)
                    Container(
                      height: 180,
                      width: 180,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                        borderRadius: BorderRadius.circular(widget.type == AddonDetailType.artist ? 90 : 12),
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(_artwork!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    _title ?? 'Loading...', 
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 16,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
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
    );
  }
}
