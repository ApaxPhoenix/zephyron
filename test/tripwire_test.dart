import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/services/tripwire.dart';

void main() {
  late List<String> done;

  setUp(() {
    done = [];
    Tripwire.tripped = false;
    Tripwire.erase = () async => done.add('erase');
    Tripwire.lock = () async => done.add('lock');
    Tripwire.halt = () => done.add('halt');
  });

  test('instrumenting the app erases everything, then quits', () async {
    Tripwire.callback().onHooks!();
    await pumpEventQueue();
    expect(done, ['erase', 'halt']);
  });

  test('an unsafe phone locks the vault, then quits', () async {
    Tripwire.callback().onDebug!();
    await pumpEventQueue();
    expect(done, ['lock', 'halt']);
  });

  test('only the first threat is acted on', () async {
    final callback = Tripwire.callback();
    callback.onPrivilegedAccess!();
    callback.onAppIntegrity!();
    await pumpEventQueue();
    expect(done, ['lock', 'halt']);
  });

  test('the app still quits when the response fails', () async {
    Tripwire.erase = () async => throw StateError('store busy');
    Tripwire.callback().onDeviceBinding!();
    await pumpEventQueue();
    expect(done, ['halt']);
  });
}
