import 'package:flutter/material.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/widgets/avatar.dart';

class SheetAction {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
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
    required List<SheetAction> items,
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
                      item.onTap();
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

  /// Lets the person pick how they show up to trustees.
  static Future<Availability?> availability(
    BuildContext context, {
    required Availability current,
  }) {
    return showModalBottomSheet<Availability>(
      context: context,
      useSafeArea: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        final scheme = theme.colorScheme;

        Widget option(Availability state) {
          final chosen = state == current;
          return ListTile(
            key: ValueKey('status:${state.name}'),
            selected: chosen,
            selectedTileColor: scheme.primary.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: SizedBox(
              width: 24,
              child: Center(child: Glyph(availability: state, size: 20)),
            ),
            title: Text(
              state.label,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(state.hint, style: theme.textTheme.bodySmall),
            trailing: AnimatedOpacity(
              opacity: chosen ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.check, color: scheme.primary),
            ),
            onTap: () => Navigator.pop(sheet, state),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: grabber(sheet)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    'Set Status',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                option(Availability.available),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Divider(color: scheme.outlineVariant),
                ),
                for (final state in Availability.values.skip(1)) option(state),
              ],
            ),
          ),
        );
      },
    );
  }
}
