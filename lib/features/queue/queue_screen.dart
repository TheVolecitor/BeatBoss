import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import 'queue_list.dart';
import 'queue_widgets.dart';

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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
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
                  onPressed: player.clearQueueKeepCurrent,
                  child: const Text('Clear Queue'),
                ),
              ],
            ),
          ),

          // Radio label and the autoplay switch
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: QueueControls(),
          ),

          // Queue content
          Expanded(
            child: QueueList(
              padding: EdgeInsets.fromLTRB(
                  15, 0, 15, MediaQuery.of(context).viewPadding.bottom),
            ),
          ),
        ],
      ),
    );
  }
}
