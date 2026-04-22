import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/local_library_service.dart';

import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_toast.dart';

/// Reusable Track List Tile - used across search, library, favourites
class TrackListTile extends StatelessWidget {
  final Track track;
  final List<Track> tracks;
  final int index;
  final String? libraryId;
  final VoidCallback? onRemove;

  const TrackListTile({
    super.key,
    required this.track,
    required this.tracks,
    required this.index,
    this.libraryId,
    this.onRemove,
    this.removeLabel = 'Remove from Library',
  });

  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final settings = context.watch<SettingsService>();
    final localLibrary = context.watch<LocalLibraryService>();
    final isDark = settings.isDarkMode;
    
    final isCurrentTrack = player.currentTrack?.id == track.id;
    final isPlaying = isCurrentTrack && player.isPlaying;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isCurrentTrack 
          ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05))
          : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
        borderRadius: BorderRadius.circular(12),
        border: isCurrentTrack 
          ? Border.all(color: AppTheme.primaryGreen.withOpacity(0.3), width: 1)
          : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          children: [
            _buildLeading(track),
            if (isPlaying)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: _MusicVisualizer(color: Colors.white, size: 20),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isCurrentTrack ? FontWeight.bold : FontWeight.w600,
                  color: isCurrentTrack ? AppTheme.primaryGreen : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ),
            if (track.isHiRes) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Hi-Res',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    )),
              ),
            ],
          ],
        ),
        subtitle: Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isCurrentTrack ? AppTheme.primaryGreen.withOpacity(0.7) : (isDark ? Colors.white54 : Colors.black54),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play/Pause toggle or just play
            IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: AppTheme.primaryGreen,
              ),
              onPressed: () {
                if (isCurrentTrack) {
                  player.togglePlayPause();
                } else {
                  player.playSingleTrack(track);
                }
              },
              tooltip: isPlaying ? 'Pause' : 'Play',
            ),
            _buildDownloadButton(context, track),
            // More menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  color: isDark ? Colors.white54 : Colors.black45),
              onSelected: (value) => _handleMenuAction(context, value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                    value: 'add_library', child: Text('Add to Library')),
                const PopupMenuItem(
                    value: 'play_next', child: Text('Play Next')),
                const PopupMenuItem(
                    value: 'add_queue', child: Text('Add to Queue')),
                PopupMenuItem(
                    value: localLibrary.isFavourite(track.id) ? 'unlike' : 'like',
                    child: Text(localLibrary.isFavourite(track.id) ? 'Unlike (Remove)' : 'Like')),
                if (onRemove != null)
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(removeLabel,
                        style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ],
        ),
        onTap: () {
          if (isCurrentTrack) {
            player.togglePlayPause();
          } else {
            player.playSingleTrack(track);
          }
        },
      ),
    );
  }

  // ... (existing helper methods remain the same)
  Widget _buildLeading(Track track) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.grey[800],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: track.albumCover != null && track.albumCover!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: track.albumCover!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(Icons.music_note),
              )
            : const Icon(Icons.music_note, color: Colors.white54),
      ),
    );
  }

  Widget _buildDownloadButton(BuildContext context, Track track) {
    final downloadManager = context.watch<DownloadManagerService>();
    final isDownloaded = downloadManager.isDownloaded(track.id.toString());
    final isDownloading = downloadManager.isDownloading(track.id.toString());
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    if (isDownloaded) {
      return IconButton(
        icon: const Icon(Icons.check_circle, color: AppTheme.primaryGreen),
        onPressed: () {}, // Already downloaded
        tooltip: 'Downloaded',
      );
    } else if (isDownloading) {
      final progress = downloadManager.getProgress(track.id.toString());
      return Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.only(right: 12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress != null ? progress / 100 : null,
              strokeWidth: 3,
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
            ),
            if (progress != null)
              Text(
                '${progress.toInt()}',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
          ],
        ),
      );
    } else {
      return IconButton(
        icon: Icon(Icons.download_rounded,
            color: isDark ? Colors.white54 : Colors.black45),
        onPressed: () async {
          final addonService = context.read<AddonService>();

          // Allow immediate feedback?
          // Better to show loading if possible, but for now just start async
          final url = await addonService.getStreamUrl(
              track.addonTrackId ?? track.id,
              addonId: track.addonId);
          if (url != null && context.mounted) {
            downloadManager.downloadTrack(
              track: track,
              streamUrl: url,
            );
          } else if (context.mounted) {
            AppToast.show(context, 'Failed to get download URL', isError: true);
          }
        },
        tooltip: 'Download',
      );
    }
  }

  void _handleMenuAction(BuildContext context, String action) {
    final player = context.read<AudioPlayerService>();
    final localLibrary = context.read<LocalLibraryService>();

    switch (action) {
      case 'add_library':
        _showLibraryPicker(context);
        break;
      case 'add_queue':
        player.addToQueue(track);
        AppToast.show(context, 'Added "${track.title}" to queue');
        break;
      case 'play_next':
        player.playNext(track);
        AppToast.show(context, 'Will play "${track.title}" next');
        break;
      case 'like':
      case 'unlike':
        localLibrary.toggleFavourite(track).then((_) {
          if (context.mounted) {
            final isFav = localLibrary.isFavourite(track.id);
            AppToast.show(
              context,
              isFav ? 'Added to Liked Songs' : 'Removed from Liked Songs',
            );
          }
        });
        break;
      case 'remove':
        onRemove?.call();
        break;
    }
  }

  void _showLibraryPicker(BuildContext context) async {
    final addonService = context.read<AddonService>();
    final localService = context.read<LocalLibraryService>();

    final cloudLibraries = await addonService.getLibraries();
    final localLibraries = localService.getLibraries();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add to Library',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            if (cloudLibraries.isEmpty && localLibraries.isEmpty)
              const Text('No libraries found. Create one first!')
            else
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (localLibraries.isNotEmpty) ...[
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('LOCAL LIBRARIES',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey))),
                      ...localLibraries.map((lib) => ListTile(
                            leading: const Icon(Icons.folder,
                                color: AppTheme.primaryGreen),
                            title: Text(lib.name),
                            onTap: () async {
                              final success = await localService
                                  .addTrackToLibrary(lib.id, track);
                              if (context.mounted) {
                                Navigator.pop(context);
                                AppToast.show(
                                  context,
                                  success
                                      ? 'Added to ${lib.name}'
                                      : 'Failed to add',
                                  isError: !success,
                                );
                              }
                            },
                          )),
                    ],
                    if (cloudLibraries.isNotEmpty) ...[
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('CLOUD LIBRARIES',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey))),
                      ...cloudLibraries.map((lib) => ListTile(
                            leading: const Icon(Icons.cloud,
                                color: AppTheme.primaryGreen),
                            title: Text(lib.name),
                            onTap: () async {
                              final success = await addonService
                                  .addTracksToLibrary(lib.id, [track]);
                              if (context.mounted) {
                                Navigator.pop(context);
                                AppToast.show(
                                  context,
                                  success
                                      ? 'Added to ${lib.name}'
                                      : 'Failed to add',
                                  isError: !success,
                                );
                              }
                            },
                          )),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MusicVisualizer extends StatefulWidget {
  final Color color;
  final double size;

  const _MusicVisualizer({required this.color, required this.size});

  @override
  State<_MusicVisualizer> createState() => _MusicVisualizerState();
}

class _MusicVisualizerState extends State<_MusicVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  // Pre-calculated sine-like wave values for one period (0.0 to 1.0)
  // This avoids real-time math.sin calls for every bar on every frame.
  static const List<double> _waveData = [
    0.5, 0.7, 0.9, 1.0, 0.9, 0.7, 0.5, 0.3, 0.1, 0.0, 0.1, 0.3
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200), // Slightly slower for smoother look
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size,
      width: widget.size * 1.2,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (index) {
              // Calculate index into our hardcoded table with staggered offsets
              final byteOffset = (index * 3);
              final tableIndex = ((_controller.value * _waveData.length).floor() + byteOffset) % _waveData.length;
              final double waveVal = _waveData[tableIndex];
              
              // Base height scaling to keep bars varied
              final double baseFactor = 0.2 + (index % 3) * 0.1;
              final double heightFactor = (baseFactor + waveVal * 0.7).clamp(0.2, 1.0);
              
              return Container(
                width: widget.size / 5,
                height: widget.size * heightFactor,
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.7 + (waveVal * 0.3)),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
