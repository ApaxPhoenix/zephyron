import 'package:flutter/material.dart';

/// The outlined count bubble next to a section title, as in Trustees.
class Pill extends StatelessWidget {
  final int count;

  const Pill({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Section title used on every dashboard tab.
class Heading extends StatelessWidget {
  final String text;
  final int? count;
  final String? description;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const Heading(
    this.text, {
    super.key,
    this.count,
    this.description,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 28, 0, 10),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(text, style: theme.textTheme.titleSmall),
              if (count != null) ...[
                const SizedBox(width: 8),
                Pill(count: count!),
              ],
              const Spacer(),
              ?trailing,
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Rows sharing one rounded card, divided by hairlines.
class Group extends StatelessWidget {
  final List<Widget> children;

  /// Where the hairline starts, so it lines up with the row text.
  final double indent;

  const Group({super.key, required this.children, this.indent = 56});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) Divider(indent: indent),
            children[index],
          ],
        ],
      ),
    );
  }
}

/// Previous and next controls for a list split into pages.
class Pager extends StatelessWidget {
  final int page;
  final int pages;
  final ValueChanged<int> onChanged;

  const Pager({
    super.key,
    required this.page,
    required this.pages,
    required this.onChanged,
  });

  /// How many pages [total] items fill at [size] per page.
  static int count(int total, int size) =>
      total == 0 ? 1 : (total + size - 1) ~/ size;

  /// The items on [page] of [items], [size] at a time.
  static List<T> slice<T>(List<T> items, int page, int size) {
    final start = (page * size).clamp(0, items.length);
    final end = (start + size).clamp(0, items.length);
    return items.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            tooltip: 'Previous page',
            style: IconButton.styleFrom(
              side: BorderSide(color: scheme.outline),
            ),
            onPressed: page > 0 ? () => onChanged(page - 1) : null,
            icon: const Icon(Icons.chevron_left, size: 20),
          ),
          SizedBox(
            width: 96,
            child: Text(
              'Page ${page + 1} of $pages',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton.outlined(
            tooltip: 'Next page',
            style: IconButton.styleFrom(
              side: BorderSide(color: scheme.outline),
            ),
            onPressed: page < pages - 1 ? () => onChanged(page + 1) : null,
            icon: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Empty state for a section with nothing in it yet.
class Vacant extends StatelessWidget {
  final IconData icon;
  final String text;

  const Vacant({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            Icon(icon, size: 28, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
