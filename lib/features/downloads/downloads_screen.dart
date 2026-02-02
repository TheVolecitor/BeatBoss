import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../features/shared/track_list_tile.dart';

/// Downloads Screen for offline listening
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch settings to auto-rebuild when downloads change
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    // Get list of tracks with metadata
    final tracks = settings.getDownloadedTracksList();

    return Scaffold(
      backgroundColor: Colors.transparent, // Handled by AppShell
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.download_done,
                    size: 32,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  const SizedBox(width: 15),
                  Text(
                    'Downloads',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const Spacer(),
                  // Play All Button (if tracks exist)
                  if (tracks.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () {
                        final player = context.read<AudioPlayerService>();
                        player.playAll(tracks);
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play All'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.black,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Stats Row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              child: FutureBuilder<int>(
                future: settings.getStorageSize(),
                builder: (context, snapshot) {
                  final sizeBytes = snapshot.data ?? 0;
                  final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
                  return Text(
                    '${tracks.length} songs • $sizeMB MB',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  );
                },
              ),
            ),
          ),

          // Track List
          if (tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off,
                        size: 64,
                        color: isDark ? Colors.white24 : Colors.black26),
                    const SizedBox(height: 15),
                    Text(
                      'No downloaded songs yet',
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 16),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = tracks[index];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    child: TrackListTile(
                      track: track,
                      tracks: tracks,
                      index: index,
                      removeLabel: 'Delete Download',
                      onRemove: () async {
                        // Prompt delete? Or just delete?
                        // For better UX, usually just delete or simple confirm.
                        // TrackListTile 'remove' option is generic, but here implies delete.
                        // But reusing TrackListTile means 'Remove from Library'.
                        // TrackListTile doesn't expose 'delete download' directly in menu unless we modify it,
                        // BUT `downloadTrack` button changes to 'Downloaded'.

                        // Here we want to allow deleting from this list.
                        // TrackListTile shows 'Remove from Library' if onRemove is passed.
                        // We can map onRemove to deleteDownload.

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Deleting download...')),
                        );
                        final dm = context.read<DownloadManagerService>();
                        await dm.deleteDownload(track.id);
                      },
                    ),
                  );
                },
                childCount: tracks.length,
              ),
            ),

          // Bottom padding for player bar
          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ),
    );
  }
}
