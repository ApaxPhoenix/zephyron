import 'package:flutter/material.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/wrappers/tor.dart';

class Beacon extends StatefulWidget {
  const Beacon({super.key});

  @override
  State<Beacon> createState() => BeaconState();
}

class BeaconState extends State<Beacon> with SingleTickerProviderStateMixin {
  late final AnimationController pulse;

  @override
  void initState() {
    super.initState();
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([
        Courier.instance.reach,
        Sentinel.summon().progress,
      ]),
      builder: (context, _) {
        final reach = Courier.instance.reach.value;
        final progress = Sentinel.summon().progress.value;

        if (reach == Reach.online) {
          if (pulse.isAnimating) pulse.stop();
        } else if (!pulse.isAnimating) {
          pulse.repeat(reverse: true);
        }

        final (Color tone, String text) = switch (reach) {
          Reach.online => (const Color(0xFF46A758), 'Connected'),
          Reach.connecting => (
            const Color(0xFFFFB020),
            progress > 0 && progress < 100
                ? 'Connecting $progress%'
                : 'Connecting',
          ),
          Reach.offline => (scheme.error, 'Offline'),
        };

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: reach == Reach.online
                    ? const AlwaysStoppedAnimation(1.0)
                    : Tween(begin: 0.35, end: 1.0).animate(pulse),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: tone,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  text,
                  key: ValueKey(text),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
