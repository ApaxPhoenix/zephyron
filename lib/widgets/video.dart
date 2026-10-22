import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/services/player.dart';
import 'package:zephyron/services/still.dart';

/// Reads a video's length and upright size.
Future<({Duration duration, int width, int height})> probe(File file) =>
    Still.probe(file.path);

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
  Player? player;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    try {
      final file = await Locker.export(widget.message);
      final next = await Player.open(file.path, video: true);
      if (!mounted) {
        await next.close();
        return;
      }
      next.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() => player = next);
      await next.play();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    player?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = player;
    final texture = video?.texture;
    final total = video?.duration ?? Duration.zero;
    final at = video?.position ?? Duration.zero;
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
            : video == null || texture == null
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => video.playing ? video.pause() : video.play(),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: video.aspect,
                          child: RotatedBox(
                            quarterTurns: video.rotation ~/ 90,
                            child: Texture(textureId: texture),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 20, 16),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: video.playing ? 'Pause' : 'Play',
                          onPressed: () =>
                              video.playing ? video.pause() : video.play(),
                          icon: Icon(
                            video.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            activeColor: Theme.of(context).colorScheme.primary,
                            inactiveColor: Colors.white24,
                            value: total.inMilliseconds == 0
                                ? 0
                                : (at.inMilliseconds / total.inMilliseconds)
                                      .clamp(0.0, 1.0),
                            onChanged: (value) => video.seek(
                              Duration(
                                milliseconds: (value * total.inMilliseconds)
                                    .round(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${length(at)} / ${length(total)}',
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
