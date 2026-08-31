import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/gifs.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/picker.dart';
import 'package:zephyron/services/web.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/crop.dart';
import 'package:zephyron/widgets/sheet.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final Profile draft = Courier.instance.me.copy();
  late final TextEditingController name = TextEditingController(
    text: draft.name,
  );
  late final TextEditingController mood = TextEditingController(
    text: draft.mood,
  );
  late final TextEditingController bio = TextEditingController(text: draft.bio);
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    mood.dispose();
    bio.dispose();
    super.dispose();
  }

  void warn(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Fits a GIF under [limit] off the UI thread, or warns when it cannot.
  Future<Uint8List?> squeeze(Uint8List bytes, int limit) async {
    if (bytes.length <= limit) return bytes;
    setState(() => busy = true);
    try {
      final smaller = await Isolate.run(() => Cropper.shrink(bytes, limit));
      if (smaller == null) warn('That GIF is too large even when shrunk.');
      return smaller;
    } catch (_) {
      warn('Could not read that GIF.');
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Uint8List?> gallery({bool camera = false}) async {
    try {
      final picked = await Picker.photo(
        camera: camera,
        front: true,
        limit: 2048,
        quality: 92,
      );
      return picked == null ? null : await picked.bytes();
    } catch (_) {
      warn('Could not open that picture.');
      return null;
    }
  }

  Future<void> picture() async {
    Future<void> pick({bool camera = false}) async {
      final bytes = await gallery(camera: camera);
      if (bytes == null || !mounted) return;
      if (Cropper.animated(bytes)) {
        final fitted = await squeeze(bytes, Courier.portrait);
        if (fitted != null) setState(() => draft.avatar = fitted);
        return;
      }
      final cropped = await Cropper.open(context, bytes);
      if (cropped == null) return;
      if (cropped.length > Courier.portrait) {
        warn('That picture is too large.');
        return;
      }
      setState(() => draft.avatar = cropped);
    }

    await Sheets.actions(
      context,
      items: [
        SheetAction(
          icon: Icons.photo_library_outlined,
          label: 'Choose from Gallery',
          onTap: () => pick(),
        ),
        SheetAction(
          icon: Icons.photo_camera_outlined,
          label: 'Take a Photo',
          onTap: () => pick(camera: true),
        ),
        if (draft.avatar != null)
          SheetAction(
            icon: Icons.delete_outline,
            label: 'Remove Photo',
            destructive: true,
            onTap: () => setState(() => draft.avatar = null),
          ),
      ],
    );
  }

  Future<void> banner() async {
    Future<void> photo() async {
      final bytes = await gallery();
      if (bytes == null || !mounted) return;
      if (Cropper.animated(bytes)) {
        final fitted = await squeeze(bytes, Courier.banner);
        if (fitted != null) setState(() => draft.banner = fitted);
        return;
      }
      final cropped = await Cropper.open(
        context,
        bytes,
        aspect: 3,
        round: false,
        width: 960,
        title: 'Crop Banner',
      );
      if (cropped != null) setState(() => draft.banner = cropped);
    }

    Future<void> giphy() async {
      final picked = await Gifs.show(context);
      if (picked == null) return;
      final fitted = await squeeze(picked.bytes, Courier.banner);
      if (fitted != null) setState(() => draft.banner = fitted);
    }

    Future<void> file() async {
      try {
        final picked = await Picker.file(type: 'image/gif');
        if (picked == null) return;
        final bytes = await picked.bytes();
        if (!Cropper.animated(bytes)) {
          warn('Choose a GIF file.');
          return;
        }
        final fitted = await squeeze(bytes, Courier.banner);
        if (fitted != null) setState(() => draft.banner = fitted);
      } catch (_) {
        warn('Could not open that file.');
      }
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
        SheetAction(
          icon: Icons.folder_open_outlined,
          label: 'GIF from Files',
          onTap: file,
        ),
        if (draft.banner != null)
          SheetAction(
            icon: Icons.delete_outline,
            label: 'Remove Banner',
            destructive: true,
            onTap: () => setState(() => draft.banner = null),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Form(
            key: key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 196,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: busy ? null : banner,
                          child: Cover(
                            banner: draft.banner,
                            height: 140,
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.edit_outlined,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  draft.banner == null
                                      ? 'Add Banner'
                                      : 'Edit Banner',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        top: 88,
                        child: GestureDetector(
                          onTap: busy ? null : picture,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  shape: BoxShape.circle,
                                ),
                                child: Avatar(
                                  label: name.text.isEmpty ? '?' : name.text,
                                  image: draft.avatar,
                                  size: 96,
                                ),
                              ),
                              Positioned(
                                right: 2,
                                bottom: 2,
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
                                    size: 16,
                                    color: scheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (busy)
                        const Positioned(
                          right: 4,
                          bottom: 12,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  'Tap the banner or your photo to change them. Banners can be a cropped photo or an animated GIF.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Display Name',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: name,
                  maxLength: Profile.names,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'How trustees see you',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text('Status', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: mood,
                  maxLength: Profile.moods,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'What are you up to?',
                  ),
                ),
                const SizedBox(height: 12),
                Text('Bio', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: bio,
                  maxLength: Profile.bios,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'A few words about you',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Availability',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                RadioGroup<Availability>(
                  groupValue: draft.availability,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => draft.availability = value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final state in Availability.values)
                        RadioListTile<Availability>(
                          value: state,
                          contentPadding: EdgeInsets.zero,
                          secondary: Glyph(availability: state),
                          title: Text(state.label),
                          subtitle: Text(state.hint),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Only trustees receive your profile. Requests and blocked senders never see it.',
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            draft
                              ..name = Profile.clip(name.text, Profile.names)
                              ..mood = Profile.clip(mood.text, Profile.moods)
                              ..bio = Profile.clip(bio.text, Profile.bios);
                            await Courier.instance.publish(draft);
                            if (context.mounted) Navigator.pop(context);
                          },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: busy
                          ? const SizedBox(
                              key: ValueKey('busy'),
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Profile', key: ValueKey('idle')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
