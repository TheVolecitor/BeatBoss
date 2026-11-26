import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A pair of colours picked from [seed], so the same title always gets the
/// same placeholder.
List<Color> placeholderColors(String seed) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  return [
    HSLColor.fromAHSL(1, hue, 0.45, 0.32).toColor(),
    HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, 0.22).toColor(),
  ];
}

/// Cover art, or a gradient with a note icon when there is no image (or it
/// fails to load).
class CoverArt extends StatelessWidget {
  final String? imageUrl;
  final String seed;
  final int cacheWidth;
  final double iconSize;

  const CoverArt({
    super.key,
    required this.imageUrl,
    required this.seed,
    this.cacheWidth = 300,
    this.iconSize = 40,
  });

  Widget _placeholder() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: placeholderColors(seed),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note,
            size: iconSize, color: Colors.white.withValues(alpha: 0.6)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: cacheWidth,
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }
}

/// Square (or round, for artists) art with a title and subtitle below it.
class MediaCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final bool circle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Overflow menu drawn over the top-right corner of the art.
  final Widget? menu;

  const MediaCard({
    super.key,
    this.imageUrl,
    required this.title,
    this.subtitle,
    this.circle = false,
    this.onTap,
    this.onLongPress,
    this.menu,
  });

  static const double width = 150;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(circle ? width : 12);

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment:
              circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: radius,
                        child: CoverArt(imageUrl: imageUrl, seed: title),
                      ),
                    ),
                  ),
                  if (menu != null)
                    Positioned(
                        top: 5,
                        right: 5,
                        child:
                            Material(color: Colors.transparent, child: menu)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: circle ? TextAlign.center : TextAlign.start,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
