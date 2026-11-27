import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/stream_cache_service.dart';
import '../../core/utils/app_toast.dart';
import '../shared/track_list_tile.dart';

String _formatBytes(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) {
    return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / mb).toStringAsFixed(1)} MB';
}

/// The songs the player has cached while you listened. Only those songs are
/// listed, and playing one plays through the list.
class CacheScreen extends StatelessWidget {
  const CacheScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<StreamCacheService>();
    final enabled =
        context.select<SettingsService, bool>((s) => s.localCacheEnabled);
    final scheme = Theme.of(context).colorScheme;
    final tracks = cache.cachedTracks;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${tracks.length} songs • ${_formatBytes(cache.usedBytes)}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (tracks.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () =>
                          context.read<AudioPlayerService>().playAll(tracks),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play All'),
                    ),
                ],
              ),
            ),
          ),
          if (!enabled)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  'Caching is turned off in Settings, so these songs stream again when played.',
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storage_outlined,
                        size: 64,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    const SizedBox(height: 15),
                    Text('No cached songs yet',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 16)),
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
                      key: ValueKey(StreamCacheService.keyFor(track)),
                      track: track,
                      tracks: tracks,
                      index: index,
                      removeLabel: 'Remove from Cache',
                      onRemove: () {
                        if (!cache.remove(track)) {
                          AppToast.show(
                            context,
                            'Cannot remove track while it is playing',
                            isError: true,
                          );
                        }
                      },
                      onPlay: () => context
                          .read<AudioPlayerService>()
                          .playAll(tracks, startIndex: index),
                    ),
                  );
                },
                childCount: tracks.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
