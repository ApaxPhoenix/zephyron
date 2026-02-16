import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/widgets/avatar.dart';
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

  Future<void> picture() async {
    Future<void> pick(ImageSource source) async {
      try {
        final picked = await ImagePicker().pickImage(
          source: source,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 82,
          preferredCameraDevice: CameraDevice.front,
        );
        if (picked == null) return;
        final Uint8List bytes = await picked.readAsBytes();
        if (bytes.length > Courier.portrait) {
          throw const FormatException('That picture is too large.');
        }
        setState(() => draft.avatar = bytes);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not use that picture.')),
        );
      }
    }

    await Sheets.actions(
      context,
      items: [
        SheetAction(
          icon: Icons.photo_library_outlined,
          label: 'Choose from Gallery',
          onTap: () => pick(ImageSource.gallery),
        ),
        SheetAction(
          icon: Icons.photo_camera_outlined,
          label: 'Take a Photo',
          onTap: () => pick(ImageSource.camera),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: picture,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Avatar(
                          label: name.text.isEmpty ? '?' : name.text,
                          image: draft.avatar,
                          size: 100,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.surface,
                                width: 2,
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
                Center(
                  child: TextButton(
                    onPressed: picture,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        draft.avatar == null ? 'Add a Photo' : 'Change Photo',
                        key: ValueKey(draft.avatar == null),
                      ),
                    ),
                  ),
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
