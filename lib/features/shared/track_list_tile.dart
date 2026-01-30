import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/models/models.dart';

/// Reusable Track List Tile - used across search, library, favorites
class TrackListTile extends StatelessWidget {
  final Track track;
  final List<Track> tracks;
  final int index;
  final bool isFavorite;
  final String? libraryId;
  final VoidCallback? onRemove;

  const TrackListTile({
    super.key,
    required this.track,
    required this.tracks,
    required this.index,
    this.libraryId,
    this.onRemove,
    this.isFavorite = false,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.read<AudioPlayerService>();
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        leading: _buildLeading(track),
        title: Row(
          children: [
            Expanded(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            if (track.isHiRes) ...[
              const SizedBox(width: 6),
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
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play Button
            IconButton(
              icon: const Icon(Icons.play_circle_fill,
                  color: AppTheme.primaryGreen),
              onPressed: () => player.playSingleTrack(track),
              tooltip: 'Play',
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
                    value: isFavorite ? 'unlike' : 'like',
                    child: Text(isFavorite ? 'Unlike (Remove)' : 'Like')),
                if (onRemove != null)
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove from Library',
                        style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ],
        ),
        onTap: () => player.playSingleTrack(track),
      ),
    );
  }

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
          final api = context.read<DabApiService>();
          final scaffoldMessenger = ScaffoldMessenger.of(context);

          // Allow immediate feedback?
          // Better to show loading if possible, but for now just start async
          final url = await api.getStreamUrl(track.id);
          if (url != null && context.mounted) {
            downloadManager.downloadTrack(
              trackId: track.id,
              streamUrl: url,
              title: track.title,
              artist: track.artist,
            );
          } else if (context.mounted) {
            scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text('Failed to get download URL')));
          }
        },
        tooltip: 'Download',
      );
    }
  }

  // ... (helper methods)

  void _handleMenuAction(BuildContext context, String action) {
    final player = context.read<AudioPlayerService>();
    final api = context.read<DabApiService>();

    switch (action) {
      case 'add_library':
        _showLibraryPicker(context);
        break;
      case 'add_queue':
        player.addToQueue(track);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${track.title}" to queue')),
        );
        break;
      case 'play_next':
        player.playNext(track);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Will play "${track.title}" next')),
        );
        break;
      case 'like':
        api.addFavorite(track).then((success) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(success ? 'Added to Liked Songs' : 'Failed to add')),
            );
          }
        });
        break;
      case 'unlike':
        api.removeFavorite(track.id).then((success) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(success
                      ? 'Removed from Liked Songs'
                      : 'Failed to remove')),
            );
            // Optional: Request refresh of parent if needed, handled by parent state usually
            if (success)
              onRemove
                  ?.call(); // onRemove usually for library, but can reuse for favorites refresh
          }
        });
        break;
      case 'remove':
        onRemove?.call();
        break;
    }
  }

  void _showLibraryPicker(BuildContext context) async {
    final api = context.read<DabApiService>();
    final libraries = await api.getLibraries();

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
            if (libraries.isEmpty)
              const Text('No libraries found. Create one first!')
            else
              ...libraries.map((lib) => ListTile(
                    leading: const Icon(Icons.library_music,
                        color: AppTheme.primaryGreen),
                    title: Text(lib.name),
                    onTap: () async {
                      final success =
                          await api.addTrackToLibrary(lib.id, track);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(success
                                  ? 'Added to ${lib.name}'
                                  : 'Failed to add')),
                        );
                      }
                    },
                  )),
          ],
        ),
      ),
    );
  }
}
