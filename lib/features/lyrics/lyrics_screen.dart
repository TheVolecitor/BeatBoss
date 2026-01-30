import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';

/// Lyrics Screen - scrollable lyrics display matching original
class LyricsScreen extends StatelessWidget {
  const LyricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.7, 1.0],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: LyricsList(
            scrollController: scrollController,
            isDark: isDark,
          ),
        );
      },
    );
  }
}

class LyricsList extends StatefulWidget {
  final ScrollController? scrollController;
  final bool isDark;

  const LyricsList({this.scrollController, required this.isDark, super.key});

  @override
  State<LyricsList> createState() => _LyricsListState();
}

class _LyricsListState extends State<LyricsList> {
  late ScrollController _autoScrollController;
  int _prevIndex = -1;
  // ignore: unused_field
  bool _userScrolled = false;

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
          const SliverFillRemaining(
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

                return GestureDetector(
                  onTap: () => player.seekToLyric(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Text(
                      lyric.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isActive
                            ? (widget.isDark ? Colors.white : Colors.black)
                            : (widget.isDark ? Colors.white30 : Colors.black38),
                        fontSize: isActive ? 24 : 18,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                      ),
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
    if (!_autoScrollController.hasClients) return;

    // Estimate height: header ~100 + lines
    // Better: index * 60 (approx line height).
    // Center it in viewport.

    // Header height approx 80-100.
    const double headerHeight = 100.0;
    const double approxLineHeight = 50.0;

    double offset = headerHeight + (index * approxLineHeight);

    double viewportHeight = _autoScrollController.position.viewportDimension;
    double centeredOffset = offset - viewportHeight / 2;

    if (centeredOffset < 0) centeredOffset = 0;
    if (centeredOffset > _autoScrollController.position.maxScrollExtent) {
      centeredOffset = _autoScrollController.position.maxScrollExtent;
    }

    _autoScrollController.animateTo(
      centeredOffset,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
  }
}
