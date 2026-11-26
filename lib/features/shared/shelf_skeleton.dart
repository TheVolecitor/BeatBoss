import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'quick_pick_tile.dart';

/// Shimmering placeholders shown while a shelf has nothing cached yet.
class ShelfSkeleton extends StatelessWidget {
  final bool _quickPicks;
  final int count;

  /// A row of card placeholders under a title bar.
  const ShelfSkeleton.cards({super.key, this.count = 6}) : _quickPicks = false;

  /// A grid of quick-pick placeholders.
  const ShelfSkeleton.quickPicks({super.key, this.count = 8})
      : _quickPicks = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget block(double w, double h, {double radius = 8}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surfaceContainerHigh,
      child: _quickPicks
          ? QuickPickGrid(
              tiles: [
                for (var i = 0; i < count; i++)
                  block(double.infinity, QuickPickTile.height),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                block(160, 22),
                const SizedBox(height: 15),
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: count,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        block(150, 150, radius: 12),
                        const SizedBox(height: 8),
                        block(110, 12),
                        const SizedBox(height: 6),
                        block(70, 10),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
