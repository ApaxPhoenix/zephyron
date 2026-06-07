import 'package:flutter/material.dart';

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
}
