import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/sql/session.dart';

/// Counts down, then erases every identity on this phone.
///
/// Reached from Settings, from a long press on the unlock screen's title and
/// from the app icon's shortcut menu. The countdown is the only chance to
/// back out; nothing asks for a passphrase.
class PanicPage extends StatefulWidget {
  /// Seconds before the wipe starts.
  static const int grace = 5;

  const PanicPage({super.key});

  @override
  State<PanicPage> createState() => PanicPageState();
}

class PanicPageState extends State<PanicPage> {
  int left = PanicPage.grace;
  bool erasing = false;
  bool erased = false;
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (left <= 1) {
        ticker?.cancel();
        unawaited(wipe());
      }
      if (mounted) setState(() => left -= 1);
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  Future<void> wipe() async {
    if (erasing) return;
    setState(() => erasing = true);
    try {
      await Courier.instance.stop();
      await Session.purge();
      await Session.dispose();
    } catch (error) {
      developer.log(
        'Panic wipe did not finish cleanly',
        name: 'PanicPage.wipe',
        level: 1200,
        error: error,
      );
    }
    if (!mounted) return;
    setState(() => erased = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress =
        (PanicPage.grace - left.clamp(0, PanicPage.grace)) / PanicPage.grace;

    return PopScope(
      canPop: !erasing,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                SizedBox(
                  width: 168,
                  height: 168,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: erasing ? 1 : progress),
                        duration: const Duration(milliseconds: 950),
                        builder: (context, value, _) =>
                            CircularProgressIndicator(
                              value: erased ? 1 : value,
                              strokeWidth: 6,
                              color: scheme.error,
                              backgroundColor: scheme.error.withValues(
                                alpha: 0.12,
                              ),
                            ),
                      ),
                      Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: erased
                              ? Icon(
                                  Icons.check,
                                  key: const ValueKey('done'),
                                  size: 56,
                                  color: scheme.error,
                                )
                              : erasing
                              ? Icon(
                                  Icons.delete_forever_outlined,
                                  key: const ValueKey('busy'),
                                  size: 56,
                                  color: scheme.error,
                                )
                              : Text(
                                  '${left.clamp(1, PanicPage.grace)}',
                                  key: ValueKey(left),
                                  style: theme.textTheme.displayMedium
                                      ?.copyWith(
                                        color: scheme.error,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  erased
                      ? 'Everything is erased'
                      : erasing
                      ? 'Erasing…'
                      : 'Erasing everything',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Every identity, message, attachment and key on this phone will be destroyed. This cannot be undone.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                AnimatedOpacity(
                  opacity: erasing ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: scheme.onSurface,
                      side: BorderSide(color: scheme.outline),
                    ),
                    onPressed: erasing
                        ? null
                        : () {
                            ticker?.cancel();
                            Navigator.of(context).maybePop();
                          },
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
