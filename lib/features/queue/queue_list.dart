import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/audio_player_service.dart';
import 'queue_widgets.dart';

/// The play queue as a reorderable list: drag the handle to move a song,
/// swipe a row to remove it. Songs autoplay added sit under their own label.
/// Shared by the mobile queue sheet and the desktop fullscreen player.
class QueueList extends StatelessWidget {
  /// Larger rows and a play button, for the desktop player.
  final bool large;
  final EdgeInsets padding;

  /// Shown above the rows, scrolling with them.
  final Widget? header;

  const QueueList({
    super.key,
    this.large = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 15),
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final scheme = Theme.of(context).colorScheme;
    final queue = player.internalQueue;

    if (queue.isEmpty) {
      return Center(
        child: Text(
          'Queue is empty',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: large ? 18 : null,
          ),
        ),
      );
    }

    final autoplayStart = player.autoplayStartIndex;
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: padding,
      header: header,
      itemCount: queue.length,
      onReorderItem: player.reorderQueue,
      itemBuilder: (context, index) {
        final track = queue[index];
        final isPlaying = index == player.currentIndex;
        final gap = large ? 12.0 : 8.0;

        final tile = Container(
          decoration: BoxDecoration(
            color: isPlaying
                ? scheme.primary.withValues(alpha: 0.2)
                : (large ? scheme.onSurface.withValues(alpha: 0.08) : null),
            borderRadius: BorderRadius.circular(large ? 16 : 12),
          ),
          child: Material(
        type: MaterialType.transparency,
        child: ListTile(
            contentPadding: EdgeInsets.symmetric(
                horizontal: large ? 16 : 8, vertical: large ? 8 : 4),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                    child: Icon(Icons.drag_handle,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: large ? 60 : 50,
                    height: large ? 60 : 50,
                    child: CachedNetworkImage(
                      imageUrl: track.displayImage,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      placeholder: (_, __) =>
                          Container(color: scheme.surfaceContainerHighest),
                      errorWidget: (_, __, ___) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.music_note,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            title: Text(
              track.title,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                fontSize: large ? 16 : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              track.artist,
              style: TextStyle(color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  color: scheme.error,
                  tooltip: 'Remove from queue',
                  onPressed: () => player.removeFromQueue(index),
                ),
                if (large)
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    color: scheme.primary,
                    tooltip: 'Play',
                    onPressed: () => player.playFromQueue(index),
                  ),
              ],
            ),
            onTap: () => player.playFromQueue(index),
          ),
      ),
        );

        // The playing song can't be swiped away: removing it would skip it.
        final row = isPlaying
            ? tile
            : Dismissible(
                key: ValueKey('dismiss_${track.id}_$index'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => player.removeFromQueue(index),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(large ? 16 : 12),
                  ),
                  child: Icon(Icons.delete_outline,
                      color: scheme.onErrorContainer),
                ),
                child: tile,
              );

        // Section labels travel with the first row of their section.
        return KeyedSubtree(
          key: ValueKey('${track.id}_$index'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (index == 0 && autoplayStart != null)
                const QueueSectionLabel('Your queue'),
              if (index == autoplayStart) const AutoplaySectionLabel(),
              Padding(padding: EdgeInsets.only(bottom: gap), child: row),
            ],
          ),
        );
      },
    );
  }
}
