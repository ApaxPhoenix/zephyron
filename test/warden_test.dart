import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/services/warden.dart';

void main() {
  late DateTime now;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    Warden.forget();
    now = DateTime(2026, 10, 21, 12);
    Warden.clock = () => now;
  });

  tearDown(() => Warden.clock = DateTime.now);

  void wait(Duration gap) => now = now.add(gap);

  test('an owner fixing typos is throttled but never purged', () async {
    final guesses = [
      'Correct horse battery',
      'Correct horse batery',
      'Correct hors battery',
      'correct horse battery',
      'Correct horse battery!',
    ];
    for (final guess in guesses) {
      expect(await Warden.record('personal', guess), Verdict.allow);
      wait(const Duration(seconds: 30));
    }
    expect(await Warden.suspicion(), guesses.length);
    expect(
      await Warden.record('personal', 'Correct horse batteryy'),
      Verdict.lockout,
    );
    expect(await Warden.remaining(), isNotNull);
  });

  test(
    'rotating identities with unrelated guesses erases everything',
    () async {
      final names = ['personal', 'work', 'burner'];
      final guesses = [
        'password123',
        'letmein!!',
        'qwertyuiop',
        'dragon2024',
        'monkeyBusiness',
        'trustno1',
        'sunshine77',
        'iloveyou',
        'football9',
        'shadowShadow',
      ];
      Verdict? verdict;
      var tries = 0;
      for (final guess in guesses) {
        tries++;
        verdict = await Warden.record(names[tries % names.length], guess);
        if (verdict == Verdict.purge) break;
        wait(const Duration(minutes: 3));
      }
      expect(verdict, Verdict.purge);
      expect(tries, lessThanOrEqualTo(9));
    },
  );

  test('one passphrase sprayed across identities is caught fast', () async {
    await Warden.record('personal', 'Summer2026!');
    wait(const Duration(seconds: 20));
    await Warden.record('work', 'Summer2026!');
    // 1 for the first, then 1 + 3 spray + 1 switched identity.
    expect(await Warden.suspicion(), 6);
  });

  test('scripted attempts and a wound-back clock add suspicion', () async {
    await Warden.record('personal', 'first guess here');
    wait(const Duration(milliseconds: 500));
    await Warden.record('personal', 'first guess hero');
    // 1, then 1 + 2 for arriving faster than a person can type.
    expect(await Warden.suspicion(), 4);

    now = now.subtract(const Duration(hours: 1));
    await Warden.record('personal', 'first guess herd');
    expect(await Warden.suspicion(), greaterThanOrEqualTo(4 + 9));
  });

  test('a restart between failures still counts against the device', () async {
    await Warden.record('personal', 'Correct horse battery');
    wait(const Duration(seconds: 30));
    Warden.forget();
    await Warden.record('personal', 'Correct horse batery');
    expect(await Warden.suspicion(), 3);
  });

  test('unlocking one identity only forgives that identity', () async {
    await Warden.record('work', 'guess one');
    wait(const Duration(minutes: 1));
    await Warden.record('personal', 'my real one');
    await Warden.absolve('personal');
    expect(await Warden.suspicion(), 1);
  });

  test('nothing derived from a guess is written to disk', () async {
    const guess = 'Very Secret Attempt 42';
    await Warden.record('personal', guess);
    final stored = await const FlutterSecureStorage().readAll();
    final raw = stored[Warden.key]!;
    expect(raw, isNot(contains(guess)));
    expect(raw, isNot(contains(Warden.stamp(guess))));
    expect(raw, isNot(contains('personal')));
  });
}
