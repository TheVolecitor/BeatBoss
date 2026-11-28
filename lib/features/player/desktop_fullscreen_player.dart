import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/models/addon_models.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/youtube_music_addon_handler.dart';
import '../../core/services/ytmusic_innertube.dart';
import '../lyrics/lyrics_screen.dart';
import '../queue/queue_list.dart';
import 'artwork_theme.dart';
import 'now_playing_actions.dart';
import '../queue/queue_widgets.dart';
import '../shared/marquee_text.dart';
import 'player_seekbar.dart';

class DesktopFullscreenPlayer extends StatefulWidget {
  const DesktopFullscreenPlayer({super.key});

  @override
  State<DesktopFullscreenPlayer> createState() => _DesktopFullscreenPlayerState();
}

class _DesktopFullscreenPlayerState extends State<DesktopFullscreenPlayer> {
  int _selectedIndex = 0; // 0 = Queue, 1 = Lyrics
  double? _dragProportion;
  String? _hdTrackId;
  String? _hdArtworkUrl;

  void _ensureFullResArtwork(String trackId, String? addonId) {
    if (_hdTrackId == trackId) return;
    _hdTrackId = trackId;
    _hdArtworkUrl = null;
    if (addonId != YouTubeMusicAddonHandler.addonId) return;
    YtMusicInnerTube().getTrackArtwork(trackId).then((url) {
      if (!mounted || _hdTrackId != trackId || url == null || url.isEmpty) {
        return;
      }
      setState(() => _hdArtworkUrl = url);
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;
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

    _ensureFullResArtwork(track.id, track.addonId);
    final displayArt = (_hdTrackId == track.id && _hdArtworkUrl != null)
        ? _hdArtworkUrl!
        : track.displayImage;


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
      body: ArtworkTheme(
        imageUrl: displayArt,
        enabled: settings.useDynamicPlayerColors,
        builder: (context, scheme) => Stack(
        children: [
          // Blurred background
          if (settings.playerShowBgArt && displayArt.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: displayArt,
                fit: BoxFit.cover,
                memCacheWidth: 400,
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: settings.playerBgBlur,
                sigmaY: settings.playerBgBlur,
              ),
              child: ArtworkGradient(
                scheme: scheme,
                base: isDark ? Colors.black : Colors.white,
                opacity: settings.playerGradientOpacity,
                child: const SizedBox.expand(),
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
                    padding: const EdgeInsets.fromLTRB(32, 20, 32, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down, size: 36),
                              color: isDark ? Colors.white : Colors.black,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert_rounded,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                              onSelected: (value) {
                                if (value == 'artist') {
                                  openArtistForTrack(context, track);
                                } else if (value == 'radio') {
                                  toggleRadio(context, player, track);
                                } else if (value.startsWith('seekbar:')) {
                                  settings.setSeekbarStyle(
                                      value.substring('seekbar:'.length));
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'artist',
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_outline, size: 18),
                                      SizedBox(width: 10),
                                      Text('Go to Artist'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'radio',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.radio,
                                        size: 18,
                                        color: player.radioSeed != null
                                            ? scheme.primary
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
                                for (final style in PlayerSeekBar.styles)
                                  PopupMenuItem(
                                    value: 'seekbar:${style.id}',
                                    child: Row(
                                      children: [
                                        Icon(
                                          settings.seekbarStyle == style.id
                                              ? Icons.check_rounded
                                              : Icons.circle_outlined,
                                          size: 16,
                                          color: settings.seekbarStyle == style.id
                                              ? scheme.primary
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(style.label),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          flex: 16,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Hero(
                                tag: 'player_bar_art_${track.id}',
                                child: Container(
                                  constraints: const BoxConstraints(maxHeight: 1200, maxWidth: 1200),
                                  decoration: BoxDecoration(
                                    boxShadow: settings.playerArtShadow
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.4),
                                              blurRadius: 40,
                                              offset: const Offset(0, 20),
                                            )
                                          ]
                                        : null,
                                    borderRadius: BorderRadius.circular(settings.playerArtRadius),
                                    image: DecorationImage(
                                      image: CachedNetworkImageProvider(displayArt, maxWidth: 1200),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Hero(
                                tag: 'player_bar_title_${track.id}',
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: MarqueeText(
                                    track.title,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontSize: 38,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => openArtistForTrack(context, track),
                                  child: Hero(
                                    tag: 'player_bar_artist_${track.id}',
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: MarqueeText(
                                        track.artist,
                                        style: TextStyle(
                                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                                          fontSize: 21,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (settings.showQualityBadges &&
                                  (player.providerAddonName != null ||
                                      player.qualityLabel != null)) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    if (player.providerAddonName != null)
                                      _FullscreenBadge(
                                        icon: Icons.extension_outlined,
                                        label: player.providerAddonName!,
                                        fg: isDark ? Colors.white70 : Colors.black54,
                                        bg: (isDark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.08),
                                      ),
                                    if (player.qualityLabel != null)
                                      _FullscreenQualityBadge(
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
                        ),
                        const SizedBox(height: 22),
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
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: PlayerSeekBar(
                                      style: settings.seekbarStyle,
                                      value: player.sliderValue,
                                      bufferedValue: player.bufferedSliderValue,
                                      seed: track.id,
                                      isDark: isDark,
                                      isPlaying: player.isPlaying,
                                      accentColor: scheme.primary,
                                      trackHeight: settings.seekbarHeight,
                                      wavyAmplitude: settings.wavyAmplitude,
                                      onChanged: player.seekToSlider,
                                    ),
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
                                  color: player.shuffleEnabled ? scheme.primary : (isDark ? Colors.white54 : Colors.black54),
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
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: player.isBuffering
                                        ? Center(
                                            child: SizedBox(
                                              width: 32,
                                              height: 32,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                                color: scheme.onPrimary,
                                              ),
                                            ),
                                          )
                                        : Icon(
                                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                                            color: scheme.onPrimary,
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
                                  color: player.loopMode != LoopMode.off ? scheme.primary : (isDark ? Colors.white54 : Colors.black54),
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
                              ? const QueueList(
                                  large: true,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  header: Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: QueueControls(),
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 0, 24, 24),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: (isDark
                                              ? Colors.white
                                              : Colors.black)
                                          .withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: (isDark
                                                ? Colors.white
                                                : Colors.black)
                                            .withValues(alpha: 0.06),
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: LyricsList(
                                        isDark: isDark,
                                        showHeader: false,
                                      ),
                                    ),
                                  ),
                                ),
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

class _FullscreenBadge extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color fg;
  final Color bg;

  const _FullscreenBadge({
    this.icon,
    required this.label,
    required this.fg,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenQualityBadge extends StatelessWidget {
  final String label;
  final String? detail;
  final StreamQualityTier tier;
  final bool isDark;

  const _FullscreenQualityBadge({
    required this.label,
    this.detail,
    required this.tier,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData? icon;

    switch (tier) {
      case StreamQualityTier.atmos:
        bg = Colors.transparent;
        fg = isDark ? const Color(0xFFB39DDB) : const Color(0xFF5E35B1);
        icon = Icons.spatial_audio_rounded;
      case StreamQualityTier.hiRes:
        bg = Colors.transparent;
        fg = isDark ? const Color(0xFFFFCA28) : const Color(0xFFD97706);
        icon = Icons.high_quality_rounded;
      case StreamQualityTier.lossless:
        bg = Colors.transparent;
        fg = isDark ? AppTheme.primaryGreen : const Color(0xFF1B5E20);
        icon = Icons.graphic_eq_rounded;
      case StreamQualityTier.standard:
        bg = Colors.transparent;
        fg = isDark ? Colors.white60 : Colors.black54;
        icon = null;
    }

    final badge = _FullscreenBadge(
      icon: icon,
      label: label.toUpperCase(),
      fg: fg,
      bg: bg,
    );
    return detail != null && detail!.isNotEmpty
        ? Tooltip(message: detail!, child: badge)
        : badge;
  }
}
