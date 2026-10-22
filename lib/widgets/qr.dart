import 'package:flutter/material.dart';
import 'package:zephyron/services/qr.dart';

/// A QR code drawn as dots, with round finder eyes in their own color.
class QrCode extends StatelessWidget {
  final String data;
  final double size;
  final Color color;
  final Color eyes;
  final Correction correction;

  const QrCode({
    super.key,
    required this.data,
    required this.eyes,
    this.size = 220,
    this.color = const Color(0xFF1A1B21),
    this.correction = Correction.medium,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'QR code',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: Dots(
          code: Qr.encode(data, correction: correction),
          color: color,
          eyes: eyes,
        ),
      ),
    );
  }
}

class Dots extends CustomPainter {
  final Qr code;
  final Color color;
  final Color eyes;

  const Dots({required this.code, required this.color, required this.eyes});

  @override
  void paint(Canvas canvas, Size size) {
    final count = code.size;
    final cell = size.width / count;
    final dot = Paint()
      ..color = color
      ..isAntiAlias = true;
    bool finder(int x, int y) =>
        (x < 7 && y < 7) ||
        (x >= count - 7 && y < 7) ||
        (x < 7 && y >= count - 7);
    for (var y = 0; y < count; y++) {
      for (var x = 0; x < count; x++) {
        if (!code.dark(x, y) || finder(x, y)) continue;
        canvas.drawCircle(
          Offset((x + 0.5) * cell, (y + 0.5) * cell),
          cell * 0.45,
          dot,
        );
      }
    }
    final ring = Paint()
      ..color = eyes
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell
      ..isAntiAlias = true;
    final pupil = Paint()
      ..color = eyes
      ..isAntiAlias = true;
    for (final (x, y) in [(0, 0), (count - 7, 0), (0, count - 7)]) {
      final center = Offset((x + 3.5) * cell, (y + 3.5) * cell);
      canvas.drawCircle(center, cell * 3, ring);
      canvas.drawCircle(center, cell * 1.5, pupil);
    }
  }

  @override
  bool shouldRepaint(Dots old) =>
      old.code != code || old.color != color || old.eyes != eyes;
}
