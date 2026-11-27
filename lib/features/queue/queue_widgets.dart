import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';

/// Stops the running radio if there is one, otherwise starts one from [track].
Future<void> toggleRadio(
    BuildContext context, AudioPlayerService player, Track track) async {
  if (player.radioSeed != null) {
    player.stopRadio();
    AppToast.show(context, 'Radio stopped');
    return;
  }
  await startRadioWithFeedback(context, player, track);
}

/// Starts a radio from [track] and tells the user what happened, including
/// when no similar songs could be found.
Future<void> startRadioWithFeedback(
    BuildContext context, AudioPlayerService player, Track track) async {
  if (!context.read<SettingsService>().recSourceEnabled) {
    AppToast.show(
        context, 'Recommendations are turned off. Choose a source in Settings.',
        isError: true);
    return;
  }
  AppToast.show(context, 'Starting radio from "${track.title}"…');
  final queued = await player.startRadio(track);
  if (!context.mounted) return;
  AppToast.show(
    context,
    queued > 0
        ? 'Radio started · $queued songs queued'
        : 'No similar songs found for "${track.title}"',
    isError: queued == 0,
  );
}

/// Shown above the queue: the radio the user started (if any) and the
/// autoplay switch, so autoplay can be turned off right where it happens.
class QueueControls extends StatelessWidget {
  const QueueControls({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;
    final muted = isDark ? Colors.white70 : Colors.black54;
    final radio = player.radioSeed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (radio != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.radio, size: 18, color: AppTheme.primaryGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Radio · ${radio.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    player.stopRadio();
                    AppToast.show(context, 'Radio stopped');
                  },
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Autoplay similar songs',
                  style: TextStyle(color: muted)),
            ),
            Switch(
              value: settings.autoplaySimilar,
              // Without a recommendation source there is nothing to autoplay.
              onChanged:
                  settings.recSourceEnabled ? settings.setAutoplaySimilar : null,
              activeThumbColor: AppTheme.primaryGreen,
            ),
          ],
        ),
      ],
    );
  }
}

/// Label for the first track autoplay added: "Autoplay · similar to <song>",
/// or "Radio · <song>" while a radio is running.
class AutoplaySectionLabel extends StatelessWidget {
  const AutoplaySectionLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final isDark = context.watch<SettingsService>().isDarkMode;
    final radio = player.radioSeed;
    final seed = player.autoplaySeed;
    final text = radio != null
        ? 'Radio · ${radio.title}'
        : 'Autoplay · similar to ${seed?.title ?? 'your music'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Icon(radio != null ? Icons.radio : Icons.auto_awesome,
              size: 16, color: AppTheme.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain section heading used above the user's own tracks when an autoplay
/// section follows them.
class QueueSectionLabel extends StatelessWidget {
  final String text;
  const QueueSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? Colors.white70 : Colors.black54,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
