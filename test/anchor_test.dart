import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/sql/database.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('the same passphrase gives a different secret on another phone', () {
    final here = List<int>.filled(32, 1);
    final elsewhere = List<int>.filled(32, 2);
    const passphrase = 'Correct horse battery staple';
    expect(Database.bind(passphrase, here), Database.bind(passphrase, here));
    expect(
      Database.bind(passphrase, here),
      isNot(Database.bind(passphrase, elsewhere)),
    );
    expect(Database.bind(passphrase, here), isNot(contains(passphrase)));
  });

  test('anchors are kept per identity and remember their migration', () async {
    expect(await Database.anchor('personal'), isNull);

    final pending = await Database.forge('personal', bound: false);
    final read = await Database.anchor('personal');
    expect(read!.value, pending);
    expect(read.bound, isFalse);

    await Database.settle('personal', pending);
    expect((await Database.anchor('personal'))!.bound, isTrue);

    final other = await Database.forge('work', bound: true);
    expect(other, isNot(pending));
    expect((await Database.anchor('personal'))!.value, pending);
  });
}
