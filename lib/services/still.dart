import 'dart:developer' as developer;
import 'package:flutter/services.dart';

/// Video thumbnails from the phone's own decoder, through a small channel
/// to Android's MediaMetadataRetriever or iOS's AVAssetImageGenerator, so no
/// extra package is needed.
class Still {
  static const MethodChannel link = MethodChannel('zephyron/media');

  /// Largest thumbnail kept, so it fits inside an encrypted manifest.
  static const int ceiling = 64 * 1024;

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
