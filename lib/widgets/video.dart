import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/locker.dart';

/// Reads a video's length and size by opening it once.
Future<({Duration duration, int width, int height})> probe(File file) async {
  final controller = VideoPlayerController.file(file);
  try {
    await controller.initialize();
    final value = controller.value;
    return (
      duration: value.duration,
      width: value.size.width.round(),
      height: value.size.height.round(),
    );
  } catch (_) {
    return (duration: Duration.zero, width: 0, height: 0);
  } finally {
    await controller.dispose();
  }
}

/// A video message bubble: a dark frame with its length and a play button.
class Reel extends StatelessWidget {
  final Message message;
  final double width;

  const Reel({super.key, required this.message, required this.width});

  @override
  Widget build(BuildContext context) {
    final ratio = message.width > 0 && message.height > 0
        ? (message.width / message.height).clamp(0.6, 1.8)
        : 16 / 9;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => Screening(message: message),
        ),
      ),
      child: Container(
        width: width,
        height: width / ratio,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B1D24), Color(0xFF2B2F3A)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (message.meta['thumb'] is String)
              Image.memory(
                base64.decode(message.meta['thumb'] as String),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            if (message.meta['thumb'] is String)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x99000000)],
                  ),
                ),
              ),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_outlined,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${length(message.duration)} · ${measure(message.size)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen playback of a video message, decrypted to a temporary file
/// that is swept when the vault locks.
class Screening extends StatefulWidget {
  final Message message;

  const Screening({super.key, required this.message});

  @override
  State<Screening> createState() => ScreeningState();
}

class ScreeningState extends State<Screening> {
  VideoPlayerController? controller;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    try {
      final file = await Locker.export(widget.message);
      final next = VideoPlayerController.file(file);
      await next.initialize();
      next.addListener(() {
        if (mounted) setState(() {});
      });
      await next.play();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() => controller = next);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = controller;
    final value = video?.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shape: const Border(),
        title: Text(
          widget.message.text.isEmpty ? 'Video' : widget.message.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: failed
            ? const Center(
                child: Text(
                  'Could not play this video.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : video == null || value == null || !value.isInitialized
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          value.isPlaying ? video.pause() : video.play(),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: VideoPlayer(video),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 20, 16),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
                          onPressed: () =>
                              value.isPlaying ? video.pause() : video.play(),
                          icon: Icon(
                            value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            video,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            colors: VideoProgressColors(
                              playedColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              bufferedColor: Colors.white24,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${length(value.position)} / ${length(value.duration)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
