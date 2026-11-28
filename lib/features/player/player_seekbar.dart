import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Interactive seekbar supporting 'normal', 'wavy' (Android Media3 squiggle),
/// 'sleek', 'waveform', 'heartbeat', and 'bars'.
class PlayerSeekBar extends StatelessWidget {
  final String style;
  final int value; // 0..1000
  final int bufferedValue; // 0..1000
  final String seed; // used for deterministic waveform bar heights
  final bool isDark;
  final bool isPlaying;
  final Color? accentColor;
  final double trackHeight;
  final double wavyAmplitude;
  final ValueChanged<int> onChanged;

  const PlayerSeekBar({
    super.key,
    required this.style,
    required this.value,
    required this.bufferedValue,
    required this.seed,
    required this.isDark,
    this.isPlaying = true,
    this.accentColor,
    this.trackHeight = 3.5,
    this.wavyAmplitude = 3.5,
    required this.onChanged,
  });

  static const List<({String id, String label})> styles = [
    (id: 'normal', label: 'Normal'),
    (id: 'wavy', label: 'Android Wavy'),
    (id: 'sleek', label: 'Sleek'),
    (id: 'waveform', label: 'Waveform'),
    (id: 'heartbeat', label: 'Heartbeat'),
    (id: 'bars', label: 'Equalizer Bars'),
  ];

  @override
  Widget build(BuildContext context) {
    final progress = (value / 1000).clamp(0.0, 1.0);
    final buffered = (bufferedValue / 1000).clamp(0.0, 1.0);
    final accent = accentColor ?? AppTheme.primaryGreen;
    final inactive =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.14);
    final bufferColor =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.28);

    switch (style) {
      case 'wavy':
        return _InteractiveTrack(
          height: 36,
          onSeek: onChanged,
          child: _WavySeekBar(
            progress: progress,
            buffered: buffered,
            isPlaying: isPlaying,
            strokeWidth: trackHeight,
            waveAmplitude: wavyAmplitude,
            activeColor: accent,
            bufferedColor: bufferColor,
            inactiveColor: inactive,
          ),
        );

      case 'bars':
        return _InteractiveTrack(
          height: 36,
          onSeek: onChanged,
          child: CustomPaint(
            size: const Size(double.infinity, 36),
            painter: _EqualizerBarsPainter(
              progress: progress,
              buffered: buffered,
              activeColor: accent,
              bufferedColor: bufferColor,
              inactiveColor: inactive,
            ),
          ),
        );

      case 'sleek':
        return _InteractiveTrack(
          height: 28,
          onSeek: onChanged,
          child: SizedBox(
            height: 28,
            child: Center(
              child: SizedBox(
                height: trackHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: inactive,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: buffered,
                      child: Container(
                        decoration: BoxDecoration(
                          color: bufferColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

      case 'waveform':
        return _InteractiveTrack(
          height: 36,
          onSeek: onChanged,
          child: CustomPaint(
            size: const Size(double.infinity, 36),
            painter: _WaveformPainter(
              progress: progress,
              buffered: buffered,
              seed: seed,
              activeColor: accent,
              bufferedColor: bufferColor,
              inactiveColor: inactive,
            ),
          ),
        );

      case 'heartbeat':
        return _InteractiveTrack(
          height: 36,
          onSeek: onChanged,
          child: CustomPaint(
            size: const Size(double.infinity, 36),
            painter: _HeartbeatPainter(
              progress: progress,
              activeColor: accent,
              inactiveColor: inactive,
            ),
          ),
        );

      case 'normal':
      default:
        return Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: buffered,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(bufferColor),
                      minHeight: trackHeight,
                    ),
                  ),
                ),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accent,
                inactiveTrackColor: inactive,
                thumbColor: accent,
                overlayColor: accent.withValues(alpha: 0.2),
                trackHeight: trackHeight,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 1000,
                onChanged: (v) => onChanged(v.toInt()),
              ),
            ),
          ],
        );
    }
  }
}

class _InteractiveTrack extends StatelessWidget {
  final double height;
  final ValueChanged<int> onSeek;
  final Widget child;

  const _InteractiveTrack({
    required this.height,
    required this.onSeek,
    required this.child,
  });

  void _seekFromDx(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return;
    final ratio = (dx / box.size.width).clamp(0.0, 1.0);
    onSeek((ratio * 1000).round());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _seekFromDx(context, d.localPosition.dx),
      onHorizontalDragStart: (d) => _seekFromDx(context, d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _seekFromDx(context, d.localPosition.dx),
      child: SizedBox(height: height, width: double.infinity, child: child),
    );
  }
}

/// Iconic Android 13+/Material 3 animated wavy squiggle seekbar.
class _WavySeekBar extends StatefulWidget {
  final double progress;
  final double buffered;
  final bool isPlaying;
  final double strokeWidth;
  final double waveAmplitude;
  final Color activeColor;
  final Color bufferedColor;
  final Color inactiveColor;

  const _WavySeekBar({
    required this.progress,
    required this.buffered,
    required this.isPlaying,
    required this.strokeWidth,
    required this.waveAmplitude,
    required this.activeColor,
    required this.bufferedColor,
    required this.inactiveColor,
  });

  @override
  State<_WavySeekBar> createState() => _WavySeekBarState();
}

class _WavySeekBarState extends State<_WavySeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isPlaying) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _WavySeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.isPlaying && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        size: const Size(double.infinity, 36),
        painter: _WavyPainter(
          progress: widget.progress,
          buffered: widget.buffered,
          phase: _ctrl.value * 2 * math.pi,
          amplitude: widget.isPlaying ? widget.waveAmplitude : 1.0,
          strokeWidth: widget.strokeWidth,
          activeColor: widget.activeColor,
          bufferedColor: widget.bufferedColor,
          inactiveColor: widget.inactiveColor,
        ),
      ),
    );
  }
}

class _WavyPainter extends CustomPainter {
  final double progress;
  final double buffered;
  final double phase;
  final double amplitude;
  final double strokeWidth;
  final Color activeColor;
  final Color bufferedColor;
  final Color inactiveColor;

  _WavyPainter({
    required this.progress,
    required this.buffered,
    required this.phase,
    required this.amplitude,
    required this.strokeWidth,
    required this.activeColor,
    required this.bufferedColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final activeX = (size.width * progress).clamp(0.0, size.width);
    final bufferedX = (size.width * buffered).clamp(0.0, size.width);

    // Straight inactive line after thumb
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = inactiveColor;
    canvas.drawLine(Offset(activeX, midY), Offset(size.width, midY), trackPaint);

    if (bufferedX > activeX) {
      canvas.drawLine(
        Offset(activeX, midY),
        Offset(bufferedX, midY),
        trackPaint..color = bufferedColor,
      );
    }

    // Squiggly sine wave up to activeX
    if (activeX > 1.0) {
      const wavelength = 26.0;
      final path = Path();
      for (double x = 0; x <= activeX; x += 2.0) {
        final y = midY +
            amplitude * math.sin((x / wavelength) * 2 * math.pi - phase);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = activeColor;
      canvas.drawPath(path, wavePaint);
    }

    // Iconic Android vertical rounded pill thumb
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(activeX, midY), width: 5, height: 18),
      const Radius.circular(3),
    );
    canvas.drawRRect(thumbRect, Paint()..color = activeColor);
  }

  @override
  bool shouldRepaint(covariant _WavyPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.strokeWidth != strokeWidth ||
      old.activeColor != activeColor;
}

class _EqualizerBarsPainter extends CustomPainter {
  final double progress;
  final double buffered;
  final Color activeColor;
  final Color bufferedColor;
  final Color inactiveColor;

  _EqualizerBarsPainter({
    required this.progress,
    required this.buffered,
    required this.activeColor,
    required this.bufferedColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const count = 36;
    final slot = size.width / count;
    final barW = math.max(2.5, slot * 0.56);
    final midY = size.height / 2;
    final activeIdx = (progress * count).floor();
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final frac = (i + 0.5) / count;
      final isHead = i == activeIdx;
      final h = isHead ? size.height * 0.78 : size.height * 0.44;
      final x = i * slot + (slot - barW) / 2;
      paint.color = frac <= progress
          ? activeColor
          : (frac <= buffered ? bufferedColor : inactiveColor);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY - h / 2, barW, h),
          Radius.circular(barW / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerBarsPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.activeColor != activeColor;
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final double buffered;
  final String seed;
  final Color activeColor;
  final Color bufferedColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.progress,
    required this.buffered,
    required this.seed,
    required this.activeColor,
    required this.bufferedColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 52;
    final slot = size.width / barCount;
    final barW = math.max(2.0, slot * 0.52);
    final midY = size.height / 2;
    var hash = seed.hashCode;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < barCount; i++) {
      hash = (hash * 1664525 + 1013904223) & 0x7fffffff;
      final norm = 0.25 + ((hash % 100) / 100.0) * 0.72;
      final h = size.height * norm;
      final x = i * slot + (slot - barW) / 2;
      final frac = (i + 0.5) / barCount;
      paint.color = frac <= progress
          ? activeColor
          : (frac <= buffered ? bufferedColor : inactiveColor);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY - h / 2, barW, h),
          Radius.circular(barW / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.seed != seed ||
      old.activeColor != activeColor;
}

class _HeartbeatPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _HeartbeatPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final amp = size.height * 0.42;
    final path = Path()..moveTo(0, midY);
    const beatWidth = 44.0;

    for (double x = 0; x < size.width; x += beatWidth) {
      final w = math.min(beatWidth, size.width - x);
      if (w < beatWidth * 0.8) {
        path.lineTo(x + w, midY);
        break;
      }
      path.lineTo(x + w * 0.25, midY);
      path.lineTo(x + w * 0.34, midY - amp * 0.35);
      path.lineTo(x + w * 0.42, midY + amp * 0.32);
      path.lineTo(x + w * 0.50, midY - amp);
      path.lineTo(x + w * 0.58, midY + amp * 0.72);
      path.lineTo(x + w * 0.68, midY);
      path.lineTo(x + w, midY);
    }

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = inactiveColor;
    canvas.drawPath(path, bgPaint);

    final activeW = size.width * progress;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, activeW, size.height));
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = activeColor;
    canvas.drawPath(path, activePaint);
    canvas.restore();

    final dotX = activeW.clamp(4.0, math.max(4.0, size.width - 4.0)).toDouble();
    canvas.drawCircle(
      Offset(dotX, size.height / 2),
      5,
      Paint()..color = activeColor,
    );
  }

  @override
  bool shouldRepaint(covariant _HeartbeatPainter old) =>
      old.progress != progress || old.activeColor != activeColor;
}
