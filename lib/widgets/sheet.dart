import 'package:flutter/material.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/widgets/avatar.dart';

class Command {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback run;

  const Command({
    required this.icon,
    required this.label,
    required this.run,
    this.destructive = false,
  });
}

class Sheets {
  static Widget grabber(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  static Future<void> actions(
    BuildContext context, {
    Widget? header,
    required List<Command> items,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      useSafeArea: true,
      builder: (sheet) {
        final scheme = Theme.of(sheet).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                grabber(sheet),
                if (header != null) ...[header, const SizedBox(height: 8)],
                for (final item in items)
                  ListTile(
                    leading: Icon(
                      item.icon,
                      color: item.destructive ? scheme.error : scheme.onSurface,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        color: item.destructive
                            ? scheme.error
                            : scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () {
                      Navigator.pop(sheet);
                      item.run();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String action = 'Delete',
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (sheet) {
        final scheme = Theme.of(sheet).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                grabber(sheet),
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () => Navigator.pop(sheet, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(sheet, true),
                        child: Text(action),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  /// A titled list of choices, each in its own padded, rounded row.
  ///
  /// [split] draws a hairline after that many options.
  static Future<T?> pick<T>(
    BuildContext context, {
    required String title,
    required String subtitle,
    required T current,
    required List<Choice<T>> options,
    int? split,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        final scheme = theme.colorScheme;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: grabber(sheet)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                  child: Text(subtitle, style: theme.textTheme.bodySmall),
                ),
                for (var index = 0; index < options.length; index++) ...[
                  if (index > 0 && index == split)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Divider(),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Material(
                      color: (options[index].value == current)
                          ? scheme.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: (options[index].value == current)
                              ? scheme.primary.withValues(alpha: 0.35)
                              : Colors.transparent,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: options[index].key,
                        onTap: () => Navigator.pop(sheet, options[index].value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Center(child: options[index].leading),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      options[index].label,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    if (options[index].hint != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        options[index].hint!,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              AnimatedOpacity(
                                opacity: (options[index].value == current)
                                    ? 1
                                    : 0,
                                duration: const Duration(milliseconds: 150),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 22,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Lets the person pick how they show up to trustees.
  static Future<Availability?> availability(
    BuildContext context, {
    required Availability current,
  }) {
    return pick(
      context,
      title: 'Set Status',
      subtitle: 'Choose how you show up to your trustees.',
      current: current,
      split: 1,
      options: [
        for (final state in Availability.values)
          Choice(
            value: state,
            label: state.label,
            hint: state.hint,
            leading: Glyph(availability: state, size: 20),
            key: ValueKey('status:${state.name}'),
          ),
      ],
    );
  }

  /// Lets the person pick how long messages in a chat last.
  static Future<Fuse?> fuse(BuildContext context, {required Fuse current}) {
    final scheme = Theme.of(context).colorScheme;
    return pick(
      context,
      title: 'Disappearing Messages',
      subtitle:
          'New messages in this chat are deleted from both phones once the timer runs out. Your trustee sees the change.',
      current: current,
      split: 1,
      options: [
        for (final choice in Fuse.values)
          Choice(
            value: choice,
            label: choice.label,
            hint: choice == Fuse.off
                ? 'Keep messages until you delete them'
                : null,
            leading: Icon(
              choice == Fuse.off ? Icons.all_inclusive : Icons.timer_outlined,
              size: 20,
              color: choice == Fuse.off
                  ? scheme.onSurfaceVariant
                  : scheme.primary,
            ),
            key: ValueKey('fuse:${choice.name}'),
          ),
      ],
    );
  }
}

/// One row in [Sheets.pick].
class Choice<T> {
  final T value;
  final String label;
  final String? hint;
  final Widget leading;
  final Key? key;

  const Choice({
    required this.value,
    required this.label,
    required this.leading,
    this.hint,
    this.key,
  });
}
