import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/services/courier.dart';

class Avatar extends StatelessWidget {
  final String label;
  final double size;
  final Uint8List? image;
  final bool? online;
  final Availability availability;

  const Avatar({
    super.key,
    required this.label,
    this.size = 48.0,
    this.image,
    this.online,
    this.availability = Availability.available,
  });

  static Color tone(Availability availability) {
    return switch (availability) {
      Availability.available => const Color(0xFF34C759),
      Availability.away => const Color(0xFFFFB020),
      Availability.busy => const Color(0xFFFF453A),
      Availability.invisible => const Color(0xFF8E8E93),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final words = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? '?'
        : words.length == 1
        ? words.first.characters.first.toUpperCase()
        : (words[0].characters.first + words[1].characters.first).toUpperCase();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey(image?.length ?? initials),
              width: size,
              height: size,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHigh,
                border: Border.all(color: scheme.outline),
              ),
              child: image != null
                  ? Image.memory(
                      image!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth:
                          (size * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : Text(
                      initials,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: size * 0.36,
                      ),
                    ),
            ),
          ),
          if (online != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online! ? tone(availability) : scheme.outline,
                  border: Border.all(color: scheme.surface, width: size * 0.05),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class Portrait extends StatelessWidget {
  final String address;
  final double size;
  final bool presence;

  const Portrait({
    super.key,
    required this.address,
    this.size = 48.0,
    this.presence = true,
  });

  @override
  Widget build(BuildContext context) {
    final courier = Courier.instance;
    final trustee = courier.roster[address];
    return Avatar(
      label: trustee?.label ?? address,
      size: size,
      image: trustee?.avatar,
      availability: trustee?.availability ?? Availability.available,
      online: presence && courier.online(address) ? true : null,
    );
  }
}

/// Status mark in the style of a chat app: a dot, a moon, a bar or a ring.
class Glyph extends StatelessWidget {
  final Availability availability;
  final double size;

  const Glyph({super.key, required this.availability, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Icon(
      switch (availability) {
        Availability.available => Icons.circle,
        Availability.away => Icons.nightlight_round,
        Availability.busy => Icons.remove_circle,
        Availability.invisible => Icons.circle_outlined,
      },
      size: size,
      color: Avatar.tone(availability),
    );
  }
}

/// A profile banner: the picture or animated GIF someone chose, or the brand
/// gradient when they have none.
class Cover extends StatelessWidget {
  final Uint8List? banner;
  final double height;
  final BorderRadius radius;

  const Cover({
    super.key,
    required this.banner,
    this.height = 120,
    this.radius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          // Fill the frame, so the picture covers it and the gradient shows.
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: banner != null
              ? Image.memory(
                  banner!,
                  key: ValueKey(banner!.length),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              : DecoratedBox(
                  key: const ValueKey('gradient'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary,
                        scheme.secondary.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
