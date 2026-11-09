import 'package:flutter/material.dart';

class HorizontalScrollWrapper extends StatefulWidget {
  final double itemWidth;
  final double itemSpacing;
  final double listHeight;
  final String title;
  final TextStyle? titleStyle;
  final Widget? trailing;
  final Widget Function(BuildContext context, ScrollController controller) builder;

  const HorizontalScrollWrapper({
    super.key,
    required this.itemWidth,
    required this.itemSpacing,
    required this.listHeight,
    required this.title,
    this.titleStyle,
    this.trailing,
    required this.builder,
  });

  @override
  State<HorizontalScrollWrapper> createState() => _HorizontalScrollWrapperState();
}

class _HorizontalScrollWrapperState extends State<HorizontalScrollWrapper> {
  late final ScrollController _controller;
  bool _showLeft = false;
  bool _showRight = true;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_updateButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateButtons());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateButtons);
    _controller.dispose();
    super.dispose();
  }

  void _updateButtons() {
    if (!mounted) return;
    if (!_controller.hasClients) return;
    
    final position = _controller.position;
    final showLeft = position.pixels > 0;
    // Don't show right button if we can't scroll at all (content fits) or reached the end
    final showRight = position.maxScrollExtent > 0 && position.pixels < position.maxScrollExtent - 1;

    if (_showLeft != showLeft || _showRight != showRight) {
      setState(() {
        _showLeft = showLeft;
        _showRight = showRight;
      });
    }
  }

  void _scroll(bool right) {
    if (!_controller.hasClients) return;
    
    final position = _controller.position;
    final viewportWidth = position.viewportDimension;
    
    // Total width of one item including spacing
    final totalItemWidth = widget.itemWidth + widget.itemSpacing;
    
    // Number of fully visible items
    final visibleItems = (viewportWidth / totalItemWidth).floor();
    
    // Scroll amount: (visible items - 1) * total item width
    // Ensure we scroll at least one item
    final scrollItems = visibleItems > 1 ? visibleItems - 1 : 1;
    final scrollAmount = scrollItems * totalItemWidth;

    final targetOffset = right 
        ? position.pixels + scrollAmount 
        : position.pixels - scrollAmount;

    _controller.animateTo(
      targetOffset.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = MediaQuery.of(context).size.width > 600;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: widget.titleStyle ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                if (isDesktop && _showLeft) _buildButton(Icons.chevron_left, () => _scroll(false)),
                if (isDesktop && _showLeft && _showRight) const SizedBox(width: 8),
                if (isDesktop && _showRight) _buildButton(Icons.chevron_right, () => _scroll(true)),
                if (widget.trailing != null) ...[
                  if (isDesktop && (_showLeft || _showRight)) const SizedBox(width: 8),
                  widget.trailing!,
                ],
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: widget.listHeight,
              child: widget.builder(context, _controller),
            ),
          ],
        );
      },
    );
  }

  Widget _buildButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.2) ?? Colors.grey,
            ),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}
