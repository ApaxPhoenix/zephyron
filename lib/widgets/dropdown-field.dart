import 'dart:async';
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

class DropdownFieldState extends State<DropdownField> {
  final link = LayerLink();
  final focus = FocusNode();

  OverlayEntry? entry;
  List<Location> items = [];
  bool active = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) {
        hide();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    focus.dispose();
    hide();
    super.dispose();
  }

  void update(String query) {
    if (timer?.isActive ?? false) timer!.cancel();

    if (query.trim().isEmpty) {
      setState(() => items = []);
      hide();
      return;
    }

    timer = Timer(const Duration(milliseconds: 300), () async {
      setState(() => active = true);
      try {
        final data = await widget.search(query);
        if (mounted) {
          setState(() {
            items = data;
            active = false;
          });
          if (items.isNotEmpty && focus.hasFocus) {
            show();
            entry?.markNeedsBuild();
          } else {
            hide();
          }
        }
      } catch (error) {
        if (mounted) {
          setState(() => active = false);
        }
      }
    });
  }

  void show() {
    if (entry != null) {
      entry!.markNeedsBuild();
      return;
    }
    entry = overlay();
    Overlay.of(context).insert(entry!);
  }

  void hide() {
    entry?.remove();
    entry = null;
  }

  OverlayEntry overlay() {
    final box = context.findRenderObject() as RenderBox;
    final size = box.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height + 8.0),
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).canvasColor,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final location = items[index];
                  return ListTile(
                    leading: const Icon(Icons.location_on),
                    title: Text(location.iso),
                    subtitle: Text(
                      '${location.ascii} • ${location.feature} • ${location.code}',
                    ),
                    onTap: () {
                      widget.controller.text = location.iso;
                      widget.select(location);
                      focus.unfocus();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: link,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
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
            ),
            IconButton(onPressed: () {}, icon: const Icon(Icons.bookmark)),
          ],
        ),
      ),
    );
  }
}
