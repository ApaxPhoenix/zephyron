import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/dashboard/communities/index.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/broadcast.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/sheet.dart';
import 'package:zephyron/widgets/stamp.dart';
import 'package:zephyron/widgets/voice.dart';

/// A podcast channel: episodes anyone in the community can publish.
class PodcastPage extends StatefulWidget {
  final Community community;
  final Room room;

  const PodcastPage({super.key, required this.community, required this.room});

  @override
  State<PodcastPage> createState() => PodcastPageState();
}

class PodcastPageState extends State<PodcastPage> {
  bool busy = false;

  Broadcast get broadcast => Broadcast.instance;

  void warn(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Recording?> record() {
    return showModalBottomSheet<Recording>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Sheets.grabber(sheet)),
                Text(
                  'Recording an Episode',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Up to an hour. Send it when you are done, or discard it to start again.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                Recorder(
                  limit: const Duration(hours: 1),
                  onDone: (take) => Navigator.pop(sheet, take),
                  onCancel: () => Navigator.pop(sheet),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<({Uint8List bytes, Duration duration, String mime})?> file() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.audio);
      if (picked.isEmpty) return null;
      final chosen = picked.first.xFile;
      if (await chosen.length() > Broadcast.ceiling) {
        warn('Episodes are limited to 50 MB.');
        return null;
      }
      final probe = AudioPlayer();
      Duration duration = Duration.zero;
      try {
        await probe.setSource(DeviceFileSource(chosen.path));
        duration = await probe.getDuration() ?? Duration.zero;
      } catch (_) {
      } finally {
        await probe.dispose();
      }
      final mime = Locker.mime(picked.first.name);
      return (
        bytes: await chosen.readAsBytes(),
        duration: duration,
        mime: mime.startsWith('audio/') ? mime : 'audio/mp4',
      );
    } catch (_) {
      warn('Could not open that audio file.');
      return null;
    }
  }

  Future<({String title, String about})?> details() async {
    final title = TextEditingController();
    final about = TextEditingController();
    final result = await showDialog<({String title, String about})>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Episode Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: about,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What is it about? (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => title.text.trim().isEmpty
                ? null
                : Navigator.pop(dialog, (
                    title: title.text.trim(),
                    about: about.text.trim(),
                  )),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    title.dispose();
    about.dispose();
    return result;
  }

  Future<void> create() async {
    final source = await Sheets.pick<String>(
      context,
      title: 'New Episode',
      subtitle:
          'Members download it from you, then from each other, encrypted with the community key.',
      current: '',
      options: [
        Choice(
          value: 'record',
          label: 'Record Now',
          hint: 'Up to an hour from your microphone',
          leading: Icon(
            Icons.mic_none_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Choice(
          value: 'file',
          label: 'Choose an Audio File',
          hint: 'Up to 50 MB',
          leading: Icon(
            Icons.audio_file_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
    if (source == null || !mounted) return;

    Uint8List? bytes;
    var duration = Duration.zero;
    var mime = 'audio/mp4';
    if (source == 'record') {
      final take = await record();
      if (take == null) return;
      bytes = take.bytes;
      duration = take.duration;
    } else {
      final picked = await file();
      if (picked == null) return;
      bytes = picked.bytes;
      duration = picked.duration;
      mime = picked.mime;
    }
    if (!mounted) return;
    final info = await details();
    if (info == null) return;

    setState(() => busy = true);
    try {
      await broadcast.publish(
        widget.community,
        widget.room.id,
        bytes: bytes,
        title: info.title,
        about: info.about,
        duration: duration,
        mime: mime,
      );
      warn('Episode published.');
    } on FormatException catch (error) {
      warn(error.message);
    } catch (_) {
      warn('Could not publish that episode.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Mark(kind: Space.podcast, color: scheme.onSurface),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.community.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: busy ? null : create,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('New Episode'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([Mesh.instance, broadcast]),
        builder: (context, _) {
          final episodes = broadcast.episodes(
            widget.community.id,
            widget.room.id,
          );
          if (episodes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.podcasts,
                        size: 34,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Episodes Yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Record one or upload an audio file. Every member who listens helps pass it on.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
            itemCount: episodes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => EpisodeCard(
              key: ValueKey(episodes[index].id),
              community: widget.community,
              post: episodes[index],
            ),
          );
        },
      ),
    );
  }
}

/// One episode, with download, playback and seeking.
class EpisodeCard extends StatefulWidget {
  final Community community;
  final Post post;

  const EpisodeCard({super.key, required this.community, required this.post});

  @override
  State<EpisodeCard> createState() => EpisodeCardState();
}

class EpisodeCardState extends State<EpisodeCard> {
  final List<StreamSubscription<dynamic>> watching = [];
  AudioPlayer? player;
  bool? kept;
  bool playing = false;
  bool opening = false;
  Duration position = Duration.zero;
  Duration? total;

  Broadcast get broadcast => Broadcast.instance;
  String get blob => Broadcast.blob(widget.post);

  @override
  void initState() {
    super.initState();
    check();
    broadcast.addListener(check);
  }

  @override
  void dispose() {
    broadcast.removeListener(check);
    for (final subscription in watching) {
      subscription.cancel();
    }
    player?.dispose();
    super.dispose();
  }

  Future<void> check() async {
    final here = await broadcast.held(blob);
    if (mounted && here != kept) setState(() => kept = here);
  }

  Future<void> toggle() async {
    final current = player;
    if (current != null) {
      playing ? await current.pause() : await current.resume();
      return;
    }
    setState(() => opening = true);
    try {
      final bytes = await broadcast.audio(blob);
      final file = await Locker.stage(blob, 'episode.m4a', bytes);
      final made = AudioPlayer();
      watching
        ..add(
          made.onPositionChanged.listen((value) {
            if (mounted) setState(() => position = value);
          }),
        )
        ..add(
          made.onDurationChanged.listen((value) {
            if (mounted) setState(() => total = value);
          }),
        )
        ..add(
          made.onPlayerStateChanged.listen((state) {
            if (mounted) setState(() => playing = state == PlayerState.playing);
          }),
        );
      await made.play(
        DeviceFileSource(File(file.path).path),
        position: position > Duration.zero ? position : null,
      );
      player = made;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play this episode.')),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final post = widget.post;
    final mesh = Mesh.instance;
    final name = mesh.called(widget.community.id, post.author);
    final length0 =
        total ?? Duration(milliseconds: post.meta['duration'] as int? ?? 0);
    final size = post.meta['size'] as int? ?? 0;
    final about = post.meta['about'] as String? ?? '';
    final loading = broadcast.progress[blob];
    final trustee = Courier.instance.roster[post.author];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                trustee != null
                    ? Portrait(address: post.author, size: 32, presence: false)
                    : Avatar(label: name, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$name · ${brief(post.time)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${length(length0)} · ${measure(size)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.text,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (about.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                about,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (kept == true)
              Row(
                children: [
                  IconButton.filled(
                    tooltip: playing ? 'Pause' : 'Play',
                    style: Pallete.solid(Theme.of(context).colorScheme),
                    onPressed: opening ? null : toggle,
                    icon: opening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                  ),
                  Expanded(
                    child: Slider(
                      value: length0.inMilliseconds == 0
                          ? 0
                          : (position.inMilliseconds / length0.inMilliseconds)
                                .clamp(0.0, 1.0),
                      onChanged: (value) {
                        final target = Duration(
                          milliseconds: (value * length0.inMilliseconds)
                              .round(),
                        );
                        setState(() => position = target);
                        player?.seek(target);
                      },
                    ),
                  ),
                  Text(
                    length(position),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              )
            else if (loading != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: loading > 0 ? loading : null,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fetching from members · ${(loading * 100).round()}%',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  side: BorderSide(color: scheme.outline),
                  foregroundColor: scheme.onSurface,
                ),
                onPressed: kept == null
                    ? null
                    : () => broadcast.download(widget.community, post),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download'),
              ),
          ],
        ),
      ),
    );
  }
}
