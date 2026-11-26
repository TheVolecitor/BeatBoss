import 'package:flutter/material.dart';

import 'horizontal_scroll_wrapper.dart';

/// A titled, horizontally scrolling row of cards, with an optional "See all".
class ShelfSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final List<Widget> children;

  /// Height of the row. Must fit the tallest child.
  final double height;
  final double itemWidth;
  final double spacing;

  const ShelfSection({
    super.key,
    required this.title,
    this.subtitle,
    this.onSeeAll,
    required this.children,
    this.height = 210,
    this.itemWidth = 150,
    this.spacing = 14,
  });

  @override
  Widget build(BuildContext context) {
    return HorizontalScrollWrapper(
      title: title,
      subtitle: subtitle,
      titleStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      itemWidth: itemWidth,
      itemSpacing: spacing,
      listHeight: height,
      trailing: onSeeAll == null
          ? null
          : TextButton(onPressed: onSeeAll, child: const Text('See all')),
      builder: (context, controller) => ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => SizedBox(width: spacing),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}
