import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/models/models.dart';
import '../../core/recommendations/rec_models.dart';
import '../../core/recommendations/recommendation_service.dart';
import '../../core/recommendations/resolved_shelf.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/utils/app_toast.dart';
import '../player/player_bar.dart';
import '../shared/media_card.dart';
import '../shared/track_list_tile.dart';

/// A recommended playlist ("mix"): a collage header with Play and Shuffle,
/// and the songs below it. Songs are looked up in the addon as the screen
/// opens, so they appear one by one.
class MixScreen extends StatefulWidget {
  final RecShelf shelf;

  /// Fetches the next page of recommendations (1-based, page 1 is [shelf]).
  /// When null there is no "Load more" button.
  final Future<List<RecTrack>> Function(int page)? loadMore;

  const MixScreen({super.key, required this.shelf, this.loadMore});

  @override
  State<MixScreen> createState() => _MixScreenState();
}

class _MixScreenState extends State<MixScreen> {
  late final ResolvedShelf _resolved;
  int _page = 1;
  bool _loadingMore = false;
  bool _noMore = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _resolved = ResolvedShelf(context.read<RecommendationService>().resolver)
      ..setShelf(widget.shelf);
  }

  VoidCallback? _mixTailListener;

  @override
  void dispose() {
    if (_mixTailListener != null) {
      _resolved.removeListener(_mixTailListener!);
      _mixTailListener = null;
    }
    _resolved.dispose();
    super.dispose();
  }

  Future<void> _start({required bool shuffle, Track? from}) async {
    if (_starting) return;
    setState(() => _starting = true);
    final player = context.read<AudioPlayerService>();
    if (_mixTailListener != null) {
      _resolved.removeListener(_mixTailListener!);
      _mixTailListener = null;
    }
    try {
      final tracks =
          await _resolved.playableWhenReady(min: from == null ? 8 : 1);
      if (!mounted) return;
      if (tracks.isEmpty) {
        AppToast.show(context, 'None of these songs could be found yet',
            isError: true);
        return;
      }
      if (shuffle) {
        await player.playAllShuffled(tracks);
      } else {
        final start =
            from == null ? 0 : tracks.indexWhere((t) => t.id == from.id);
        await player.playAll(tracks, startIndex: start < 0 ? 0 : start);
      }
      if (!mounted || !_resolved.isResolving) return;
      final submitted = List<Track>.of(tracks);
      void onMoreResolved() {
        if (!mounted) {
          _resolved.removeListener(onMoreResolved);
          return;
        }
        final current = player.currentTrack;
        final queue = player.queue;
        final stillOwns = current != null &&
            submitted.any((t) => identical(t, current)) &&
            submitted.every((s) => queue.any((q) => identical(q, s)));
        if (!stillOwns) {
          _resolved.removeListener(onMoreResolved);
          if (identical(_mixTailListener, onMoreResolved)) {
            _mixTailListener = null;
          }
          return;
        }
        for (final t in _resolved.playable) {
          if (!submitted.any((s) => identical(s, t))) {
            submitted.add(t);
            player.addToQueue(t);
          }
        }
        if (!_resolved.isResolving) {
          _resolved.removeListener(onMoreResolved);
          if (identical(_mixTailListener, onMoreResolved)) {
            _mixTailListener = null;
          }
        }
      }
      _mixTailListener = onMoreResolved;
      _resolved.addListener(onMoreResolved);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _loadMore() async {
    final loader = widget.loadMore;
    if (loader == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final more = await loader(_page + 1);
      if (!mounted) return;
      final before = _resolved.items.length;
      _resolved.append(more);
      _page++;
      // Nothing new (or an empty page) means we've reached the end.
      if (more.isEmpty ||
          (_resolved.items.length == before && !_resolved.isResolving)) {
        _noMore = true;
      }
    } catch (e) {
      print('Load more failed: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 768 && size.height >= 520;

    return Scaffold(
      extendBodyBehindAppBar: !isDesktop,
      appBar: isDesktop
          ? null
          : AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: ListenableBuilder(
        listenable: _resolved,
        builder: (context, _) =>
            isDesktop ? _desktop(context) : _mobile(context),
      ),
      bottomNavigationBar: const PlayerBar(avoidBottomInset: true),
    );
  }

  // ---- Header ----

  Widget _collage(double size) {
    final covers = _resolved.covers(4);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              for (var row = 0; row < 2; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (var col = 0; col < 2; col++)
                        Expanded(
                          child: CoverArt(
                            imageUrl: row * 2 + col < covers.length
                                ? covers[row * 2 + col]
                                : null,
                            seed: '${widget.shelf.title}${row * 2 + col}',
                            cacheWidth: 300,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _starting ? null : () => _start(shuffle: false),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
              foregroundColor: scheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _starting ? null : () => _start(shuffle: true),
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('Shuffle'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleBlock(TextAlign align) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          widget.shelf.title,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        if (widget.shelf.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.shelf.subtitle!,
            textAlign: align,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  // ---- Layouts ----

  Widget _desktop(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 350,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BackButton(),
                  const Spacer(),
                  Center(child: _collage(240)),
                  const SizedBox(height: 28),
                  _titleBlock(TextAlign.center),
                  const SizedBox(height: 28),
                  _actions(),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 24, 24, 24),
              children: _rows(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobile(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
        children: [
          Center(child: _collage(220)),
          const SizedBox(height: 24),
          _titleBlock(TextAlign.center),
          const SizedBox(height: 20),
          _actions(),
          const SizedBox(height: 16),
          ..._rows(),
        ],
      ),
    );
  }

  List<Widget> _rows() {
    final items = _resolved.items;
    final playable = _resolved.playable;
    final widgets = <Widget>[];

    for (final item in items) {
      final track = item.track;
      if (track == null) {
        widgets.add(const _SkeletonRow());
        continue;
      }
      final index = playable.indexOf(track);
      widgets.add(TrackListTile(
        key: ValueKey(item.rec.key),
        track: track,
        tracks: playable,
        index: index,
        onPlay: () => _start(shuffle: false, from: track),
      ));
    }

    if (items.isEmpty && !_resolved.isResolving) {
      widgets.add(const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'None of these songs could be found with your active addon.',
            textAlign: TextAlign.center,
          ),
        ),
      ));
    }

    if (widget.loadMore != null && !_noMore) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: _loadingMore
              ? const CircularProgressIndicator()
              : OutlinedButton(
                  onPressed: _loadMore,
                  child: const Text('Load more'),
                ),
        ),
      ));
    }
    return widgets;
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget block(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Shimmer.fromColors(
        baseColor: scheme.surfaceContainerHighest,
        highlightColor: scheme.surfaceContainerHigh,
        child: Row(
          children: [
            block(50, 50),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  block(160, 14),
                  const SizedBox(height: 8),
                  block(100, 12)
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
