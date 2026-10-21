import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/locker.dart';

/// What a finished recording hands back.
typedef Recording = ({Uint8List bytes, Duration duration});

/// The bar that replaces the message field while a voice note is recorded.
class Recorder extends StatefulWidget {
  /// Longest voice note, kept well under the attachment limit.
  static const Duration ceiling = Duration(minutes: 10);

  final ValueChanged<Recording> onDone;
  final VoidCallback onCancel;

  const Recorder({super.key, required this.onDone, required this.onCancel});

  @override
  State<Recorder> createState() => RecorderState();
}

class RecorderState extends State<Recorder> {
  final AudioRecorder recorder = AudioRecorder();
  final Stopwatch watch = Stopwatch();
  final List<double> levels = [];
  StreamSubscription<Amplitude>? meter;
  Timer? ticker;
  String? path;
  bool live = false;
  bool finishing = false;

  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    try {
      if (!await recorder.hasPermission()) {
        widget.onCancel();
        return;
      }
      final folder = await Locker.outbox();
      path =
          '${folder.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 32000,
          numChannels: 1,
          noiseSuppress: true,
          echoCancel: true,
        ),
        path: path!,
      );
      watch.start();
      meter = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amplitude) {
            final level = ((amplitude.current + 50) / 50).clamp(0.05, 1.0);
            setState(() {
              levels.add(level);
              if (levels.length > 48) levels.removeAt(0);
            });
          });
      ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (watch.elapsed >= Recorder.ceiling) finish();
        if (mounted) setState(() {});
      });
      if (mounted) setState(() => live = true);
    } catch (_) {
      widget.onCancel();
    }
  }

  Future<void> finish() async {
    if (finishing) return;
    finishing = true;
    watch.stop();
    ticker?.cancel();
    await meter?.cancel();
    try {
      final saved = await recorder.stop();
      final file = File(saved ?? path!);
      final bytes = await file.readAsBytes();
      await file.delete();
      if (watch.elapsed < const Duration(milliseconds: 600) || bytes.isEmpty) {
        widget.onCancel();
        return;
      }
      widget.onDone((bytes: bytes, duration: watch.elapsed));
    } catch (_) {
      widget.onCancel();
    }
  }

  Future<void> cancel() async {
    if (finishing) return;
    finishing = true;
    ticker?.cancel();
    await meter?.cancel();
    try {
      await recorder.cancel();
    } catch (_) {}
    widget.onCancel();
  }

  @override
  void dispose() {
    ticker?.cancel();
    meter?.cancel();
    recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          tooltip: 'Discard',
          icon: Icon(Icons.delete_outline, color: scheme.error),
          onPressed: cancel,
        ),
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                AnimatedOpacity(
                  opacity: live && watch.elapsed.inMilliseconds % 1000 < 600
                      ? 1
                      : 0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.circle, size: 10, color: scheme.error),
                ),
                const SizedBox(width: 10),
                Text(
                  length(watch.elapsed),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wave(
                    levels: levels,
                    progress: 1,
                    color: scheme.error,
                    faded: scheme.error.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Send voice message',
          onPressed: live ? finish : null,
          icon: const Icon(Icons.arrow_upward_rounded),
        ),
      ],
    );
  }
}

/// Bars standing in for a waveform; the played part is drawn solid.
class Wave extends StatelessWidget {
  final List<double> levels;
  final double progress;
  final Color color;
  final Color faded;

  const Wave({
    super.key,
    required this.levels,
    required this.progress,
    required this.color,
    required this.faded,
  });

  /// A steady made-up shape for a stored note, so it looks the same every
  /// time without decoding the audio.
  static List<double> shape(String seed, int count) {
    final random = Random(seed.hashCode);
    return List.generate(count, (index) {
      final swell = sin(index / count * pi);
      return (0.25 + random.nextDouble() * 0.75) * (0.4 + 0.6 * swell);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, box) {
          final count = max(1, (box.maxWidth / 5).floor());
          final shown = levels.length >= count
              ? levels.sublist(levels.length - count)
              : [...List.filled(count - levels.length, 0.08), ...levels];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var index = 0; index < shown.length; index++)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 3,
                      height: 4 + 24 * shown[index],
                      decoration: BoxDecoration(
                        color: index / shown.length <= progress ? color : faded,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A voice message bubble's player.
class VoiceNote extends StatefulWidget {
  final Message message;
  final Color foreground;

  const VoiceNote({super.key, required this.message, required this.foreground});

  @override
  State<VoiceNote> createState() => VoiceNoteState();
}

class VoiceNoteState extends State<VoiceNote> {
  final List<StreamSubscription<dynamic>> watching = [];
  late final List<double> bars = Wave.shape(widget.message.id, 40);
  AudioPlayer? player;
  Duration position = Duration.zero;
  Duration? total;
  bool playing = false;
  bool loading = false;

  /// Made on first play, so a long chat does not open a player per note.
  AudioPlayer open() {
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
      )
      ..add(
        made.onPlayerComplete.listen((_) {
          if (mounted) setState(() => position = Duration.zero);
        }),
      );
    return made;
  }

  @override
  void dispose() {
    for (final subscription in watching) {
      subscription.cancel();
    }
    player?.dispose();
    super.dispose();
  }

  Future<void> toggle() async {
    final current = player;
    if (current != null && playing) {
      await current.pause();
      return;
    }
    if (current == null) {
      setState(() => loading = true);
      try {
        final file = await Locker.export(widget.message);
        final made = open();
        await made.setSource(DeviceFileSource(file.path));
        player = made;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not play this voice message.')),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => loading = false);
      }
    }
    await player!.resume();
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.foreground;
    final length0 = total ?? widget.message.duration;
    final progress = length0.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / length0.inMilliseconds;
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tone,
                    ),
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: playing ? 'Pause' : 'Play',
                    onPressed: toggle,
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: tone,
                      size: 30,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wave(
                  levels: bars,
                  progress: progress,
                  color: tone,
                  faded: tone.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 2),
                Text(
                  playing || position > Duration.zero
                      ? length(position)
                      : length(length0),
                  style: TextStyle(
                    color: tone.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
