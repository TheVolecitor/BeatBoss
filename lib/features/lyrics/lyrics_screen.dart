import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../player/artwork_theme.dart';
import '../shared/marquee_text.dart';

/// Lyrics Screen - album-themed draggable lyrics card for mobile fullscreen.
class LyricsScreen extends StatelessWidget {
  const LyricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final player = context.watch<AudioPlayerService>();
    final track = player.currentTrack;
    final isDark = settings.isDarkMode;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.7, 1.0],
      builder: (context, scrollController) {
        return ArtworkTheme(
          imageUrl: track?.displayImage,
          enabled: settings.useDynamicPlayerColors,
          builder: (context, scheme) => ArtworkGradient(
            scheme: scheme,
            base: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Compact track header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                    child: Row(
                      children: [
                        if (track != null && track.displayImage.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: track.displayImage,
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                              memCacheWidth: 160,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MarqueeText(
                                track?.title ?? 'Lyrics',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (track != null)
                                MarqueeText(
                                  track.artist,
                                  style: TextStyle(
                                    color: (isDark ? Colors.white : Colors.black)
                                        .withValues(alpha: 0.6),
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.08),
                  ),
                  Expanded(
                    child: LyricsList(
                      scrollController: scrollController,
                      isDark: isDark,
                      showHeader: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class LyricsList extends StatefulWidget {
  final ScrollController? scrollController;
  final bool isDark;
  final bool showHeader;

  const LyricsList({
    this.scrollController,
    required this.isDark,
    this.showHeader = true,
    super.key,
  });

  @override
  State<LyricsList> createState() => _LyricsListState();
}

class _LyricsListState extends State<LyricsList> {
  late ScrollController _autoScrollController;
  int _prevIndex = -1;
  String? _prevTrackId;
  final Map<int, GlobalKey> _itemKeys = {};
  // ignore: unused_field
  final bool _userScrolled = false;

  @override
  void initState() {
    super.initState();
    _autoScrollController = widget.scrollController ?? ScrollController();
    _autoScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _autoScrollController.removeListener(_onScroll);
    if (widget.scrollController == null) {
      _autoScrollController.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    // If user interacts?
    // Hard to distinguish animateTo from drag.
    // We'll ignore for now.
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final track = player.currentTrack;

    if (track?.id != _prevTrackId) {
      _prevTrackId = track?.id;
      _itemKeys.clear();
      _prevIndex = -1;
    }

    // Auto-scroll logic
    if (player.currentLyricIndex != _prevIndex) {
      _prevIndex = player.currentLyricIndex;
      if (_prevIndex != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToIndex(_prevIndex);
        });
      }
    }

    return CustomScrollView(
      controller: _autoScrollController,
      slivers: [
        if (widget.showHeader)
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: widget.isDark ? Colors.white30 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Text(
                        'Lyrics',
                        style: TextStyle(
                          color: widget.isDark ? Colors.white : Colors.black,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (track != null)
                        Expanded(
                          child: Text(
                            track.title,
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  widget.isDark ? Colors.white54 : Colors.black45,
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (player.isFetchingLyrics)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGreen),
            ),
          )
        else if (player.lyrics.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No lyrics loaded. Play a track to see lyrics.',
                style: TextStyle(
                  color: widget.isDark ? Colors.white54 : Colors.black45,
                  fontSize: 16,
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final lyric = player.lyrics[index];
                final isActive = index == player.currentLyricIndex;
                final settings = context.watch<SettingsService>();
                final baseSize = settings.lyricsFontSize;
                final key = _itemKeys.putIfAbsent(index, () => GlobalKey());

                return GestureDetector(
                  key: key,
                  onTap: () => player.seekToLyric(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 16),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      textAlign: settings.lyricsCentered
                          ? TextAlign.center
                          : TextAlign.left,
                      style: TextStyle(
                        color: isActive
                            ? (widget.isDark ? Colors.white : Colors.black)
                            : (widget.isDark ? Colors.white : Colors.black)
                                .withValues(alpha: settings.lyricsDimOpacity),
                        fontSize: isActive ? baseSize + 8 : baseSize,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.w600,
                        height: 1.4,
                      ),
                      child: Text(lyric.text),
                    ),
                  ),
                );
              },
              childCount: player.lyrics.length,
            ),
          ),
        // Fill remaining space to ensure drag works on empty areas
        const SliverFillRemaining(
          hasScrollBody: false,
          child: SizedBox.shrink(),
        ),
        // Add some bottom padding
        const SliverToBoxAdapter(child: SizedBox(height: 50)),
      ],
    );
  }

  void _scrollToIndex(int index) {
    if (!mounted || !_autoScrollController.hasClients) return;

    final ctx = _itemKeys[index]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.45,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
      return;
    }

    // Fallback when target row hasn't been laid out yet in SliverList.
    final baseSize = context.read<SettingsService>().lyricsFontSize;
    final approxLineHeight = 32.0 + baseSize * 1.4;
    final headerHeight = widget.showHeader ? 90.0 : 0.0;
    final viewportHeight = _autoScrollController.position.viewportDimension;
    var target = headerHeight + (index * approxLineHeight) - viewportHeight * 0.45;
    target = target.clamp(0.0, _autoScrollController.position.maxScrollExtent);

    _autoScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }
}
