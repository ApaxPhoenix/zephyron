import 'dart:developer' as developer;
import 'package:flutter/services.dart';

/// Video thumbnails from the phone's own decoder, through a small channel
/// to Android's MediaMetadataRetriever or iOS's AVAssetImageGenerator, so no
/// extra package is needed.
class Still {
  static const MethodChannel link = MethodChannel('zephyron/media');

  /// Largest thumbnail kept, so it fits inside an encrypted manifest.
  static const int ceiling = 64 * 1024;

  /// How long a video or recording lasts, and a video's upright size; zero
  /// for whatever cannot be read.
  static Future<({Duration duration, int width, int height})> probe(
    String path,
  ) async {
    try {
      final facts = await link.invokeMapMethod<String, Object?>('probe', {
        'path': path,
      });
      int read(String key) => (facts?[key] as num?)?.toInt() ?? 0;
      return (
        duration: Duration(milliseconds: read('duration')),
        width: read('width'),
        height: read('height'),
      );
    } catch (_) {
      return (duration: Duration.zero, width: 0, height: 0);
    }
  }

  /// A JPEG of [path]'s first moments, or null when none can be made.
  static Future<Uint8List?> grab(String path, {int width = 480}) async {
    try {
      final bytes = await link.invokeMethod<Uint8List>('thumbnail', {
        'path': path,
        'width': width,
      });
      if (bytes == null || bytes.isEmpty || bytes.length > ceiling) return null;
      return bytes;
    } on MissingPluginException {
      return null;
    } catch (error) {
      developer.log(
        'Could not make a thumbnail for a video',
        name: 'Still.grab',
        level: 800,
        error: error,
      );
      return null;
    }
  }
}
