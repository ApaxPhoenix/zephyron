import 'package:flutter/material.dart';
import 'package:zephyron/services/mosaic.dart';

/// A QR code drawn as dots, with round finder eyes in their own color.
class Barcode extends StatelessWidget {
  final String data;
  final double size;
  final Color color;
  final Color eyes;
  final Correction correction;

  const Barcode({
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
          code: Mosaic.encode(data, correction: correction),
          color: color,
          eyes: eyes,
        ),
      ),
    );
  }
}

class Dots extends CustomPainter {
  final Mosaic code;
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
    bool finder(int column, int row) =>
        (column < 7 && row < 7) ||
        (column >= count - 7 && row < 7) ||
        (column < 7 && row >= count - 7);
    for (var row = 0; row < count; row++) {
      for (var column = 0; column < count; column++) {
        if (!code.dark(column, row) || finder(column, row)) continue;
        canvas.drawCircle(
          Offset((column + 0.5) * cell, (row + 0.5) * cell),
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
    for (final (column, row) in [(0, 0), (count - 7, 0), (0, count - 7)]) {
      final center = Offset((column + 3.5) * cell, (row + 3.5) * cell);
      canvas.drawCircle(center, cell * 3, ring);
      canvas.drawCircle(center, cell * 1.5, pupil);
    }
  }

  @override
  bool shouldRepaint(Dots old) =>
      old.code != code || old.color != color || old.eyes != eyes;
}
