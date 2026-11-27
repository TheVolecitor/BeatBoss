import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/models.dart';
import '../../core/models/addon_models.dart';
import '../../core/services/local_library_service.dart';
import '../../core/services/addon_service.dart';
import '../lyrics/lyrics_screen.dart';
import '../queue/queue_screen.dart';
import '../queue/queue_widgets.dart';
import '../shared/artist_navigation.dart';
import 'artwork_theme.dart';
import 'desktop_fullscreen_player.dart';
import 'player_seekbar.dart';
import 'now_playing_actions.dart';

/// Player Bar - bottom player controls matching original exactly
class PlayerBar extends StatefulWidget {
  /// Set when the bar is the bottom-most widget on screen (no bottom nav
  /// below it), so it stays clear of the system navigation bar.
  final bool avoidBottomInset;

  const PlayerBar({super.key, this.avoidBottomInset = false});

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
        bottom: 72, // Sit exactly flush with the 72px desktop player bar
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

    final bottomInset =
        widget.avoidBottomInset ? MediaQuery.of(context).viewPadding.bottom : 0.0;

    return Container(
      height: (isMobile ? 60 : 72) + bottomInset, // 72 on desktop to fix overflow
      padding: EdgeInsets.only(bottom: bottomInset),
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
                GestureDetector(
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const DesktopFullscreenPlayer(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          const begin = Offset(0.0, 1.0);
                          const end = Offset.zero;
                          const curve = Curves.easeInOutCubic;
                          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                          return SlideTransition(
                            position: animation.drive(tween),
                            child: child,
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 400),
                      ),
                    );
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Hero(
                      tag: 'player_bar_art_${track.id}',
                      child: _TrackArt(
                          imageUrl: track.displayImage,
                          isDownloaded: false,
                          size: 46),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push(
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => const DesktopFullscreenPlayer(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              const begin = Offset(0.0, 1.0);
                              const end = Offset.zero;
                              const curve = Curves.easeInOutCubic;
                              var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                              return SlideTransition(
                                position: animation.drive(tween),
                                child: child,
                              );
                            },
                            transitionDuration: const Duration(milliseconds: 400),
                          ),
                        );
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Hero(
                            tag: 'player_bar_title_${track.id}',
                            child: Material(
                              type: MaterialType.transparency,
                              child: Text(
                                track.title,
                                style: TextStyle(
                                    color: textColor, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          Hero(
                            tag: 'player_bar_artist_${track.id}',
                            child: Material(
                              type: MaterialType.transparency,
                              child: Text(
                                track.artist,
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
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
                  ),
                ),
                Consumer<LocalLibraryService>(
                  builder: (context, localLibrary, child) {
                    final isFav = localLibrary.isFavourite(track.id);
                    return IconButton(
                      icon:
                          Icon(isFav ? Icons.favorite : Icons.favorite_border),
                      color: isFav ? AppTheme.primaryGreen : secondaryColor,
                      iconSize: 22,
                      onPressed: () {
                        localLibrary.toggleFavourite(track,
                            addonService: context.read<AddonService>());
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      constraints: const BoxConstraints(),
                    );
                  },
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
                          decoration: BoxDecoration(
                              color: AppTheme.primaryGreen,
                              shape: BoxShape.circle),
                          child: player.isBuffering
                              ? const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.black,
                                    ),
                                  ),
                                )
                              : Icon(
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
                                      horizontal: 14.0),
                                  child: LinearProgressIndicator(
                                    value: player.bufferedSliderValue / 1000,
                                    backgroundColor: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
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
            width: 280,
            child: Padding(
              padding:
                  const EdgeInsets.only(right: 20.0), // Shift closer inwards
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (player.qualityLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _QualityBadge(
                        label: player.qualityLabel!,
                        detail: player.qualityDetail,
                        tier: player.qualityTier ?? StreamQualityTier.standard,
                        isDark: isDark,
                      ),
                    ),
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
              AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
          minHeight: 2,
        ),
        GestureDetector(
          onTap: () => _showExpandedPlayer(context),
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity! < -300) {
              // Swipe UP
              _showExpandedPlayer(context);
            } else if (details.primaryVelocity! > 300) {
              // Swipe DOWN
              player.clearQueue();
            }
          },
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
                Consumer<LocalLibraryService>(
                  builder: (context, localLibrary, child) {
                    final isFav = localLibrary.isFavourite(track.id);
                    return IconButton(
                      icon:
                          Icon(isFav ? Icons.favorite : Icons.favorite_border),
                      color: isFav
                          ? AppTheme.primaryGreen
                          : (isDark ? Colors.white54 : Colors.black45),
                      iconSize: 20,
                      onPressed: () {
                        localLibrary.toggleFavourite(track,
                            addonService: context.read<AddonService>());
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                    );
                  },
                ),
                InkWell(
                    onTap: player.togglePlayPause,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            shape: BoxShape.circle),
                        child: player.isBuffering
                            ? const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.black,
                                  ),
                                ),
                              )
                            : Icon(
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

  void _openArtist(BuildContext context, Track track) {
    final artistId = track.artistId;
    final addonId = track.addonId;
    if (artistId != null && addonId != null) {
      openArtistPage(context,
          id: artistId, addonId: addonId, name: track.artist);
    } else {
      openArtistByName(context, track.artist);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryColor = isDark ? Colors.white54 : Colors.black54;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.0,
      maxChildSize: 1.0,
      snap: true,
      builder: (context, scrollController) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final isSmallScreen = screenHeight < 700;

        // Dynamic sizes — bigger cover art in mobile fullscreen
        final artSize = (screenWidth - 40).clamp(220.0, isSmallScreen ? 280.0 : 360.0);
        final titleFontSize = isSmallScreen ? 20.0 : 24.0;
        final artistFontSize = isSmallScreen ? 14.0 : 17.0;
        final sectionSpacing = isSmallScreen ? 12.0 : 22.0;

        return Consumer<AudioPlayerService>(builder: (context, player, _) {
          final settings = context.watch<SettingsService>();
          // The sheet is opened with the track that was playing at that moment;
          // follow the player so Next/Previous update art, title and artist.
          final track = player.currentTrack ?? this.track;
          return ArtworkTheme(
            imageUrl: track.displayImage,
            builder: (context, scheme) => ArtworkGradient(
            scheme: scheme,
            base: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SingleChildScrollView(
              controller: scrollController,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: screenHeight,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      20, 14, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Top row: drag handle + 3-dot menu
                      Row(
                        children: [
                          const SizedBox(width: 48),
                          Expanded(
                            child: Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white24 : Colors.black12,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: secondaryColor,
                            ),
                            onSelected: (value) {
                              if (value == 'radio') {
                                toggleRadio(context, player, track);
                              } else if (value.startsWith('seekbar:')) {
                                settings.setSeekbarStyle(
                                    value.substring('seekbar:'.length));
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'radio',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.radio,
                                      size: 18,
                                      color: player.radioSeed != null
                                          ? AppTheme.primaryGreen
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(player.radioSeed != null
                                        ? 'Stop Radio'
                                        : 'Start Radio'),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                enabled: false,
                                child: Text('Seekbar Style',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ),
                              for (final style in const [
                                ('normal', 'Normal'),
                                ('sleek', 'Sleek'),
                                ('waveform', 'Waveform'),
                                ('heartbeat', 'Heartbeat'),
                              ])
                                PopupMenuItem(
                                  value: 'seekbar:${style.$1}',
                                  child: Row(
                                    children: [
                                      Icon(
                                        settings.seekbarStyle == style.$1
                                            ? Icons.check_rounded
                                            : Icons.circle_outlined,
                                        size: 16,
                                        color: settings.seekbarStyle == style.$1
                                            ? AppTheme.primaryGreen
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(style.$2),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),

                      // Bigger Cover Art
                      SizedBox(
                          height: artSize,
                          child: Center(
                              child: _TrackArt(
                                  imageUrl: track.displayImage,
                                  size: artSize,
                                  isDownloaded: false))),
                      SizedBox(height: sectionSpacing),

                      // Info + Addon/Quality Markers
                      Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              track.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: textColor,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold),
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _openArtist(context, track),
                            child: Text(track.artist,
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: artistFontSize,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1),
                          ),
                          if (player.providerAddonName != null ||
                              player.qualityLabel != null) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: [
                                if (player.providerAddonName != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.extension_outlined,
                                          size: 13, color: secondaryColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        player.providerAddonName!,
                                        style: TextStyle(
                                          color: secondaryColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                if (player.qualityLabel != null)
                                  _QualityBadge(
                                    label: player.qualityLabel!,
                                    detail: player.qualityDetail,
                                    tier: player.qualityTier ??
                                        StreamQualityTier.standard,
                                    isDark: isDark,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: sectionSpacing),

                      // Progress
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: PlayerSeekBar(
                              style: settings.seekbarStyle,
                              value: player.sliderValue,
                              bufferedValue: player.bufferedSliderValue,
                              seed: track.id,
                              isDark: isDark,
                              onChanged: player.seekToSlider,
                            ),
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
                                ? scheme.primary
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
                            backgroundColor: scheme.primary,
                            onPressed: player.togglePlayPause,
                            child: player.isBuffering
                                ? Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: scheme.onPrimary,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    player.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color: scheme.onPrimary,
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
                                ? scheme.primary
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
                          // Relocated Heart Button
                          Consumer<LocalLibraryService>(
                            builder: (context, localLibrary, child) {
                              final isFav = localLibrary.isFavourite(track.id);
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.black.withOpacity(0.05),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: Icon(isFav
                                      ? Icons.favorite
                                      : Icons.favorite_border),
                                  color: isFav
                                      ? scheme.primary
                                      : secondaryColor,
                                  iconSize: 32,
                                  onPressed: () {
                                    localLibrary.toggleFavourite(track,
                                        addonService:
                                            context.read<AddonService>());
                                  },
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.lyrics_outlined,
                                color: secondaryColor),
                            tooltip: 'Lyrics',
                            onPressed: () {
                              showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const LyricsScreen());
                            },
                          ),
                          GoToArtistButton(track: track, color: secondaryColor),
                          RadioButton(
                              track: track,
                              color: secondaryColor,
                              activeColor: scheme.primary),
                          IconButton(
                            icon:
                                Icon(Icons.queue_music, color: secondaryColor),
                            tooltip: 'Queue',
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
                    memCacheWidth: 600,
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

class _QualityBadge extends StatelessWidget {
  final String label;
  final String? detail;
  final StreamQualityTier tier;
  final bool isDark;

  const _QualityBadge({
    required this.label,
    this.detail,
    required this.tier,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    Color fg;
    IconData? icon;

    switch (tier) {
      case StreamQualityTier.atmos:
        fg = isDark ? const Color(0xFFB39DDB) : const Color(0xFF5E35B1);
        icon = Icons.spatial_audio_rounded;
      case StreamQualityTier.hiRes:
        fg = isDark ? const Color(0xFFFFCA28) : const Color(0xFFD97706);
        icon = Icons.high_quality_rounded;
      case StreamQualityTier.lossless:
        fg = isDark ? AppTheme.primaryGreen : const Color(0xFF1B5E20);
        icon = Icons.graphic_eq_rounded;
      case StreamQualityTier.standard:
        fg = isDark ? Colors.white54 : Colors.black54;
        icon = null;
    }

    final marker = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
        ],
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: fg,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );

    return detail != null && detail!.isNotEmpty
        ? Tooltip(message: detail!, child: marker)
        : marker;
  }
}
