import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Plays raw 16-bit mono audio as it arrives, through the phone's own audio
/// stack: AudioTrack on Android and AVAudioEngine on iOS. Used by voice
/// rooms, so no third-party audio package sits between a voice and the
/// speaker.
class Sound {
  static const MethodChannel link = MethodChannel('zephyron/sound');

  static Future<bool> open(int rate) async {
    try {
      await link.invokeMethod<void>('open', {'rate': rate});
      return true;
    } on MissingPluginException {
      return false;
    } catch (error) {
      developer.log(
        'Could not open the speaker for live audio',
        name: 'Sound.open',
        level: 900,
        error: error,
      );
      return false;
    }
  }

  /// Queues [samples] to play right after what is already queued.
  static Future<void> feed(Int16List samples) async {
    try {
      await link.invokeMethod<void>('feed', {
        'pcm': Uint8List.view(
          samples.buffer,
          samples.offsetInBytes,
          samples.lengthInBytes,
        ),
      });
    } catch (_) {}
  }

  static Future<void> close() async {
    try {
      await link.invokeMethod<void>('close');
    } catch (_) {}
  }
}
