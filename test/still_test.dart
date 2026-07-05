import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/services/still.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(Still.link, null));

  test('the phone decoder hands back a small thumbnail', () async {
    MethodCall? asked;
    messenger.setMockMethodCallHandler(Still.link, (call) async {
      asked = call;
      return Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);
    });
    final bytes = await Still.grab('/tmp/clip.mp4');
    expect(bytes, [0xFF, 0xD8, 1, 2, 3]);
    expect(asked?.method, 'thumbnail');
    expect((asked?.arguments as Map)['path'], '/tmp/clip.mp4');
  });

  test('oversized thumbnails and missing decoders give nothing', () async {
    messenger.setMockMethodCallHandler(
      Still.link,
      (_) async => Uint8List(Still.ceiling + 1),
    );
    expect(await Still.grab('/tmp/clip.mp4'), isNull);
    messenger.setMockMethodCallHandler(Still.link, null);
    expect(await Still.grab('/tmp/clip.mp4'), isNull);
  });
}
