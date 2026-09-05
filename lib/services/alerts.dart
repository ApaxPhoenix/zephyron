import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart' as hashing;
import 'package:flutter/services.dart';

/// System notifications through a small channel to the phone's own
/// notification manager, so no package is needed. They only ever say who
/// wrote and how many messages there are, never what they say.
class Alerts {
  static const MethodChannel link = MethodChannel('zephyron/alerts');

  /// The notification counting messages that arrived while locked.
  static const int held = 2;

  /// The notification for messages from [peer].
  static int slot(String peer) {
    final digest = hashing.sha256.convert(utf8.encode(peer)).bytes;
    return 1000 + ((digest[0] << 16 | digest[1] << 8 | digest[2]) % 1000000);
  }

  /// What a notification for [count] messages from [name] says.
  static String count(int count) =>
      count == 1 ? 'Sent you a message' : 'Sent you $count messages';

  static Future<void> call(String method, [Object? arguments]) async {
    try {
      await link.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Platforms without the native side simply show nothing.
    } catch (error) {
      developer.log(
        'Notification call $method failed',
        name: 'Alerts.call',
        level: 800,
        error: error,
      );
    }
  }

  /// Asks for permission to notify, where the platform requires it.
  static Future<void> permit() => call('permit');

  static Future<void> show(int id, String title, String text) =>
      call('show', {'id': id, 'title': title, 'text': text});

  static Future<void> cancel(int id) => call('cancel', {'id': id});

  /// Keeps the app running in the background so the phone stays reachable,
  /// with a quiet ongoing notification saying so.
  static Future<void> stand(bool on) => call('stand', {'on': on});
}
