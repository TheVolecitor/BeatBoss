import 'package:flutter/material.dart';

import 'media_card.dart';

/// Number of quick-pick columns for a given screen width.
int quickPickColumns(double width) {
  if (width < 768) return 2;
  if (width < 1200) return 3;
  return 4;
}

/// A compact row: small art and a title, filled with the surface colour.
class QuickPickTile extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final bool playing;
  final VoidCallback? onTap;

  const QuickPickTile({
    super.key,
    required this.title,
    this.imageUrl,
    this.playing = false,
    this.onTap,
  });

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              SizedBox(
                width: height,
                height: height,
                child: CoverArt(
                    imageUrl: imageUrl,
                    seed: title,
                    cacheWidth: 150,
                    iconSize: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: playing ? scheme.primary : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// [tiles] in a grid of [quickPickColumns] columns, each [QuickPickTile.height]
/// tall.
class QuickPickGrid extends StatelessWidget {
  final List<Widget> tiles;
  const QuickPickGrid({super.key, required this.tiles});

  static const double spacing = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = quickPickColumns(MediaQuery.of(context).size.width);
      final tileWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
        ],
      );
    });
  }
}
