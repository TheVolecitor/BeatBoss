import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/artwork_palette_service.dart';

/// Gives [builder] a [ColorScheme] taken from the cover at [imageUrl]. While a
/// new cover is loading it keeps the previous colors, so the player fades from
/// one song's colors to the next instead of flashing back to the default.
class ArtworkTheme extends StatefulWidget {
  final String? imageUrl;
  final Widget Function(BuildContext context, ColorScheme scheme) builder;

  const ArtworkTheme({super.key, required this.imageUrl, required this.builder});

  @override
  State<ArtworkTheme> createState() => _ArtworkThemeState();
}

class _ArtworkThemeState extends State<ArtworkTheme> {
  ColorScheme? _scheme;
  Brightness? _brightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness != _brightness) {
      _brightness = brightness;
      _load();
    }
  }

  @override
  void didUpdateWidget(ArtworkTheme old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) _load();
  }

  Future<void> _load() async {
    final url = widget.imageUrl;
    final brightness = _brightness!;
    final scheme = await context
        .read<ArtworkPaletteService>()
        .schemeFor(url, brightness);
    // Ignore an answer for a cover that is no longer showing.
    if (!mounted || url != widget.imageUrl || brightness != _brightness) return;
    // No cover or a failed load falls back to the app colors.
    if (scheme != _scheme) setState(() => _scheme = scheme);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _scheme ?? Theme.of(context).colorScheme);
}

/// Background for the player: a gradient from the cover's container color to
/// [base]. Animates when the colors change.
class ArtworkGradient extends StatelessWidget {
  final ColorScheme scheme;
  final Color base;
  final BorderRadiusGeometry? borderRadius;

  /// Less than 1 lets what is behind the gradient show through.
  final double opacity;
  final Widget child;

  const ArtworkGradient({
    super.key,
    required this.scheme,
    required this.base,
    this.borderRadius,
    this.opacity = 1,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primaryContainer.withValues(alpha: opacity),
            base.withValues(alpha: opacity),
          ],
          stops: const [0.0, 0.75],
        ),
      ),
      child: child,
    );
  }
}
