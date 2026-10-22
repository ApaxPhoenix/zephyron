import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/services/qr.dart';
import 'package:zephyron/widgets/qr.dart';

void main() {
  /// Reads the 15 format bits back out of the first copy, beside the
  /// top-left finder.
  int format(Qr code) {
    var bits = 0;
    void take(int x, int y, int index) {
      if (code.dark(x, y)) bits |= 1 << index;
    }

    for (var index = 0; index <= 5; index++) {
      take(8, index, index);
    }
    take(8, 7, 6);
    take(8, 8, 7);
    take(7, 8, 8);
    for (var index = 9; index < 15; index++) {
      take(14 - index, 8, index);
    }
    return bits;
  }

  /// The format bits for [level] and [mask], as the standard defines them.
  int bch(Correction level, int mask) {
    final data = level.bits << 3 | mask;
    var rest = data;
    for (var step = 0; step < 10; step++) {
      rest = (rest << 1) ^ ((rest >> 9) * 0x537);
    }
    return (data << 10 | rest) ^ 0x5412;
  }

  test('format information matches the standard\'s table', () {
    // ISO/IEC 18004 table C.1, for mask 0 at each level.
    const table = {
      Correction.low: 0x77C4,
      Correction.medium: 0x5412,
      Correction.quartile: 0x355F,
      Correction.high: 0x1689,
    };
    for (final entry in table.entries) {
      expect(bch(entry.key, 0), entry.value, reason: '${entry.key}');
      final code = Qr.encode('zephyron', correction: entry.key);
      expect(format(code), bch(entry.key, code.mask), reason: '${entry.key}');
    }
  });

  test('the version is written from version 7 on', () {
    final code = Qr.encode('x' * 140, correction: Correction.low);
    expect(code.version, 7);
    var bits = 0;
    for (var index = 0; index < 18; index++) {
      if (code.dark(code.size - 11 + index % 3, index ~/ 3)) {
        bits |= 1 << index;
      }
    }
    expect(bits, 0x07C94, reason: 'ISO/IEC 18004 table D.1');
  });

  test('alignment patterns sit where the standard puts them', () {
    expect(Qr.alignments(1), isEmpty);
    expect(Qr.alignments(2), [6, 18]);
    expect(Qr.alignments(7), [6, 22, 38]);
    expect(Qr.alignments(32), [6, 34, 60, 86, 112, 138]);
    expect(Qr.alignments(40), [6, 30, 58, 86, 114, 142, 170]);
  });

  test('byte capacities match the standard', () {
    int bytes(int version, Correction level) =>
        (Qr.capacityOf(version, level) * 8 - 4 - (version < 10 ? 8 : 16)) ~/ 8;
    expect(bytes(1, Correction.low), 17);
    expect(bytes(1, Correction.medium), 14);
    expect(bytes(1, Correction.quartile), 11);
    expect(bytes(1, Correction.high), 7);
    expect(bytes(10, Correction.medium), 213);
    expect(bytes(15, Correction.high), 220);
    expect(bytes(40, Correction.low), 2953);
    expect(bytes(40, Correction.medium), 2331);
    expect(bytes(40, Correction.quartile), 1663);
    expect(bytes(40, Correction.high), 1273);
    expect(
      () => Qr.encode('x' * 2954, correction: Correction.low),
      throwsArgumentError,
    );
  });

  test('codes stay exactly as checked against a reference encoder', () {
    // Each matched another implementation module for module when written.
    for (final (text, level, version, mask, digest) in [
      (
        'zephyron://add/abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx?name=Bob',
        Correction.medium,
        5,
        2,
        '3e7aa00a97f12f3a158c6dd57eae8b565a7e371119822449581698b751a0cbbc',
      ),
      (
        'Hello, wörld ✓',
        Correction.high,
        3,
        3,
        '65a2ed2ce8bfeaf99a92f0df2319d1b56068165cc9c0ba58f327ed5da823c06e',
      ),
      (
        'a' * 400,
        Correction.low,
        13,
        1,
        'ef9a060efb3ffa912af3fa3336a855a89927220d028fd1f641baa2d97912c485',
      ),
    ]) {
      final code = Qr.encode(text, correction: level);
      expect(code.version, version);
      expect(code.mask, mask);
      final bits = code.modules
          .map((row) => row.map((dark) => dark ? '1' : '0').join())
          .join();
      expect(sha256.convert(utf8.encode(bits)).toString(), digest);
    }
  });

  testWidgets('the widget draws a code at the size asked for', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: QrCode(data: 'zephyron', size: 180, eyes: Colors.blue),
        ),
      ),
    );
    expect(tester.getSize(find.byType(QrCode)), const Size(180, 180));
    expect(find.bySemanticsLabel('QR code'), findsOneWidget);
  });
}
