import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps what is on screen from leaving the phone.
///
/// On Android this toggles FLAG_SECURE, which blocks screenshots and screen
/// recording and blanks the app in Recents. It starts on before Flutter runs,
/// so the unlock screen is covered too.
class Shield {
  static const MethodChannel link = MethodChannel('zephyron/security');

  static Future<void> apply(bool on) async {
    try {
      await link.invokeMethod<void>('shield', on);
    } on MissingPluginException {
      // Platforms without a native side rely on the curtain alone.
    } catch (error) {
      developer.log(
        'Failed to change screen security',
        name: 'Shield.apply',
        level: 900,
        error: error,
      );
    }
  }
}

/// Covers the app whenever it is not in the foreground, so the app switcher
/// snapshot never shows a conversation.
class Curtain extends StatefulWidget {
  final Widget child;
  final ValueListenable<bool> enabled;

  const Curtain({super.key, required this.child, required this.enabled});

  @override
  State<Curtain> createState() => CurtainState();
}

class CurtainState extends State<Curtain> with WidgetsBindingObserver {
  bool away = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hidden = state != AppLifecycleState.resumed;
    if (hidden != away) setState(() => away = hidden);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: widget.enabled,
      builder: (context, on, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          if (on && away)
            ColoredBox(
              color: scheme.surface,
              child: Center(
                child: Icon(
                  Icons.shield_outlined,
                  size: 56,
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
      child: widget.child,
    );
  }
}
