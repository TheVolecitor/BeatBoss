import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';

/// Queue Screen - display and manage play queue matching original
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white30 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Current Queue',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: player.clearQueue,
                  child: const Text('Clear Queue'),
                ),
              ],
            ),
          ),

          // Queue content
          Expanded(
            child: player.internalQueue.isEmpty
                ? Center(
                    child: Text(
                      'Queue is empty',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    itemCount: player.internalQueue.length,
                    itemBuilder: (context, index) {
                      final track = player.internalQueue[index];
                      final isPlaying = index == player.currentIndex;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isPlaying
                              ? AppTheme.primaryGreen.withOpacity(0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 50,
                              height: 50,
                              child: CachedNetworkImage(
                                imageUrl: track.displayImage,
                                fit: BoxFit.cover,
                                placeholder: (_, __) =>
                                    Container(color: AppTheme.darkCard),
                                errorWidget: (_, __, ___) => Container(
                                  color: AppTheme.darkCard,
                                  child: const Icon(Icons.music_note,
                                      color: Colors.white30),
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            track.title,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: isPlaying
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.artist,
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                            maxLines: 1,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: Colors.red,
                                onPressed: () => player.removeFromQueue(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                color: AppTheme.primaryGreen,
                                onPressed: () => player.playFromQueue(index),
                              ),
                            ],
                          ),
                          onTap: () => player.playFromQueue(index),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
