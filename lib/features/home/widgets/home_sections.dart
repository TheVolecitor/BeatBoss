import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/models.dart';
import '../../../core/recommendations/recommendation_service.dart';
import '../../../core/recommendations/resolved_shelf.dart';
import '../../../core/recommendations/track_matching.dart';
import '../../../core/services/addon_service.dart';
import '../../../core/services/audio_player_service.dart';
import '../../search/search_screen.dart';
import '../../shared/addon_detail_screen.dart';
import '../../shared/media_card.dart';
import '../../shared/mix_card.dart';
import '../../shared/quick_pick_tile.dart';
import '../../shared/shelf_section.dart';
import '../../shared/shelf_skeleton.dart';
import '../../shared/track_menu.dart';
import '../home_controller.dart';
import 'shelf_cards.dart';

Widget _title(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
    );

/// Up to 8 songs to start with: the last few played, then recommendations
/// (or charts when there is no personal source). Tapping plays the grid.
class QuickPicksSection extends StatelessWidget {
  final HomeController controller;
  final List<Track> recent;

  const QuickPicksSection(
      {super.key, required this.controller, required this.recent});

  @override
  Widget build(BuildContext context) {
    final source =
        controller.personal ? controller.recommended : controller.charts;
    final current =
        context.select<AudioPlayerService, String?>((p) => p.currentTrack?.id);

    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final seen = <String>{};
        final picks = <Track>[
          for (final t in [...recent.take(4), ...source.playable])
            if (seen.add(matchKey(t.artist, t.title))) t,
        ].take(8).toList();

        if (picks.isEmpty) {
          if (!controller.loading || !controller.sourceEnabled) {
            return const SizedBox.shrink();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title('Quick picks'),
              const ShelfSkeleton.quickPicks(),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Quick picks'),
            QuickPickGrid(
              tiles: [
                for (var i = 0; i < picks.length; i++)
                  QuickPickTile(
                    title: picks[i].title,
                    imageUrl: picks[i].albumCover,
                    playing: picks[i].id == current,
                    onTap: () => context
                        .read<AudioPlayerService>()
                        .playAll(picks, startIndex: i),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// "Made for you": the personal mixes as collage cards.
class MadeForYouSection extends StatelessWidget {
  final HomeController controller;
  const MadeForYouSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final shelves = [
      controller.recommended,
      controller.mix,
      controller.library,
      ...controller.artistMixes,
    ];

    return ListenableBuilder(
      listenable: Listenable.merge(shelves),
      builder: (context, _) {
        final shown = shelves.where((s) => s.hasData).toList();
        if (shown.isEmpty) {
          return controller.loading
              ? const ShelfSkeleton.cards()
              : const SizedBox.shrink();
        }
        return ShelfSection(
          title: 'Made for you',
          height: 215,
          itemWidth: MixCard.width,
          children: [
            for (final shelf in shown)
              MixCard(
                key: ValueKey(shelf.shelf?.id),
                title: shelf.title,
                subtitle: shelf.subtitle,
                covers: shelf.covers(4),
                onTap: () => openMix(context, shelf),
                onPlay: () => _play(context, shelf),
              ),
          ],
        );
      },
    );
  }

  Future<void> _play(BuildContext context, ResolvedShelf shelf) async {
    final player = context.read<AudioPlayerService>();
    final tracks = await shelf.playableWhenReady(min: 1);
    if (tracks.isEmpty) return;
    await player.playAll(tracks);
  }
}

/// The active addon's own catalog: songs, albums and playlists.
class AddonCatalogSection extends StatelessWidget {
  final HomeController controller;
  const AddonCatalogSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final tracks = controller.catalogTracks;
    final albums = controller.catalogAlbums;
    final playlists = controller.catalogPlaylists;
    final addonName =
        context.read<AddonService>().activeAddon?.name ?? 'your addon';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tracks.isNotEmpty) ...[
          ShelfSection(
            title: 'From $addonName',
            height: kCardRowHeight,
            children: [
              for (var i = 0; i < tracks.length; i++)
                MediaCard(
                  key: ValueKey('catalog-${tracks[i].id}'),
                  imageUrl: tracks[i].albumCover,
                  title: tracks[i].title,
                  subtitle: tracks[i].artist,
                  onTap: () => context
                      .read<AudioPlayerService>()
                      .playAll(tracks, startIndex: i),
                  menu: TrackMenuButton(track: tracks[i]),
                ),
            ],
          ),
          const SizedBox(height: 28),
        ],
        if (albums.isNotEmpty) ...[
          ShelfSection(
            title: 'Albums',
            height: kCardRowHeight,
            children: [
              for (final album in albums)
                MediaCard(
                  key: ValueKey('catalog-album-${album.id}'),
                  imageUrl: album.artworkURL,
                  title: album.title,
                  subtitle: album.artist,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddonDetailScreen(
                        id: album.id,
                        type: AddonDetailType.album,
                        addonId: album.addonId,
                        initialTitle: album.title,
                        initialArtwork: album.artworkURL,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
        ],
        if (playlists.isNotEmpty) ...[
          ShelfSection(
            title: 'Playlists',
            height: kCardRowHeight,
            children: [
              for (final playlist in playlists)
                MediaCard(
                  key: ValueKey('catalog-playlist-${playlist.id}'),
                  imageUrl: playlist.artworkURL,
                  title: playlist.title,
                  subtitle: playlist.creator ??
                      (playlist.trackCount != null
                          ? '${playlist.trackCount} tracks'
                          : null),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddonDetailScreen(
                        id: playlist.id,
                        type: AddonDetailType.playlist,
                        addonId: playlist.addonId,
                        initialTitle: playlist.title,
                        initialArtwork: playlist.artworkURL,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
        ],
      ],
    );
  }
}

/// Recently played songs as cards.
class RecentlyPlayedSection extends StatelessWidget {
  final List<Track> recent;
  const RecentlyPlayedSection({super.key, required this.recent});

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) return const SizedBox.shrink();
    return ShelfSection(
      title: 'Recently played',
      height: kCardRowHeight,
      children: [
        for (final track in recent)
          MediaCard(
            key: ValueKey('recent-${track.id}'),
            imageUrl: track.albumCover,
            title: track.title,
            subtitle: track.artist,
            onTap: () =>
                context.read<AudioPlayerService>().playSingleTrack(track),
            menu: TrackMenuButton(track: track),
          ),
      ],
    );
  }
}

/// What's popular right now, with rank badges, timeframe selector (ListenBrainz),
/// and "Load more" in its full list.
class ChartsSection extends StatelessWidget {
  final HomeController controller;
  const ChartsSection({super.key, required this.controller});

  static const _ranges = [
    ('week', 'This week'),
    ('month', 'This month'),
    ('all_time', 'All time'),
  ];

  @override
  Widget build(BuildContext context) {
    final shelfWidget = TrackShelfSection(
      shelf: controller.charts,
      loading: controller.loading && controller.sourceEnabled,
      loadMore: context.read<RecommendationService>().moreCharts,
    );

    if (!controller.supportsChartRanges) return shelfWidget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        shelfWidget,
        if (controller.charts.hasData) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in _ranges)
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: controller.chartRange == value,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => controller.setChartRange(value),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Genre shelves, shown when there is no personal source.
class TagSections extends StatelessWidget {
  final HomeController controller;
  const TagSections({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.personal || !controller.sourceEnabled) {
      return const SizedBox.shrink();
    }
    final recs = context.read<RecommendationService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tag in kLoggedOutTags)
          if (controller.tags[tag] case final shelf?)
            Padding(
              padding: const EdgeInsets.only(top: 28),
              child: TrackShelfSection(
                shelf: shelf,
                loading: controller.loading,
                loadMore: (page) => recs.moreTagTracks(tag, page),
              ),
            ),
      ],
    );
  }
}
