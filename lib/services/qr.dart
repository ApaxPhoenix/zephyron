import 'dart:convert';
import 'dart:math';

/// How much of a QR code can be damaged and still read.
enum Correction {
  low(1, 0),
  medium(0, 1),
  quartile(3, 2),
  high(2, 3);

  const Correction(this.bits, this.row);

  /// The level as written into the code's format information.
  final int bits;

  /// The level's row in the capacity tables.
  final int row;
}

/// A QR code, made here from the text it holds, as in ISO/IEC 18004.
///
/// Only byte mode is used, which holds any UTF-8 text. The smallest version
/// that fits is chosen, and of the eight masks the one the standard scores
/// best.
class Qr {
  /// Error correction codewords in each block, by level and version.
  static const List<List<int>> eccs = [
    [
      -1,
      7,
      10,
      15,
      20,
      26,
      18,
      20,
      24,
      30,
      18,
      20,
      24,
      26,
      30,
      22,
      24,
      28,
      30,
      28,
      28,
      28,
      28,
      30,
      30,
      26,
      28,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
    ],
    [
      -1,
      10,
      16,
      26,
      18,
      24,
      16,
      18,
      22,
      22,
      26,
      30,
      22,
      22,
      24,
      24,
      28,
      28,
      26,
      26,
      26,
      26,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
      28,
    ],
    [
      -1,
      13,
      22,
      18,
      26,
      18,
      24,
      18,
      22,
      20,
      24,
      28,
      26,
      24,
      20,
      30,
      24,
      28,
      28,
      26,
      30,
      28,
      30,
      30,
      30,
      30,
      28,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
    ],
    [
      -1,
      17,
      28,
      22,
      16,
      22,
      28,
      26,
      26,
      24,
      28,
      24,
      28,
      22,
      24,
      24,
      30,
      28,
      28,
      26,
      28,
      30,
      24,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
    ],
  ];

  /// Error correction blocks, by level and version.
  static const List<List<int>> blocks = [
    [
      -1,
      1,
      1,
      1,
      1,
      1,
      2,
      2,
      2,
      2,
      4,
      4,
      4,
      4,
      4,
      6,
      6,
      6,
      6,
      7,
      8,
      8,
      9,
      9,
      10,
      12,
      12,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      19,
      20,
      21,
      22,
      24,
      25,
    ],
    [
      -1,
      1,
      1,
      1,
      2,
      2,
      4,
      4,
      4,
      5,
      5,
      5,
      8,
      9,
      9,
      10,
      10,
      11,
      13,
      14,
      16,
      17,
      17,
      18,
      20,
      21,
      23,
      25,
      26,
      28,
      29,
      31,
      33,
      35,
      37,
      38,
      40,
      43,
      45,
      47,
      49,
    ],
    [
      -1,
      1,
      1,
      2,
      2,
      4,
      4,
      6,
      6,
      8,
      8,
      8,
      10,
      12,
      16,
      12,
      17,
      16,
      18,
      21,
      20,
      23,
      23,
      25,
      27,
      29,
      34,
      34,
      35,
      38,
      40,
      43,
      45,
      48,
      51,
      53,
      56,
      59,
      62,
      65,
      68,
    ],
    [
      -1,
      1,
      1,
      2,
      4,
      4,
      4,
      5,
      6,
      8,
      8,
      11,
      11,
      16,
      16,
      18,
      16,
      19,
      21,
      25,
      25,
      25,
      34,
      30,
      32,
      35,
      37,
      40,
      42,
      45,
      48,
      51,
      54,
      57,
      60,
      63,
      66,
      70,
      74,
      77,
      81,
    ],
  ];

  final int version;
  final Correction correction;
  final int mask;

  /// Dark modules, row by row.
  final List<List<bool>> modules;

  Qr._(this.version, this.correction, this.mask, this.modules);

  int get size => modules.length;

  bool dark(int x, int y) => modules[y][x];

  /// Encodes [text], or throws [ArgumentError] when it is too long for any
  /// version at [correction].
  static Qr encode(String text, {Correction correction = Correction.medium}) {
    final data = utf8.encode(text);
    for (var version = 1; version <= 40; version++) {
      final count = version < 10 ? 8 : 16;
      final capacity = capacityOf(version, correction) * 8;
      if (4 + count + data.length * 8 <= capacity) {
        return Weave(version, correction).build(data, count, capacity);
      }
    }
    throw ArgumentError('Too long for a QR code');
  }

  /// Modules left for data and error correction once the fixed patterns
  /// are drawn.
  static int raw(int version) {
    var result = (16 * version + 128) * version + 64;
    if (version >= 2) {
      final align = version ~/ 7 + 2;
      result -= (25 * align - 10) * align - 55;
      if (version >= 7) result -= 36;
    }
    return result;
  }

  /// Data codewords a version holds at a level.
  static int capacityOf(int version, Correction correction) =>
      raw(version) ~/ 8 -
      eccs[correction.row][version] * blocks[correction.row][version];

  /// Where the alignment patterns sit along each axis.
  static List<int> alignments(int version) {
    if (version == 1) return const [];
    final count = version ~/ 7 + 2;
    final size = version * 4 + 17;
    final step = (version * 8 + count * 3 + 5) ~/ (count * 4 - 4) * 2;
    final result = [6];
    for (var at = size - 7; result.length < count; at -= step) {
      result.insert(1, at);
    }
    return result;
  }

  // Arithmetic in GF(2^8) with the polynomial 0x11D, for Reed-Solomon.

  static int multiply(int x, int y) {
    var z = 0;
    for (var bit = 7; bit >= 0; bit--) {
      z = (z << 1) ^ ((z >> 7) * 0x11D);
      z ^= ((y >> bit) & 1) * x;
    }
    return z;
  }

  static List<int> divisor(int degree) {
    final result = List.filled(degree, 0)..[degree - 1] = 1;
    var root = 1;
    for (var step = 0; step < degree; step++) {
      for (var index = 0; index < degree; index++) {
        result[index] = multiply(result[index], root);
        if (index + 1 < degree) result[index] ^= result[index + 1];
      }
      root = multiply(root, 0x02);
    }
    return result;
  }

  static List<int> remainder(List<int> data, List<int> divisor) {
    final result = List.filled(divisor.length, 0, growable: true);
    for (final byte in data) {
      final factor = byte ^ result.removeAt(0);
      result.add(0);
      for (var index = 0; index < result.length; index++) {
        result[index] ^= multiply(divisor[index], factor);
      }
    }
    return result;
  }
}

/// Lays out one QR code.
class Weave {
  final int version;
  final Correction correction;
  final int size;
  final List<List<bool>> modules;
  final List<List<bool>> fixed;

  Weave(this.version, this.correction)
    : size = version * 4 + 17,
      modules = List.generate(
        version * 4 + 17,
        (_) => List.filled(version * 4 + 17, false),
      ),
      fixed = List.generate(
        version * 4 + 17,
        (_) => List.filled(version * 4 + 17, false),
      );

  Qr build(List<int> data, int count, int capacity) {
    final bits = <bool>[];
    void put(int value, int length) {
      for (var bit = length - 1; bit >= 0; bit--) {
        bits.add((value >> bit) & 1 == 1);
      }
    }

    put(0x4, 4);
    put(data.length, count);
    for (final byte in data) {
      put(byte, 8);
    }
    put(0, min(4, capacity - bits.length));
    put(0, (8 - bits.length % 8) % 8);
    final codewords = <int>[
      for (var at = 0; at < bits.length; at += 8)
        bits
            .sublist(at, at + 8)
            .fold<int>(0, (byte, bit) => byte << 1 | (bit ? 1 : 0)),
    ];
    for (var pad = 0xEC; codewords.length < capacity ~/ 8; pad ^= 0xEC ^ 0x11) {
      codewords.add(pad);
    }

    patterns();
    place(interleave(codewords));
    var best = 0;
    var lowest = -1;
    for (var mask = 0; mask < 8; mask++) {
      apply(mask);
      format(mask);
      final score = penalty();
      if (lowest < 0 || score < lowest) {
        best = mask;
        lowest = score;
      }
      apply(mask);
    }
    apply(best);
    format(best);
    return Qr._(version, correction, best, modules);
  }

  void set(int x, int y, bool dark) {
    modules[y][x] = dark;
    fixed[y][x] = true;
  }

  void patterns() {
    for (var index = 0; index < size; index++) {
      set(6, index, index % 2 == 0);
      set(index, 6, index % 2 == 0);
    }
    finder(3, 3);
    finder(size - 4, 3);
    finder(3, size - 4);
    final spots = Qr.alignments(version);
    final last = spots.length - 1;
    for (var row = 0; row < spots.length; row++) {
      for (var column = 0; column < spots.length; column++) {
        final corner =
            (row == 0 && column == 0) ||
            (row == 0 && column == last) ||
            (row == last && column == 0);
        if (!corner) alignment(spots[row], spots[column]);
      }
    }
    format(0);
    stamp();
  }

  void finder(int x, int y) {
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final distance = max(dx.abs(), dy.abs());
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < size && py >= 0 && py < size) {
          set(px, py, distance != 2 && distance != 4);
        }
      }
    }
  }

  void alignment(int x, int y) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        set(x + dx, y + dy, max(dx.abs(), dy.abs()) != 1);
      }
    }
  }

  static bool bit(int value, int index) => (value >> index) & 1 != 0;

  /// The level and mask, protected by a BCH code, in both copies.
  void format(int mask) {
    final data = correction.bits << 3 | mask;
    var rest = data;
    for (var step = 0; step < 10; step++) {
      rest = (rest << 1) ^ ((rest >> 9) * 0x537);
    }
    final bits = (data << 10 | rest) ^ 0x5412;
    for (var index = 0; index <= 5; index++) {
      set(8, index, bit(bits, index));
    }
    set(8, 7, bit(bits, 6));
    set(8, 8, bit(bits, 7));
    set(7, 8, bit(bits, 8));
    for (var index = 9; index < 15; index++) {
      set(14 - index, 8, bit(bits, index));
    }
    for (var index = 0; index < 8; index++) {
      set(size - 1 - index, 8, bit(bits, index));
    }
    for (var index = 8; index < 15; index++) {
      set(8, size - 15 + index, bit(bits, index));
    }
    set(8, size - 8, true);
  }

  /// The version, from version 7 up, in both corners.
  void stamp() {
    if (version < 7) return;
    var rest = version;
    for (var step = 0; step < 12; step++) {
      rest = (rest << 1) ^ ((rest >> 11) * 0x1F25);
    }
    final bits = version << 12 | rest;
    for (var index = 0; index < 18; index++) {
      final dark = bit(bits, index);
      final a = size - 11 + index % 3;
      final b = index ~/ 3;
      set(a, b, dark);
      set(b, a, dark);
    }
  }

  /// Splits the data into blocks, adds each block's error correction, and
  /// interleaves them.
  List<int> interleave(List<int> data) {
    final count = Qr.blocks[correction.row][version];
    final ecc = Qr.eccs[correction.row][version];
    final total = Qr.raw(version) ~/ 8;
    final short = count - total % count;
    final length = total ~/ count;
    final generator = Qr.divisor(ecc);
    final made = <List<int>>[];
    var at = 0;
    for (var index = 0; index < count; index++) {
      final take = length - ecc + (index < short ? 0 : 1);
      final block = data.sublist(at, at + take);
      at += take;
      final check = Qr.remainder(block, generator);
      if (index < short) block.add(0);
      made.add([...block, ...check]);
    }
    return [
      for (var index = 0; index < made[0].length; index++)
        for (var row = 0; row < made.length; row++)
          if (index != length - ecc || row >= short) made[row][index],
    ];
  }

  /// Fills the free modules in the zigzag order the standard sets.
  void place(List<int> data) {
    var index = 0;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (var step = 0; step < size; step++) {
        for (var side = 0; side < 2; side++) {
          final x = right - side;
          final upward = (right + 1) & 2 == 0;
          final y = upward ? size - 1 - step : step;
          if (!fixed[y][x] && index < data.length * 8) {
            modules[y][x] = bit(data[index >> 3], 7 - (index & 7));
            index += 1;
          }
        }
      }
    }
  }

  void apply(int mask) {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final flip = switch (mask) {
          0 => (x + y) % 2 == 0,
          1 => y % 2 == 0,
          2 => x % 3 == 0,
          3 => (x + y) % 3 == 0,
          4 => (x ~/ 3 + y ~/ 2) % 2 == 0,
          5 => x * y % 2 + x * y % 3 == 0,
          6 => (x * y % 2 + x * y % 3) % 2 == 0,
          _ => ((x + y) % 2 + x * y % 3) % 2 == 0,
        };
        if (flip && !fixed[y][x]) modules[y][x] = !modules[y][x];
      }
    }
  }

  /// The standard's score for how hard a mask makes the code to read.
  int penalty() {
    var result = 0;
    for (final across in [true, false]) {
      for (var line = 0; line < size; line++) {
        var color = false;
        var run = 0;
        final history = List.filled(7, 0, growable: true);
        for (var along = 0; along < size; along++) {
          final dark = across ? modules[line][along] : modules[along][line];
          if (dark == color) {
            run += 1;
            if (run == 5) {
              result += 3;
            } else if (run > 5) {
              result += 1;
            }
          } else {
            record(run, history);
            if (!color) result += finders(history) * 40;
            color = dark;
            run = 1;
          }
        }
        if (color) {
          record(run, history);
          run = 0;
        }
        record(run + size, history);
        result += finders(history) * 40;
      }
    }
    for (var y = 0; y < size - 1; y++) {
      for (var x = 0; x < size - 1; x++) {
        final color = modules[y][x];
        if (color == modules[y][x + 1] &&
            color == modules[y + 1][x] &&
            color == modules[y + 1][x + 1]) {
          result += 3;
        }
      }
    }
    final dark = modules.fold<int>(
      0,
      (sum, row) => sum + row.where((item) => item).length,
    );
    final total = size * size;
    result += (((dark * 20 - total * 10).abs() + total - 1) ~/ total - 1) * 10;
    return result;
  }

  void record(int run, List<int> history) {
    if (history[0] == 0) run += size;
    history
      ..removeLast()
      ..insert(0, run);
  }

  int finders(List<int> history) {
    final unit = history[1];
    final core =
        unit > 0 &&
        history[2] == unit &&
        history[3] == unit * 3 &&
        history[4] == unit &&
        history[5] == unit;
    return (core && history[0] >= unit * 4 && history[6] >= unit ? 1 : 0) +
        (core && history[6] >= unit * 4 && history[0] >= unit ? 1 : 0);
  }
}
