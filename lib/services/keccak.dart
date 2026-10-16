import 'dart:typed_data';

/// SHA3-256 from FIPS 202, the hash Tor uses for the checksum in a v3
/// onion address. Written here because neither crypto package has it.
class Keccak {
  static const List<int> constants = [
    0x0000000000000001,
    0x0000000000008082,
    0x800000000000808A,
    0x8000000080008000,
    0x000000000000808B,
    0x0000000080000001,
    0x8000000080008081,
    0x8000000000008009,
    0x000000000000008A,
    0x0000000000000088,
    0x0000000080008009,
    0x000000008000000A,
    0x000000008000808B,
    0x800000000000008B,
    0x8000000000008089,
    0x8000000000008003,
    0x8000000000008002,
    0x8000000000000080,
    0x000000000000800A,
    0x800000008000000A,
    0x8000000080008081,
    0x8000000000008080,
    0x0000000080000001,
    0x8000000080008008,
  ];

  /// How far each lane turns, by column then row.
  static const List<List<int>> turns = [
    [0, 36, 3, 41, 18],
    [1, 44, 10, 45, 2],
    [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56],
    [27, 20, 39, 8, 14],
  ];

  /// Bytes absorbed per permutation for a 256-bit output.
  static const int rate = 136;

  static int rotate(int value, int count) =>
      count == 0 ? value : (value << count) | (value >>> (64 - count));

  /// The SHA3-256 digest of [data].
  static Uint8List digest(List<int> data) {
    final padded = Uint8List(((data.length ~/ rate) + 1) * rate)
      ..setAll(0, data);
    padded[data.length] ^= 0x06;
    padded[padded.length - 1] ^= 0x80;
    final lanes = List<int>.filled(25, 0);
    final view = ByteData.sublistView(padded);
    for (var block = 0; block < padded.length; block += rate) {
      for (var lane = 0; lane < rate ~/ 8; lane++) {
        lanes[lane] ^= view.getUint64(block + lane * 8, Endian.little);
      }
      {
        final columns = List<int>.filled(5, 0);
        final mixed = List<int>.filled(25, 0);
        for (final constant in constants) {
          for (var column = 0; column < 5; column++) {
            columns[column] =
                lanes[column] ^
                lanes[column + 5] ^
                lanes[column + 10] ^
                lanes[column + 15] ^
                lanes[column + 20];
          }
          for (var column = 0; column < 5; column++) {
            final change =
                columns[(column + 4) % 5] ^
                rotate(columns[(column + 1) % 5], 1);
            for (var row = 0; row < 25; row += 5) {
              lanes[column + row] ^= change;
            }
          }
          for (var column = 0; column < 5; column++) {
            for (var row = 0; row < 5; row++) {
              mixed[row + 5 * ((2 * column + 3 * row) % 5)] = rotate(
                lanes[column + 5 * row],
                turns[column][row],
              );
            }
          }
          for (var row = 0; row < 25; row += 5) {
            for (var column = 0; column < 5; column++) {
              lanes[column + row] =
                  mixed[column + row] ^
                  (~mixed[(column + 1) % 5 + row] &
                      mixed[(column + 2) % 5 + row]);
            }
          }
          lanes[0] ^= constant;
        }
      }
    }
    final out = ByteData(32);
    for (var lane = 0; lane < 4; lane++) {
      out.setUint64(lane * 8, lanes[lane], Endian.little);
    }
    return out.buffer.asUint8List();
  }
}
