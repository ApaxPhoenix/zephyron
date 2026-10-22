import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/dashboard/chats/gifs.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/services/picker.dart';
import 'package:zephyron/services/still.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/sheet.dart';
import 'package:zephyron/widgets/video.dart';

Future<({int width, int height})> dimensions(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final result = (width: descriptor.width, height: descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return result;
  } catch (_) {
    return (width: 0, height: 0);
  }
}

class Attach {
  static Future<void> menu(BuildContext context, String peer) {
    final courier = Courier.instance;
    final scheme = Theme.of(context).colorScheme;

    void warn(String text) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
      );
    }

    Future<void> photo({bool camera = false}) async {
      try {
        final picked = await Picker.photo(camera: camera);
        if (picked == null) return;
        final bytes = await picked.bytes();
        final size = await dimensions(bytes);
        final animated = picked.name.toLowerCase().endsWith('.gif');
        if (!context.mounted) return;
        final caption = await Preview.show(
          context,
          bytes: bytes,
          name: picked.name,
          media: true,
        );
        if (caption == null) return;
        await courier.attach(
          peer,
          bytes,
          kind: animated ? Kind.gif : Kind.image,
          name: picked.name,
          width: size.width,
          height: size.height,
          caption: caption,
        );
      } on FormatException catch (error) {
        warn(error.message);
      } catch (_) {
        warn('Could not attach that photo.');
      }
    }

    Future<void> clip() async {
      try {
        final picked = await Picker.video();
        if (picked == null) return;
        if (picked.size > Locker.ceiling) {
          await picked.discard();
          warn('Videos are limited to 25 MB. Try a shorter clip.');
          return;
        }
        final facts = await probe(picked.file);
        final thumb = await Still.grab(picked.path);
        final bytes = await picked.bytes();
        if (!context.mounted) return;
        final caption = await Preview.show(
          context,
          bytes: bytes,
          name: picked.name,
          media: false,
        );
        if (caption == null) return;
        final mime = Locker.mime(picked.name);
        await courier.attach(
          peer,
          bytes,
          kind: Kind.video,
          name: picked.name,
          mime: mime.startsWith('video/') ? mime : 'video/mp4',
          width: facts.width,
          height: facts.height,
          duration: facts.duration.inMilliseconds,
          thumb: thumb,
          caption: caption,
        );
      } on FormatException catch (error) {
        warn(error.message);
      } catch (_) {
        warn('Could not attach that video.');
      }
    }

    Widget option(IconData icon, String label, VoidCallback run) {
      return Builder(
        builder: (sheet) => InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pop(sheet);
            run();
          },
          child: Container(
            width: 68,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: scheme.primary, size: 26),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Sheets.grabber(sheet),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  option(
                    Icons.photo_library_outlined,
                    'Gallery',
                    () => photo(),
                  ),
                  option(
                    Icons.photo_camera_outlined,
                    'Camera',
                    () => photo(camera: true),
                  ),
                  option(Icons.videocam_outlined, 'Video', () => clip()),
                  option(Icons.gif_rounded, 'GIF', () async {
                    final picked = await Gifs.show(context);
                    if (picked == null) return;
                    try {
                      await courier.attach(
                        peer,
                        picked.bytes,
                        kind: Kind.gif,
                        name: 'giphy-${picked.gif.id}.gif',
                        mime: 'image/gif',
                        width: picked.gif.width,
                        height: picked.gif.height,
                      );
                    } catch (_) {
                      warn('Could not attach that GIF.');
                    }
                  }),
                  option(Icons.insert_drive_file_outlined, 'File', () async {
                    try {
                      final chosen = await Picker.file();
                      if (chosen == null) return;
                      if (chosen.size > Locker.ceiling) {
                        await chosen.discard();
                        warn('Files are limited to 25 MB.');
                        return;
                      }
                      final bytes = await chosen.bytes();
                      final name = chosen.name;
                      final mime = Locker.mime(name);
                      final image = mime.startsWith('image/');
                      final size = image
                          ? await dimensions(bytes)
                          : (width: 0, height: 0);
                      if (!context.mounted) return;
                      final caption = await Preview.show(
                        context,
                        bytes: bytes,
                        name: name,
                        media: image,
                      );
                      if (caption == null) return;
                      await courier.attach(
                        peer,
                        bytes,
                        kind: mime == 'image/gif'
                            ? Kind.gif
                            : image
                            ? Kind.image
                            : Kind.file,
                        name: name,
                        mime: mime,
                        width: size.width,
                        height: size.height,
                        caption: caption,
                      );
                    } on FormatException catch (error) {
                      warn(error.message);
                    } catch (_) {
                      warn('Could not attach that file.');
                    }
                  }),
                  option(Icons.person_outline, 'Trustee', () async {
                    final chosen = await Chooser.show(
                      context,
                      title: 'Share a trustee',
                      exclude: {peer},
                    );
                    if (chosen == null) return;
                    await courier.share(peer, chosen);
                  }),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Sent peer to peer over Tor and stored encrypted on both devices',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Preview extends StatefulWidget {
  final Uint8List bytes;
  final String name;
  final bool media;

  const Preview({
    super.key,
    required this.bytes,
    required this.name,
    required this.media,
  });

  static Future<String?> show(
    BuildContext context, {
    required Uint8List bytes,
    required String name,
    required bool media,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Preview(bytes: bytes, name: name, media: media),
    );
  }

  @override
  State<Preview> createState() => PreviewState();
}

class PreviewState extends State<Preview> {
  final TextEditingController caption = TextEditingController();

  @override
  void dispose() {
    caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final height = MediaQuery.of(context).size.height;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: inset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Sheets.grabber(context),
            if (widget.media)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * 0.45),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.memory(widget.bytes, fit: BoxFit.contain),
                ),
              )
            else
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.insert_drive_file_outlined,
                    color: scheme.primary,
                  ),
                ),
                title: Text(
                  widget.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(measure(widget.bytes.length)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: caption,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Add a caption',
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: () => Navigator.pop(context, caption.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class Chooser extends StatelessWidget {
  final String title;
  final Set<String> exclude;

  const Chooser({super.key, required this.title, this.exclude = const {}});

  static Future<Trustee?> show(
    BuildContext context, {
    required String title,
    Set<String> exclude = const {},
  }) {
    return showModalBottomSheet<Trustee>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Chooser(title: title, exclude: exclude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final people =
        Courier.instance.roster.values
            .where((item) => item.trusted && !exclude.contains(item.address))
            .toList()
          ..sort((alpha, beta) => alpha.label.compareTo(beta.label));

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Sheets.grabber(context),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No other trustees yet.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: people.length,
                itemBuilder: (context, index) {
                  final person = people[index];
                  return ListTile(
                    leading: Portrait(address: person.address, size: 42),
                    title: Text(
                      person.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      person.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: Pallete.mono,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, person),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
