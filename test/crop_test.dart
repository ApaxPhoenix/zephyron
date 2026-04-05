import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zephyron/widgets/crop.dart';

Uint8List photo(int width, int height) {
  final canvas = img.Image(width: width, height: height);
  for (final pixel in canvas) {
    pixel
      ..r = pixel.x * 255 ~/ width
      ..g = pixel.y * 255 ~/ height
      ..b = 128;
  }
  return img.encodeJpg(canvas);
}

Uint8List noisy(int width, int height, int frames) {
  final random = Random(7);
  final animation = img.Image(width: width, height: height);
  for (var index = 0; index < frames; index++) {
    final frame = index == 0
        ? animation
        : img.Image(width: width, height: height);
    for (final pixel in frame) {
      pixel
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    if (index > 0) animation.addFrame(frame);
  }
  return img.encodeGif(animation);
}

void main() {
  test('an avatar crop is a square of the requested width', () {
    final result = Cropper.cut(
      photo(800, 600),
      const Rect.fromLTWH(100, 0, 600, 600),
      512,
      1,
    );
    final decoded = img.decodeJpg(result)!;
    expect(decoded.width, 512);
    expect(decoded.height, 512);
  });

  test('a banner crop keeps its three to one shape', () {
    final result = Cropper.cut(
      photo(1200, 900),
      const Rect.fromLTWH(0, 200, 1200, 400),
      960,
      3,
    );
    final decoded = img.decodeJpg(result)!;
    expect(decoded.width, 960);
    expect(decoded.height, 320);
  });

  test('a crop that strays past the edge is kept inside the picture', () {
    final result = Cropper.cut(
      photo(400, 400),
      const Rect.fromLTWH(-20, -20, 500, 500),
      256,
      1,
    );
    expect(img.decodeJpg(result)!.width, 256);
  });

  test('oversized GIF banners shrink but keep their animation', () {
    final big = noisy(640, 213, 3);
    const limit = 120 * 1024;
    expect(big.length, greaterThan(limit));
    expect(Cropper.animated(big), isTrue);

    final small = Cropper.shrink(big, limit)!;
    expect(small.length, lessThanOrEqualTo(limit));
    final decoded = img.decodeGif(small)!;
    expect(decoded.numFrames, 3);
    expect(decoded.width, lessThan(640));
  });

  test('a GIF that already fits is left alone', () {
    final tiny = noisy(60, 20, 2);
    expect(identical(Cropper.shrink(tiny, 1024 * 1024), tiny), isTrue);
    expect(Cropper.animated(photo(10, 10)), isFalse);
  });
}
