import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/models.dart';
import '../../../core/recommendations/rec_models.dart';
import '../../../core/recommendations/recommendation_service.dart';
import '../../../core/recommendations/resolved_shelf.dart';
import '../../../core/services/audio_player_service.dart';
import '../../../core/utils/app_toast.dart';
import '../../mix/mix_screen.dart';
import '../../queue/queue_widgets.dart';
import '../../shared/media_card.dart';
import '../../shared/shelf_section.dart';
import '../../shared/shelf_skeleton.dart';
import '../../shared/track_menu.dart';

const double kCardRowHeight = 205;

/// Plays [shelf]'s songs as one queue, starting at [track].
void playFromShelf(BuildContext context, ResolvedShelf shelf, Track track) {
  final tracks = shelf.playable;
  final start = tracks.indexWhere((t) => t.id == track.id);
  if (start < 0) return;
  context.read<AudioPlayerService>().playAll(tracks, startIndex: start);
}

/// Opens the full list for [shelf].
void openMix(BuildContext context, ResolvedShelf shelf,
    {Future<List<RecTrack>> Function(int page)? loadMore}) {
  final data = shelf.shelf;
  if (data == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(
        builder: (_) => MixScreen(shelf: data, loadMore: loadMore)),
  );
}

/// One card per entry of [shelf]: playable ones are tappable, ones still being
/// looked up show their recommended title greyed out.
List<Widget> trackCards(BuildContext context, ResolvedShelf shelf) {
  return [
    for (final item in shelf.items)
      if (item.track case final track?)
        MediaCard(
          key: ValueKey(item.rec.key),
          imageUrl: track.albumCover ?? item.rec.imageUrl,
          title: track.title,
          subtitle: track.artist,
          onTap: () => playFromShelf(context, shelf, track),
          menu: TrackMenuButton(track: track),
        )
      else
        Opacity(
          key: ValueKey(item.rec.key),
          opacity: 0.5,
          child: MediaCard(
            imageUrl: item.rec.imageUrl,
            title: item.rec.title,
            subtitle: item.rec.artist,
          ),
        ),
  ];
}

/// A row of track cards for [shelf]. Shows a skeleton while the shelf has no
/// data and [loading], and nothing when it stays empty.
class TrackShelfSection extends StatelessWidget {
  final ResolvedShelf shelf;
  final bool loading;

  /// Overrides the shelf's own title.
  final String? title;
  final Future<List<RecTrack>> Function(int page)? loadMore;

  const TrackShelfSection({
    super.key,
    required this.shelf,
    required this.loading,
    this.title,
    this.loadMore,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: shelf,
      builder: (context, _) {
        if (!shelf.hasData) {
          return loading
              ? const ShelfSkeleton.cards()
              : const SizedBox.shrink();
        }
        final cards = trackCards(context, shelf);
        if (cards.isEmpty && !shelf.isResolving) return const SizedBox.shrink();
        return ShelfSection(
          title: title ?? shelf.title,
          subtitle: shelf.subtitle,
          height: kCardRowHeight,
          onSeeAll: () => openMix(context, shelf, loadMore: loadMore),
          children: cards,
        );
      },
    );
  }
}

/// "Fans also like <artist>": round artist cards. Tapping one starts a radio
/// from that artist's first playable top track.
class FansSection extends StatelessWidget {
  final RecShelf shelf;
  const FansSection({super.key, required this.shelf});

  Future<void> _radio(BuildContext context, String artist) async {
    final recs = context.read<RecommendationService>();
    final player = context.read<AudioPlayerService>();
    final track = await recs.firstPlayableTopTrack(artist);
    if (!context.mounted) return;
    if (track == null) {
      AppToast.show(context, 'Couldn\'t find songs by $artist', isError: true);
      return;
    }
    await startRadioWithFeedback(context, player, track);
  }

  @override
  Widget build(BuildContext context) {
    return ShelfSection(
      title: shelf.title,
      height: kCardRowHeight,
      children: [
        for (final artist in shelf.artists)
          MediaCard(
            key: ValueKey(artist.name),
            imageUrl: artist.imageUrl,
            title: artist.name,
            subtitle: 'Artist radio',
            circle: true,
            onTap: () => _radio(context, artist.name),
          ),
      ],
    );
  }
}
