import 'package:flutter/material.dart';

import 'media_card.dart';

/// A "made for you" card: a 2x2 collage of covers, the title over the art and
/// a round play button.
class MixCard extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Cover URLs to collage (the first four are used). Missing ones get a
  /// gradient placeholder.
  final List<String?> covers;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  const MixCard({
    super.key,
    required this.title,
    this.subtitle,
    this.covers = const [],
    this.onTap,
    this.onPlay,
  });

  static const double width = 170;

  String? _cover(int i) => i < covers.length ? covers[i] : null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Column(
                      children: [
                        for (var row = 0; row < 2; row++)
                          Expanded(
                            child: Row(
                              children: [
                                for (var col = 0; col < 2; col++)
                                  Expanded(
                                    child: CoverArt(
                                      imageUrl: _cover(row * 2 + col),
                                      seed: '$title${row * 2 + col}',
                                      cacheWidth: 200,
                                      iconSize: 24,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC000000)],
                          stops: [0.4, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 54,
                      bottom: 10,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                    if (onPlay != null)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Material(
                          color: scheme.primary,
                          shape: const CircleBorder(),
                          elevation: 3,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onPlay,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(Icons.play_arrow_rounded,
                                  size: 24, color: scheme.onPrimary),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
