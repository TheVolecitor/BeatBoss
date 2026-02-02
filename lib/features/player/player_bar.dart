import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/models.dart';
import '../lyrics/lyrics_screen.dart';
import '../queue/queue_screen.dart';

/// Player Bar - bottom player controls matching original exactly
class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key});

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  OverlayEntry? _lyricsOverlay;

  void _toggleLyrics(BuildContext context, bool isDark) {
    if (_lyricsOverlay != null) {
      _removeLyricsOverlay();
    } else {
      _showLyricsOverlay(context, isDark);
    }
  }

  void _removeLyricsOverlay() {
    _lyricsOverlay?.remove();
    _lyricsOverlay = null;
  }

  void _showLyricsOverlay(BuildContext context, bool isDark) {
    final overlay = Overlay.of(context);

    _lyricsOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        bottom: 84, // Sit exactly above the player bar
        child: Material(
          color: (isDark ? Colors.black : Colors.white).withOpacity(0.9),
          child: LyricsList(isDark: isDark), // Reusing the refactored widget
        ),
      ),
    );

    overlay.insert(_lyricsOverlay!);
  }

  @override
  void dispose() {
    _removeLyricsOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;
    final track = player.currentTrack;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    if (track == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: isMobile ? 60 : 72, // Increased slightly to 72 to fix overflow
      decoration: BoxDecoration(
        color:
            (isDark ? AppTheme.darkCard : AppTheme.lightCard).withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: isMobile
          ? _MobilePlayerBar(track: track, player: player, isDark: isDark)
          : _DesktopPlayerBar(
              track: track,
              player: player,
              isDark: isDark,
              onLyricsTap: () => _toggleLyrics(context, isDark),
            ),
    );
  }
}

class _DesktopPlayerBar extends StatelessWidget {
  final Track track;
  final AudioPlayerService player;
  final bool isDark;
  final VoidCallback onLyricsTap;

  const _DesktopPlayerBar({
    required this.track,
    required this.player,
    required this.isDark,
    required this.onLyricsTap,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryColor = isDark ? Colors.white30 : Colors.black38;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        children: [
          // Left: Track Info (Fixed Width)
          SizedBox(
            width: 260,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TrackArt(
                    imageUrl: track.displayImage,
                    isDownloaded: false,
                    size: 46),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: TextStyle(
                            color: textColor, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track.artist,
                        style: TextStyle(color: secondaryColor, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (track.isHiRes)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            track.audioQuality!.displayText,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Center: Controls (Expanded to fill middle)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Control buttons
                Padding(
                  padding: const EdgeInsets.only(
                      top: 6, bottom: 2), // Adjusted for vertical center
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shuffle),
                        iconSize: 20,
                        color: player.shuffleEnabled
                            ? AppTheme.primaryGreen
                            : secondaryColor,
                        onPressed: player.toggleShuffle,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 15),
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        iconSize: 28,
                        color: textColor,
                        onPressed: player.previousTrack,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 15),
                      InkWell(
                        onTap: player.togglePlayPause,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                              color: AppTheme.primaryGreen,
                              shape: BoxShape.circle),
                          child: Icon(
                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        iconSize: 28,
                        color: textColor,
                        onPressed: player.nextTrack,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 15),
                      IconButton(
                        icon: Icon(
                          player.loopMode == LoopMode.one
                              ? Icons.repeat_one
                              : Icons.repeat,
                        ),
                        iconSize: 20,
                        color: player.loopMode != LoopMode.off
                            ? AppTheme.primaryGreen
                            : secondaryColor,
                        onPressed: player.toggleLoop,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // Seek slider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(player.position),
                        style: TextStyle(color: secondaryColor, fontSize: 11),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6.0),
                                  child: LinearProgressIndicator(
                                    value: player.bufferedSliderValue / 1000,
                                    backgroundColor: isDark
                                        ? Colors.white10
                                        : Colors.black12,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      (isDark ? Colors.white : Colors.black)
                                          .withOpacity(0.3),
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
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                              ),
                              child: Slider(
                                value: player.sliderValue.toDouble(),
                                min: 0,
                                max: 1000,
                                onChanged: (value) =>
                                    player.seekToSlider(value.toInt()),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDuration(player.duration),
                        style: TextStyle(color: secondaryColor, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Right: Controls (Fixed Width to match Left)
          SizedBox(
            width: 260,
            child: Padding(
              padding:
                  const EdgeInsets.only(right: 20.0), // Shift closer inwards
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.lyrics_outlined),
                    color: secondaryColor,
                    onPressed: onLyricsTap,
                    iconSize: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music),
                    color: secondaryColor,
                    onPressed: () => _showQueue(context),
                    iconSize: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                  _VolumeButton(player: player, secondaryColor: secondaryColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QueueScreen(),
    );
  }
}

class _VolumeButton extends StatefulWidget {
  final AudioPlayerService player;
  final Color secondaryColor;

  const _VolumeButton({required this.player, required this.secondaryColor});

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _toggleVolumeSlider() {
    if (_overlayEntry != null) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 160,
        height: 50,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(-60, -60), // Position above and slightly left
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).cardColor,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 8),
                const Icon(Icons.volume_down, size: 20),
                Expanded(
                  child: StatefulBuilder(builder: (context, setState) {
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        trackHeight: 2,
                      ),
                      child: Slider(
                        value: widget.player.volume,
                        onChanged: (value) {
                          widget.player.setVolume(value);
                          setState(() {});
                        },
                      ),
                    );
                  }),
                ),
                const Icon(Icons.volume_up, size: 20),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        icon:
            Icon(widget.player.volume > 0 ? Icons.volume_up : Icons.volume_off),
        iconSize: 20,
        color: widget.secondaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: _toggleVolumeSlider,
      ),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }
}

class _MobilePlayerBar extends StatelessWidget {
  final Track track;
  final AudioPlayerService player;
  final bool isDark;

  const _MobilePlayerBar({
    required this.track,
    required this.player,
    required this.isDark,
  });

  @override
  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress bar at top of mini player
        LinearProgressIndicator(
          value: player.sliderValue / 1000,
          backgroundColor: Colors.transparent,
          valueColor:
              const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
          minHeight: 2,
        ),
        GestureDetector(
          onTap: () => _showExpandedPlayer(context),
          child: Container(
            color: Colors.transparent, // Ensure hit test works
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                _TrackArt(
                    imageUrl: track.displayImage,
                    size: 44,
                    isDownloaded: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(track.title,
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(track.artist,
                          style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                              fontSize: 11),
                          maxLines: 1),
                    ],
                  ),
                ),
                InkWell(
                    onTap: player.togglePlayPause,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                            color: AppTheme.primaryGreen,
                            shape: BoxShape.circle),
                        child: Icon(
                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 22))),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  color: textColor,
                  onPressed: player.nextTrack,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showExpandedPlayer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true, // Ensure it covers app bar
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _ExpandedMobilePlayer(player: player, track: track, isDark: isDark),
    );
  }
}

class _ExpandedMobilePlayer extends StatelessWidget {
  final AudioPlayerService player;
  final Track track;
  final bool isDark;

  const _ExpandedMobilePlayer({
    required this.player,
    required this.track,
    required this.isDark,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryColor = isDark ? Colors.white54 : Colors.black54;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.0, // Allows dismissing by dragging down
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.9, 1.0],
      builder: (context, scrollController) {
        return Consumer<AudioPlayerService>(builder: (context, player, _) {
          return Container(
            decoration: BoxDecoration(
              color:
                  isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white24 : Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Art
                      SizedBox(
                          height: 300,
                          child: Center(
                              child: _TrackArt(
                                  imageUrl: track.displayImage,
                                  size: 280,
                                  isDownloaded: false))),
                      const SizedBox(height: 20),

                      // Info
                      Column(
                        children: [
                          Text(track.title,
                              style: TextStyle(
                                  color: textColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Text(track.artist,
                              style: TextStyle(
                                  color: secondaryColor, fontSize: 18),
                              textAlign: TextAlign.center,
                              maxLines: 1),
                        ],
                      ),
                      const SizedBox(height: 30),

                      // Progress
                      Column(
                        children: [
                          Stack(
                            children: [
                              // Buffered Indicator
                              Positioned.fill(
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal:
                                            24.0), // Slider internal padding default is around 24
                                    child: LinearProgressIndicator(
                                      value: player.bufferedSliderValue / 1000,
                                      backgroundColor: isDark
                                          ? Colors.white10
                                          : Colors.black12,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        (isDark ? Colors.white : Colors.black)
                                            .withOpacity(0.3),
                                      ),
                                      minHeight: 4,
                                    ),
                                  ),
                                ),
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  inactiveTrackColor: Colors.transparent,
                                ),
                                child: Slider(
                                  value: player.sliderValue.toDouble(),
                                  min: 0,
                                  max: 1000,
                                  activeColor: AppTheme.primaryGreen,
                                  onChanged: (v) =>
                                      player.seekToSlider(v.toInt()),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(player.position),
                                    style: TextStyle(
                                        color: secondaryColor, fontSize: 12)),
                                Text(_formatDuration(player.duration),
                                    style: TextStyle(
                                        color: secondaryColor, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Controls with Loop/Shuffle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.shuffle),
                            iconSize: 28, // Added size
                            color: player.shuffleEnabled
                                ? AppTheme.primaryGreen
                                : secondaryColor,
                            onPressed: player.toggleShuffle,
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous,
                                size: 42), // Increased
                            color: textColor,
                            onPressed: player.previousTrack,
                          ),
                          FloatingActionButton(
                            heroTag: 'play_pause_fab', // Unique tag
                            backgroundColor: AppTheme.primaryGreen,
                            onPressed: player.togglePlayPause,
                            child: Icon(
                                player.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.black,
                                size: 42), // Increased
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next,
                                size: 42), // Increased
                            color: textColor,
                            onPressed: player.nextTrack,
                          ),
                          IconButton(
                            icon: Icon(player.loopMode == LoopMode.one
                                ? Icons.repeat_one
                                : Icons.repeat),
                            iconSize: 28, // Added size
                            color: player.loopMode != LoopMode.off
                                ? AppTheme.primaryGreen
                                : secondaryColor,
                            onPressed: player.toggleLoop,
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),

                      // Bottom Actions (Lyrics, Queue)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton.icon(
                            icon: Icon(Icons.lyrics_outlined,
                                color: secondaryColor),
                            label: Text('Lyrics',
                                style: TextStyle(color: secondaryColor)),
                            onPressed: () {
                              showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const LyricsScreen());
                            },
                          ),
                          TextButton.icon(
                            icon:
                                Icon(Icons.queue_music, color: secondaryColor),
                            label: Text('Queue',
                                style: TextStyle(color: secondaryColor)),
                            onPressed: () {
                              showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const QueueScreen());
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
  }
}

class _TrackArt extends StatelessWidget {
  final String imageUrl;
  final double size;
  final bool isDownloaded;

  const _TrackArt({
    required this.imageUrl,
    this.size = 55,
    required this.isDownloaded,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppTheme.darkCard,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppTheme.darkCard),
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.music_note, color: Colors.white30),
                  )
                : const Icon(Icons.music_note, color: Colors.white30),
          ),
        ),
        if (isDownloaded)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check, size: 12, color: Colors.black),
            ),
          ),
      ],
    );
  }
}
