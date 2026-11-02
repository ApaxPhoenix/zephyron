import 'dart:io';
import 'package:flutter/services.dart';

/// Something picked on the phone, copied into the outbox that is wiped when
/// the vault locks.
class Picked {
  final String path;
  final String name;
  final String mime;
  final int size;

  const Picked({
    required this.path,
    required this.name,
    required this.mime,
    required this.size,
  });

  File get file => File(path);

  /// Reads the copy and deletes it, so no plain copy is left behind once
  /// the app has encrypted what it needs.
  Future<Uint8List> bytes() async {
    final data = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    return data;
  }

  /// Deletes the copy of something the app turned down.
  Future<void> discard() async {
    try {
      await file.delete();
    } catch (_) {}
  }
}

/// The phone's own photo, video and file pickers and its camera app, through
/// a small channel: Android's system pickers or iOS's PHPicker and document
/// picker. None of them need storage permissions.
class Picker {
  static const MethodChannel link = MethodChannel('zephyron/picker');

  /// A photo from the gallery, or a new one from the [camera], scaled to
  /// [limit] on its long side and turned upright. GIFs come as they are.
  static Future<Picked?> photo({
    bool camera = false,
    bool front = false,
    int limit = 2560,
    int quality = 88,
  }) => pick(camera ? 'camera' : 'photo', {
    'limit': limit,
    'quality': quality,
    'front': front,
  });

  static Future<Picked?> video() => pick('video', const {});

  /// Any file, or only those of a MIME [type] such as `audio/*`.
  static Future<Picked?> file({String type = '*/*'}) =>
      pick('file', {'type': type});

  static Future<Picked?> pick(
    String method,
    Map<String, Object> arguments,
  ) async {
    final result = await link.invokeMapMethod<String, Object?>(
      method,
      arguments,
    );
    if (result == null) return null;
    return Picked(
      path: result['path'] as String,
      name: result['name'] as String? ?? 'file',
      mime: result['mime'] as String? ?? 'application/octet-stream',
      size: (result['size'] as num?)?.toInt() ?? 0,
    );
  }
}
