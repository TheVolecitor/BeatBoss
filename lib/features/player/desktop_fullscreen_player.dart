import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../lyrics/lyrics_screen.dart';

class DesktopFullscreenPlayer extends StatefulWidget {
  const DesktopFullscreenPlayer({super.key});

  @override
  State<DesktopFullscreenPlayer> createState() => _DesktopFullscreenPlayerState();
}

class _DesktopFullscreenPlayerState extends State<DesktopFullscreenPlayer> {
  int _selectedIndex = 0; // 0 = Queue, 1 = Lyrics
  double? _dragProportion;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkMode;
    final player = context.watch<AudioPlayerService>();
    final track = player.currentTrack;

    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    final screenHeight = MediaQuery.of(context).size.height;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        switch (event.logicalKey) {
          case LogicalKeyboardKey.space:
            player.togglePlayPause();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            player.nextTrack();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowLeft:
            player.previousTrack();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.escape:
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: Stack(
        children: [
          // Blurred background
          if (track.displayImage.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: track.displayImage,
                fit: BoxFit.cover,
                memCacheWidth: 400,
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.7),
              ),
            ),
          ),
          
          // Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final settings = context.watch<SettingsService>();
                final proportion = _dragProportion ?? settings.fullscreenLeftPaneProportion;
                
                return Row(
                  children: [
                    // Left Side (Big Cover Art & Info)
                    SizedBox(
                      width: constraints.maxWidth * proportion - 2, // Subtract half divider width
                      child: Padding(
                    padding: const EdgeInsets.all(48.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, size: 36),
                          color: isDark ? Colors.white : Colors.black,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(flex: 1),
                        Expanded(
                          flex: 12,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Hero(
                                tag: 'player_bar_art_${track.id}',
                                child: Container(
                                  constraints: const BoxConstraints(maxHeight: 1200, maxWidth: 1200),
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.4),
                                        blurRadius: 40,
                                        offset: const Offset(0, 20),
                                      )
                                    ],
                                    borderRadius: BorderRadius.circular(20),
                                    image: DecorationImage(
                                      image: CachedNetworkImageProvider(track.displayImage, maxWidth: 800),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(flex: 1),
                        Center(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Hero(
                                tag: 'player_bar_title_${track.id}',
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: Text(
                                    track.title,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontSize: 42,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Hero(
                                tag: 'player_bar_artist_${track.id}',
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: Text(
                                    track.artist,
                                    style: TextStyle(
                                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Player Controls
                        Column(
                          children: [
                            // Seek Bar
                            Row(
                              children: [
                                Text(
                                  _formatDuration(player.position),
                                  style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5), fontSize: 14),
                                ),
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 18.0),
                                            child: LinearProgressIndicator(
                                              value: player.bufferedSliderValue / 1000,
                                              backgroundColor: Colors.transparent,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3),
                                              ),
                                              minHeight: 4,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: AppTheme.primaryGreen,
                                          inactiveTrackColor: Colors.transparent,
                                          trackHeight: 4,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                                        ),
                                        child: Slider(
                                          value: player.sliderValue.toDouble(),
                                          min: 0,
                                          max: 1000,
                                          onChanged: (value) => player.seekToSlider(value.toInt()),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _formatDuration(player.duration),
                                  style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5), fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Buttons
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                IconButton(
                                  icon: const Icon(Icons.shuffle),
                                  iconSize: 28,
                                  color: player.shuffleEnabled ? AppTheme.primaryGreen : (isDark ? Colors.white54 : Colors.black54),
                                  onPressed: player.toggleShuffle,
                                ),
                                const SizedBox(width: 24),
                                IconButton(
                                  icon: const Icon(Icons.skip_previous),
                                  iconSize: 48,
                                  color: isDark ? Colors.white : Colors.black,
                                  onPressed: player.previousTrack,
                                ),
                                const SizedBox(width: 24),
                                InkWell(
                                  onTap: player.togglePlayPause,
                                  borderRadius: BorderRadius.circular(40),
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: const BoxDecoration(
                                      color: AppTheme.primaryGreen,
                                      shape: BoxShape.circle,
                                    ),
                                    child: player.isBuffering
                                        ? const Center(
                                            child: SizedBox(
                                              width: 32,
                                              height: 32,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                                color: Colors.black,
                                              ),
                                            ),
                                          )
                                        : Icon(
                                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                                            color: Colors.black,
                                            size: 40,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 24),
                                IconButton(
                                  icon: const Icon(Icons.skip_next),
                                  iconSize: 48,
                                  color: isDark ? Colors.white : Colors.black,
                                  onPressed: player.nextTrack,
                                ),
                                const SizedBox(width: 24),
                                IconButton(
                                  icon: Icon(player.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat),
                                  iconSize: 28,
                                  color: player.loopMode != LoopMode.off ? AppTheme.primaryGreen : (isDark ? Colors.white54 : Colors.black54),
                                  onPressed: player.toggleLoop,
                                ),
                              ],
                            ),
                            ),
                          ],
                        ),
                        const Spacer(flex: 2),
                      ],
                    ),
                  ),
                ),
                
                // Draggable Divider
                MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      final newWidth = (constraints.maxWidth * proportion) + details.delta.dx;
                      final newProportion = (newWidth / constraints.maxWidth).clamp(0.3, 0.7);
                      setState(() {
                        _dragProportion = newProportion;
                      });
                    },
                    onHorizontalDragEnd: (details) {
                      if (_dragProportion != null) {
                        context.read<SettingsService>().setFullscreenLeftPaneProportion(_dragProportion!);
                        setState(() {
                          _dragProportion = null;
                        });
                      }
                    },
                    child: Container(
                      width: 4,
                      color: Colors.transparent,
                    ),
                  ),
                ),

                // Right Side (Queue / Lyrics Switcher)
                Expanded(
                  child: Container(
                    color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.2),
                    child: Column(
                      children: [
                        // Tab Switcher
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                          child: Row(
                            children: [
                              _buildTabItem('Queue', 0, isDark),
                              const SizedBox(width: 32),
                              _buildTabItem('Lyrics', 1, isDark),
                            ],
                          ),
                        ),
                        // Tab Content
                        Expanded(
                          child: _selectedIndex == 0 
                            ? const _QueueView() 
                            : LyricsList(isDark: isDark), // Reuse LyricsList from lyrics_screen.dart
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
        ],
      ),
    ),
    );
  }

  Widget _buildTabItem(String title, int index, bool isDark) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isSelected 
                ? (isDark ? Colors.white : Colors.black) 
                : (isDark ? Colors.white54 : Colors.black54),
              fontSize: 24,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          )
        ],
      ),
    );
  }
}

// A slightly modified view of the Queue that fits into our tab space properly without the drag handles and modal heights.
class _QueueView extends StatelessWidget {
  const _QueueView();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final isDark = context.watch<SettingsService>().isDarkMode;

    if (player.internalQueue.isEmpty) {
      return Center(
        child: Text(
          'Queue is empty',
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black45,
            fontSize: 18,
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      itemCount: player.internalQueue.length,
      onReorder: (oldIndex, newIndex) {
        if (oldIndex < newIndex) {
          newIndex -= 1;
        }
        player.reorderQueue(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final track = player.internalQueue[index];
        final isPlaying = index == player.currentIndex;

        return Container(
          key: ValueKey('${track.id}_$index'),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isPlaying
                ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                : (isDark ? Colors.white10 : Colors.black12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: Icon(Icons.drag_handle, color: isDark ? Colors.white54 : Colors.black54),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: CachedNetworkImage(
                      imageUrl: track.displayImage,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      placeholder: (_, __) => Container(color: AppTheme.darkCard),
                      errorWidget: (_, __, ___) => Container(
                        color: AppTheme.darkCard,
                        child: const Icon(Icons.music_note, color: Colors.white30),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            title: Text(
              track.title,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                fontSize: 16,
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
                  color: Colors.redAccent,
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
    );
  }
}
