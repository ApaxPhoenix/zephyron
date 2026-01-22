import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/sql/database.dart' as store;
import 'package:zephyron/sql/ledger.dart';
import 'support.dart';

void main() {
  setUp(unlock);

  Message letter(String id, {Status status = Status.sending}) => Message(
    id: id,
    peer: alice.address,
    mine: true,
    text: 'hi',
    time: DateTime(2026, 1, 1),
    status: status,
  );

  test('locked store refuses access', () async {
    await store.Database.databaseInstance?.close();
    store.Database.databaseInstance = null;
    expect(() => Ledger.base, throwsStateError);
  });

  test('trustees round trip and are forgotten with their history', () async {
    await Ledger.keep(
      Trustee(address: alice.address, nickname: 'Al', pinned: true),
    );
    await Ledger.record(letter('one'));
    expect((await Ledger.trustees()).single.label, 'Al');

    await Ledger.forget(alice.address);
    expect(await Ledger.trustees(), isEmpty);
    expect(await Ledger.everything(), isEmpty);
  });

  test('history ignores duplicates and only ever upgrades status', () async {
    expect(await Ledger.record(letter('two')), isTrue);
    expect(await Ledger.record(letter('two')), isFalse);

    await Ledger.mark('two', Status.read);
    await Ledger.mark('two', Status.sent);
    expect((await Ledger.everything()).single.status, Status.read);

    await Ledger.erase('two');
    expect(await Ledger.exists('two'), isFalse);
  });

  test('attachment metadata survives storage', () async {
    await Ledger.record(
      Message(
        id: 'three',
        peer: alice.address,
        mine: false,
        kind: Kind.file,
        text: '',
        time: DateTime(2026, 1, 1),
        meta: {'name': 'report.pdf', 'size': 2048},
      ),
    );
    final stored = (await Ledger.everything()).single;
    expect(stored.kind, Kind.file);
    expect(stored.name, 'report.pdf');
    expect(stored.size, 2048);
  });

  test('preferences and profile persist as documents', () async {
    expect(await Ledger.read('profile'), isNull);
    await Ledger.write('profile', Profile(name: 'Bob', mood: 'busy').toJson());
    await Ledger.write(
      'preferences',
      Preferences(receipts: false, rating: Rating.g).toJson(),
    );

    expect(Profile.fromJson((await Ledger.read('profile'))!).name, 'Bob');
    final prefs = Preferences.fromJson((await Ledger.read('preferences'))!);
    expect(prefs.receipts, isFalse);
    expect(prefs.rating, Rating.g);
  });

  test('stores from the first messaging build are migrated', () async {
    await store.Database.databaseInstance?.close();
    final legacy = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await legacy.execute(
      'CREATE TABLE contacts (address TEXT PRIMARY KEY, name TEXT, pinned INTEGER, archived INTEGER, pending INTEGER, created INTEGER)',
    );
    await legacy.execute(
      'CREATE TABLE history (id TEXT PRIMARY KEY, peer TEXT, mine INTEGER, text TEXT, time INTEGER, status INTEGER)',
    );
    await legacy.insert('contacts', {
      'address': alice.address,
      'name': 'Alice',
      'pinned': 1,
      'archived': 0,
      'pending': 0,
      'created': 1,
    });
    await legacy.insert('contacts', {
      'address': carol.address,
      'name': '',
      'pinned': 0,
      'archived': 0,
      'pending': 1,
      'created': 2,
    });
    await legacy.insert('history', {
      'id': 'old',
      'peer': alice.address,
      'mine': 0,
      'text': 'from before',
      'time': 5,
      'status': 2,
    });
    store.Database.databaseInstance = legacy;

    await Ledger.ensure();
    final people = {
      for (final item in await Ledger.trustees()) item.address: item,
    };
    expect(people[alice.address]?.trust, Trust.trustee);
    expect(people[alice.address]?.pinned, isTrue);
    expect(people[carol.address]?.trust, Trust.stranger);
    expect((await Ledger.everything()).single.kind, Kind.text);

    await Ledger.ensure();
    expect(await Ledger.trustees(), hasLength(2));
  });
}
