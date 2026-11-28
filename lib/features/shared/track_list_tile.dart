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
import 'marquee_text.dart';
import 'track_menu.dart';

/// Reusable Track List Tile - used across search, library, favourites
class TrackListTile extends StatelessWidget {
  final Track track;
  final List<Track> tracks;
  final int index;
  final String? libraryId;
  final VoidCallback? onRemove;

  /// Replaces what tapping the row (or its play button) does when this track
  /// isn't the current one. By default it plays just this track.
  final VoidCallback? onPlay;

  const TrackListTile({
    super.key,
    required this.track,
    required this.tracks,
    required this.index,
    this.libraryId,
    this.onRemove,
    this.onPlay,
    this.removeLabel = 'Remove from Library',
    this.showInfoText = false,
  });

  final String removeLabel;
  final bool showInfoText;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final settings = context.watch<SettingsService>();
    final localLibrary = context.watch<LocalLibraryService>();
    final isDark = settings.isDarkMode;
    
    final isCurrentTrack = player.currentTrack?.id == track.id;
    final isPlaying = isCurrentTrack && player.isPlaying;

    return Container(
      margin: EdgeInsets.symmetric(vertical: settings.compactTrackList ? 2 : 4),
      decoration: BoxDecoration(
        color: isCurrentTrack 
          ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05))
          : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
        borderRadius: BorderRadius.circular(settings.cardRadius),
        border: isCurrentTrack 
          ? Border.all(color: AppTheme.primaryGreen.withOpacity(0.3), width: 1)
          : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        dense: settings.compactTrackList,
        contentPadding: EdgeInsets.symmetric(
            horizontal: 12, vertical: settings.compactTrackList ? 0 : 4),
        leading: settings.showTrackArtInLists
            ? Stack(
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
              )
            : (isPlaying
                ? const SizedBox(
                    width: 28,
                    child: Center(
                      child: _MusicVisualizer(
                          color: Colors.white, size: 20),
                    ),
                  )
                : null),
        title: Row(
          children: [
            Expanded(
              child: MarqueeText(
                track.title,
                style: TextStyle(
                  fontWeight: isCurrentTrack ? FontWeight.bold : FontWeight.w600,
                  color: isCurrentTrack ? AppTheme.primaryGreen : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ),
            if (settings.showQualityBadges && track.isHiRes) ...[
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
        subtitle: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: MarqueeText(
                track.artist,
                style: TextStyle(
                  color: isCurrentTrack ? AppTheme.primaryGreen.withOpacity(0.7) : (isDark ? Colors.white54 : Colors.black54),
                ),
              ),
            ),
            if (showInfoText && track.infoText != null && track.infoText!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    track.infoText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
              ),
            ],
          ],
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
                  (onPlay ?? () => player.playSingleTrack(track))();
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
                ...trackMenuItems(includeDownload: false),
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
            (onPlay ?? () => player.playSingleTrack(track))();
          }
        },
      ),
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
                memCacheWidth: 200,
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
        icon: Icon(Icons.check_circle, color: AppTheme.primaryGreen),
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
                  AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
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
    if (handleTrackMenuAction(context, track, action)) return;
    final localLibrary = context.read<LocalLibraryService>();

    switch (action) {
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
