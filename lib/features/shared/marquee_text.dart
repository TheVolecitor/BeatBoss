import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/settings_service.dart';

/// Displays [text] on a single line, smoothly marquee-scrolling when it
/// overflows and [SettingsService.enableMarquee] is enabled: holds for 3s,
/// scrolls to the end, returns to start, and repeats.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final Duration pauseDuration;
  final double velocity;

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.pauseDuration = const Duration(seconds: 3),
    this.velocity = 42.0,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _scroll = ScrollController();
  int _runToken = 0;
  double _lastMaxExtent = 0;

  @override
  void dispose() {
    _runToken++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _runToken++;
      _lastMaxExtent = 0;
      if (_scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    }
  }

  void _scheduleLoop(double maxExtent) {
    if ((maxExtent - _lastMaxExtent).abs() < 1.0 && _runToken > 0) return;
    _lastMaxExtent = maxExtent;
    final token = ++_runToken;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop(token, maxExtent));
  }

  Future<void> _loop(int token, double maxExtent) async {
    while (mounted && token == _runToken && maxExtent > 1.0) {
      await Future.delayed(widget.pauseDuration);
      if (!mounted || token != _runToken || !_scroll.hasClients) return;

      final scrollMs =
          ((maxExtent / widget.velocity) * 1000).round().clamp(1200, 12000);
      await _scroll.animateTo(
        maxExtent,
        duration: Duration(milliseconds: scrollMs),
        curve: Curves.linear,
      );
      if (!mounted || token != _runToken || !_scroll.hasClients) return;

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || token != _runToken || !_scroll.hasClients) return;

      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool enabled = true;
    try {
      enabled = context.watch<SettingsService>().enableMarquee;
    } catch (_) {
      // Allow usage in tests without SettingsService in the tree.
    }

    if (!enabled) {
      _runToken++;
      _lastMaxExtent = 0;
      return Text(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        if (!maxW.isFinite || maxW <= 0) {
          return Text(
            widget.text,
            style: widget.style,
            textAlign: widget.textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        final effectiveStyle = DefaultTextStyle.of(context).style.merge(widget.style);
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final overflow = painter.width - maxW;
        if (overflow <= 2.0) {
          _runToken++;
          _lastMaxExtent = 0;
          return Text(
            widget.text,
            style: widget.style,
            textAlign: widget.textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        _scheduleLoop(overflow + 8.0);
        return SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        );
      },
    );
  }
}

