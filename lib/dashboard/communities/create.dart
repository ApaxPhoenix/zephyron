import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/gifs.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/picker.dart';
import 'package:zephyron/services/web.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/crop.dart';
import 'package:zephyron/widgets/sheet.dart';

/// Starts a community, or changes how an existing one looks when [id] is set.
class CreatePage extends StatefulWidget {
  final String? id;

  const CreatePage({super.key, this.id});

  @override
  State<CreatePage> createState() => CreatePageState();
}

class CreatePageState extends State<CreatePage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  late final Community? existing = widget.id == null
      ? null
      : Mesh.instance.communities[widget.id];
  late final TextEditingController name = TextEditingController(
    text: existing?.name ?? '',
  );
  late final TextEditingController about = TextEditingController(
    text: existing?.about ?? '',
  );
  late Uint8List? icon = existing?.icon;
  late Uint8List? banner = existing?.banner;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    about.dispose();
    super.dispose();
  }

  void warn(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Uint8List?> pick() async {
    try {
      final picked = await Picker.photo(limit: 2048, quality: 92);
      return picked == null ? null : await picked.bytes();
    } catch (_) {
      warn('Could not open that picture.');
      return null;
    }
  }

  Future<Uint8List?> fit(Uint8List bytes, int limit) async {
    if (bytes.length <= limit) return bytes;
    setState(() => busy = true);
    try {
      final smaller = await Isolate.run(() => Cropper.shrink(bytes, limit));
      if (smaller == null) warn('That GIF is too large even when shrunk.');
      return smaller;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseIcon() async {
    final bytes = await pick();
    if (bytes == null || !mounted) return;
    if (Cropper.animated(bytes)) {
      final fitted = await fit(bytes, Mesh.icons);
      if (fitted != null) setState(() => icon = fitted);
      return;
    }
    final cropped = await Cropper.open(
      context,
      bytes,
      round: false,
      width: 320,
      title: 'Crop Icon',
    );
    if (cropped == null) return;
    if (cropped.length > Mesh.icons) {
      warn('That picture is too large.');
      return;
    }
    setState(() => icon = cropped);
  }

  Future<void> chooseBanner() async {
    Future<void> photo() async {
      final bytes = await pick();
      if (bytes == null || !mounted) return;
      if (Cropper.animated(bytes)) {
        final fitted = await fit(bytes, Mesh.banners);
        if (fitted != null) setState(() => banner = fitted);
        return;
      }
      final cropped = await Cropper.open(
        context,
        bytes,
        aspect: 3,
        round: false,
        width: 900,
        title: 'Crop Banner',
      );
      if (cropped == null) return;
      final fitted = await fit(cropped, Mesh.banners);
      if (fitted != null) setState(() => banner = fitted);
    }

    Future<void> giphy() async {
      final picked = await Gifs.show(context);
      if (picked == null) return;
      final fitted = await fit(picked.bytes, Mesh.banners);
      if (fitted != null) setState(() => banner = fitted);
    }

    await Sheets.actions(
      context,
      items: [
        SheetAction(
          icon: Icons.photo_library_outlined,
          label: 'Choose a Photo',
          onTap: photo,
        ),
        if (Giphy.ready)
          SheetAction(
            icon: Icons.gif_box_outlined,
            label: 'Search GIPHY',
            onTap: giphy,
          ),
        if (banner != null)
          SheetAction(
            icon: Icons.delete_outline,
            label: 'Remove Banner',
            destructive: true,
            onTap: () => setState(() => banner = null),
          ),
      ],
    );
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    setState(() => busy = true);
    final navigator = Navigator.of(context);
    final mesh = Mesh.instance;
    try {
      final current = existing;
      if (current == null) {
        final made = await mesh.create(
          name: name.text,
          about: about.text,
          icon: icon,
          banner: banner,
        );
        navigator.pushReplacementNamed(
          '/dashboard/communities/community',
          arguments: {'id': made.id},
        );
      } else {
        await mesh.describe(
          current,
          name: name.text.trim(),
          about: about.text.trim(),
          icon: icon,
          clearIcon: icon == null && current.icon != null,
          banner: identical(banner, current.banner) ? null : banner,
          clearBanner: banner == null && current.banner != null,
        );
        navigator.pop();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final editing = existing != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit Community' : 'New Community')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Form(
            key: key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 190,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: busy ? null : chooseBanner,
                          child: Cover(
                            banner: banner,
                            height: 136,
                            radius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              banner == null ? 'Add Banner' : 'Edit Banner',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        top: 92,
                        child: GestureDetector(
                          onTap: busy ? null : chooseIcon,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Crest(
                                  label: name.text.isEmpty ? '?' : name.text,
                                  image: icon,
                                  size: 84,
                                ),
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: scheme.surface,
                                        width: 3,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.photo_camera_outlined,
                                      size: 15,
                                      color: scheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('Name', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                TextFormField(
                  controller: name,
                  maxLength: Community.names,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'What should people call it?',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Give your community a name'
                      : null,
                ),
                const SizedBox(height: 12),
                Text('Description', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                TextFormField(
                  controller: about,
                  maxLength: Community.abouts,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'What is it for?',
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.hub_outlined, color: scheme.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          editing
                              ? 'Any member can change these. The newest change shows for everyone.'
                              : 'Nobody owns a community, including you. Every member can invite people, add channels and change this description; you will simply be listed first.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: busy ? null : save,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(editing ? 'Save Changes' : 'Create Community'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
