import 'package:flutter/services.dart';

/// The phone's own share sheet, through a small channel: an Android chooser
/// or an iOS activity sheet. Files go out from the outbox, lent to the one
/// app picked and wiped when the vault locks.
class Share {
  static const MethodChannel link = MethodChannel('zephyron/share');

  static Future<void> text(String text, {String? subject}) =>
      link.invokeMethod<void>('text', {'text': text, 'subject': ?subject});

  static Future<void> file(String path, {String? mime}) =>
      link.invokeMethod<void>('file', {'path': path, 'mime': ?mime});
}
