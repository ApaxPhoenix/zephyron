import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:zephyron/models/location.dart';

class DropdownField extends StatefulWidget {
  final TextEditingController controller;
  final Future<List<Location>> Function(String query) search;
  final void Function(Location selected) select;
  final InputDecoration decoration;

  const DropdownField({
    super.key,
    required this.controller,
    required this.search,
    required this.select,
    this.decoration = const InputDecoration(),
  });

  @override
  State<DropdownField> createState() => DropdownFieldState();
}

class DropdownFieldState extends State<DropdownField>
    with SingleTickerProviderStateMixin {
  final link = LayerLink();
  final focus = FocusNode();

  OverlayEntry? entry;
  List<Location> items = [];
  bool active = false;
  Timer? timer;

  late final AnimationController controller;
  late final Animation<double> fade;
  late final Animation<Offset> slide;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    fade = CurvedAnimation(parent: controller, curve: Curves.easeOut);

    slide = Tween<Offset>(
      begin: const Offset(0.0, -0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));

    focus.addListener(() {
      if (!focus.hasFocus) {
        entry?.remove();
        entry = null;
      }
    });
  }

  void update(String query) {
    if (timer?.isActive ?? false) timer!.cancel();

    if (query.trim().isEmpty) {
      setState(() => items = []);
      entry?.remove();
      entry = null;
      return;
    }

    timer = Timer(const Duration(milliseconds: 250), () async {
      setState(() => active = true);
      try {
        final data = await widget.search(query);
        if (mounted) {
          setState(() {
            items = data;
            active = false;
          });
          if (items.isNotEmpty && focus.hasFocus) {
            if (entry != null) {
              entry!.markNeedsBuild();
              controller.forward(from: 0.0);
            } else {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && box.attached) {
                final size = box.size;
                entry = OverlayEntry(
                  builder: (context) {
                    final theme = Theme.of(context);

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              focus.unfocus();
                              entry?.remove();
                              entry = null;
                            },
                          ),
                        ),
                        Positioned(
                          width: size.width,
                          child: CompositedTransformFollower(
                            link: link,
                            showWhenUnlinked: false,
                            offset: Offset(0.0, size.height + 8.0),
                            child: FadeTransition(
                              opacity: fade,
                              child: SlideTransition(
                                position: slide,
                                child: Material(
                                  elevation: 8.0,
                                  color: theme.colorScheme.surface,
                                  shadowColor: Colors.black.withValues(
                                    alpha: 0.25,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      maxHeight: 300,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.5),
                                        width: 1,
                                      ),
                                    ),
                                    child: ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      shrinkWrap: true,
                                      itemCount: items.length,
                                      separatorBuilder: (context, index) =>
                                          Divider(
                                            height: 1,
                                            indent: 16,
                                            endIndent: 16,
                                            color: theme
                                                .colorScheme
                                                .outlineVariant
                                                .withValues(alpha: 0.2),
                                          ),
                                      itemBuilder: (context, index) {
                                        final location = items[index];
                                        final name = location.ascii.isNotEmpty
                                            ? location.ascii
                                            : 'Unknown Location';

                                        return ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 4,
                                              ),
                                          leading: CircleAvatar(
                                            radius: 16,
                                            backgroundColor: theme
                                                .colorScheme
                                                .primaryContainer,
                                            child: Icon(
                                              Icons.location_on_rounded,
                                              size: 18,
                                              color: theme
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                          ),
                                          title: Text(
                                            name,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                          onTap: () {
                                            widget.controller.text = name;
                                            widget.select(location);
                                            focus.unfocus();
                                            entry?.remove();
                                            entry = null;
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
                Overlay.of(context).insert(entry!);
                controller.forward(from: 0.0);
              }
            }
          } else {
            entry?.remove();
            entry = null;
          }
        }
      } catch (error) {
        developer.log(
          'Error updating search dropdown: $error',
          error: error,
          stackTrace: StackTrace.current,
          level: 1000,
          name: 'DropdownField.update',
        );
        if (mounted) {
          setState(() => active = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: link,
      child: TextFormField(
        controller: widget.controller,
        focusNode: focus,
        onChanged: update,
        decoration: widget.decoration.copyWith(
          suffixIcon: active
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: Padding(
                    padding: EdgeInsets.all(14.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : widget.decoration.suffixIcon,
        ),
      ),
    );
  }

  @override
  void dispose() {
    try {
      timer?.cancel();
      controller.dispose();
      focus.dispose();
      entry?.remove();
      entry = null;
    } catch (error) {
      developer.log(
        'Cleanup error in dropdown field dispose: $error',
        error: error,
        stackTrace: StackTrace.current,
        level: 1000,
        name: 'DropdownField.dispose',
      );
    }
    super.dispose();
  }
}
