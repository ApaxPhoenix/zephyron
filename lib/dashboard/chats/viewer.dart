import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/widgets/stamp.dart';

class Viewer extends StatelessWidget {
  final Message message;
  final Uint8List bytes;
  final String author;

  const Viewer({
    super.key,
    required this.message,
    required this.bytes,
    required this.author,
  });

  static Future<void> export(BuildContext context, Message message) async {
    try {
      final file = await Locker.export(message);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: message.mime)]),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not export this attachment.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              author,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              '${heading(message.time)}, ${clock(message.time)}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share or save',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => export(context, message),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Hero(
                  tag: 'media:${message.id}',
                  child: Image.memory(bytes, gaplessPlayback: true),
                ),
              ),
            ),
          ),
          if (message.text.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Text(
                    message.text,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
