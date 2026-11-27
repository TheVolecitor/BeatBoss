import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Interactive seekbar supporting 'normal', 'sleek', 'waveform', and 'heartbeat'.
class PlayerSeekBar extends StatelessWidget {
  final String style;
  final int value; // 0..1000
  final int bufferedValue; // 0..1000
  final String seed; // used for deterministic waveform bar heights
  final bool isDark;
  final ValueChanged<int> onChanged;

  const PlayerSeekBar({
    super.key,
    required this.style,
    required this.value,
    required this.bufferedValue,
    required this.seed,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (value / 1000).clamp(0.0, 1.0);
    final buffered = (bufferedValue / 1000).clamp(0.0, 1.0);
    final accent = AppTheme.primaryGreen;
    final inactive =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.14);
    final bufferColor =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.28);

    switch (style) {
      case 'sleek':
        return _InteractiveTrack(
          height: 28,
          onSeek: onChanged,
          child: SizedBox(
            height: 28,
            child: Center(
              child: SizedBox(
                height: 3,
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
                  padding: const EdgeInsets.symmetric(horizontal: 18.0),
                  child: LinearProgressIndicator(
                    value: buffered,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(bufferColor),
                    minHeight: 4,
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
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: value.toDouble().clamp(0.0, 1000.0),
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

  void _handle(BuildContext context, Offset localPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return;
    final ratio = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
    onSeek((ratio * 1000).round());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _handle(context, d.localPosition),
      onHorizontalDragUpdate: (d) => _handle(context, d.localPosition),
      child: SizedBox(height: height, width: double.infinity, child: child),
    );
  }
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
    const barCount = 48;
    final step = size.width / barCount;
    final barWidth = (step * 0.56).clamp(2.0, 5.0);
    final midY = size.height / 2;
    var hash = seed.hashCode;

    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < barCount; i++) {
      hash = (hash * 1103515245 + 12345) & 0x7fffffff;
      final norm = 0.22 + ((hash % 78) / 100.0);
      final h = norm * (size.height - 6);
      final x = i * step + (step - barWidth) / 2;
      final barPos = (i + 0.5) / barCount;
      if (barPos <= progress) {
        paint.color = activeColor;
      } else if (barPos <= buffered) {
        paint.color = bufferedColor;
      } else {
        paint.color = inactiveColor;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x + barWidth / 2, midY), width: barWidth, height: h),
          const Radius.circular(2),
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

  Path _buildPath(Size size) {
    final path = Path();
    final midY = size.height / 2;
    final amp = (size.height / 2) - 4;
    const cycles = 7;
    final cycleW = size.width / cycles;
    path.moveTo(0, midY);
    for (var c = 0; c < cycles; c++) {
      final x0 = c * cycleW;
      path.lineTo(x0 + cycleW * 0.28, midY);
      path.lineTo(x0 + cycleW * 0.36, midY - amp * 0.25);
      path.lineTo(x0 + cycleW * 0.44, midY + amp * 0.3);
      path.lineTo(x0 + cycleW * 0.52, midY - amp * 0.95);
      path.lineTo(x0 + cycleW * 0.60, midY + amp * 0.65);
      path.lineTo(x0 + cycleW * 0.68, midY);
      path.lineTo(x0 + cycleW, midY);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = inactiveColor;
    canvas.drawPath(path, basePaint);

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

