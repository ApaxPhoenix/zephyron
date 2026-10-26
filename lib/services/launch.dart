import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the app was opened for from outside it: a zephyron:// link, as a
/// phone's camera opens one from a scanned code, or a shortcut on the app
/// icon such as `trustee`. It waits here until an identity is unlocked to
/// act on it.
class Launch {
  static const MethodChannel channel = MethodChannel('links');

  static final ValueNotifier<String?> wanted = ValueNotifier(null);
}
