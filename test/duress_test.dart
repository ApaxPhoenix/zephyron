import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/services/duress.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('nothing matches before a duress passphrase is armed', () async {
    expect(await Duress.armed(), isFalse);
    expect(await Duress.match('anything at all'), isNull);
  });

  test('the duress passphrase opens the decoy and nothing else', () async {
    await Duress.arm(
      'everyday',
      'Real decoy passphrase 1',
      'Under pressure 42',
    );
    expect(await Duress.decoy(), 'everyday');

    final hit = await Duress.match('Under pressure 42');
    expect(hit?.name, 'everyday');
    expect(hit?.passphrase, 'Real decoy passphrase 1');

    expect(await Duress.match('Under pressure 43'), isNull);
    expect(await Duress.match('Real decoy passphrase 1'), isNull);
  });

  test('the decoy passphrase is never stored in the clear', () async {
    await Duress.arm(
      'everyday',
      'Real decoy passphrase 1',
      'Under pressure 42',
    );
    final raw = (await const FlutterSecureStorage().readAll())[Duress.key]!;
    expect(raw, isNot(contains('Real decoy passphrase 1')));
    expect(raw, isNot(contains('Under pressure 42')));
  });

  test('turning it off forgets the decoy', () async {
    await Duress.arm(
      'everyday',
      'Real decoy passphrase 1',
      'Under pressure 42',
    );
    await Duress.disarm();
    expect(await Duress.decoy(), isNull);
    expect(await Duress.match('Under pressure 42'), isNull);
  });
}
