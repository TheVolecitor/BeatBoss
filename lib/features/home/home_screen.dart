import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/recommendations/recommendation_service.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/history_service.dart';
import '../../core/services/last_fm_service.dart';
import '../../core/services/listenbrainz_service.dart';
import '../../core/services/settings_service.dart';
import 'home_controller.dart';
import 'widgets/home_header.dart';
import 'widgets/home_sections.dart';
import 'widgets/shelf_cards.dart';

const _gap = SizedBox(height: 28);

/// Home: quick picks, personal mixes and shelves of recommendations, all
/// shown from the cache first and refreshed in the background.
class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const HomeScreen({super.key, this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  late final HomeController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = HomeController(
      recs: context.read<RecommendationService>(),
      settings: context.read<SettingsService>(),
      lastFm: context.read<LastFmService>(),
      listenBrainz: context.read<ListenBrainzService>(),
      addons: context.read<AddonService>(),
      history: context.read<HistoryService>(),
    );
    // Show cached shelves right away; the refresh runs after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.start();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int tab) => widget.onNavigate?.call(tab);

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final history = context.watch<HistoryService>();
    context.watch<LastFmService>();
    context.watch<ListenBrainzService>();
    final recent = history.recentlyPlayed.take(10).toList();

    return RefreshIndicator(
      onRefresh: () => _controller.refresh(force: true),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          final loggedOut = !c.personal;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const HomeHeader(),
                    if (loggedOut &&
                        c.sourceEnabled &&
                        !c.recs.active.isLoggedIn) ...[
                      const SizedBox(height: 20),
                      ConnectBanner(
                        providerName: c.recs.active.displayName,
                        onConnect: () => _goTo(2),
                      ),
                    ],
                    const SizedBox(height: 24),
                    QuickPicksSection(controller: c, recent: recent),
                    if (c.sourceEnabled) ...[
                      _gap,
                      if (loggedOut) ...[
                        ChartsSection(controller: c),
                        _gap,
                      ],
                      MadeForYouSection(controller: c),
                      _gap,
                      for (final shelf in c.because) ...[
                        TrackShelfSection(shelf: shelf, loading: false),
                        _gap,
                      ],
                      if (c.fans case final fans? when !fans.isEmpty) ...[
                        FansSection(shelf: fans),
                        _gap,
                      ],
                    ],
                    RecentlyPlayedSection(recent: recent),
                    if (recent.isNotEmpty) _gap,
                    AddonCatalogSection(controller: c),
                    if (c.sourceEnabled && !loggedOut)
                      ChartsSection(controller: c),
                    TagSections(controller: c),
                    if (!c.hasAnyContent && recent.isEmpty && !c.loading)
                      _EmptyState(sourceEnabled: c.sourceEnabled),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool sourceEnabled;
  const _EmptyState({required this.sourceEnabled});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        children: [
          Icon(Icons.music_note, size: 80, color: muted.withValues(alpha: 0.5)),
          const SizedBox(height: 20),
          Text('Start playing music!',
              style: TextStyle(color: muted, fontSize: 18)),
          if (!sourceEnabled) ...[
            const SizedBox(height: 8),
            Text('Recommendations are turned off in Settings.',
                style: TextStyle(color: muted)),
          ],
        ],
      ),
    );
  }
}
