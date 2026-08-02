import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/sql/ledger.dart';
import 'support.dart';

void main() {
  final courier = Courier.instance;
  late Identity dana;

  setUpAll(unlock);

  setUp(() async {
    reset();
    courier.prefs = Preferences();
    courier.roster[alice.address] = Trustee(address: alice.address);
    dana = Identity.fromInput(
      'dana relay ${DateTime.now().microsecondsSinceEpoch}',
    );
    for (final parcel in await Ledger.parcels()) {
      await Ledger.handed(parcel['id'] as String);
    }
  });

  Map<String, dynamic> parcel(
    Identity from,
    Identity to,
    Map<String, dynamic> frame,
  ) => sealed(
    from,
    Signal.parcel,
    body: jsonEncode({'to': to.address, 'frame': frame}),
  );

  test('a trustee\'s parcel is held and acknowledged', () async {
    final wire = await Wire.open();
    final frame = sealed(
      alice,
      Signal.message,
      to: carol,
      body: 'sealed for carol',
    );
    wire.send(parcel(alice, carol, frame));
    await wire.reply('held', frame['id'] as String);
    expect(await Ledger.parcels(recipient: carol.address), hasLength(1));
    await wire.close();
  });

  test('strangers cannot make this phone hold things', () async {
    final wire = await Wire.open();
    final frame = sealed(dana, Signal.message, to: carol, body: 'spam');
    wire.send(parcel(dana, carol, frame));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(wire.replies.where((item) => item['kind'] == 'held'), isEmpty);
    expect(await Ledger.parcels(), isEmpty);
    await wire.close();
  });

  test('with carrying off, nothing is held', () async {
    courier.prefs.carry = false;
    final wire = await Wire.open();
    wire.send(parcel(alice, carol, sealed(alice, Signal.message, to: carol)));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await Ledger.parcels(), isEmpty);
    await wire.close();
  });

  test('a mailbox holds mail for its owner from anyone', () async {
    courier.prefs.serve = carol.address;
    final wire = await Wire.open();
    final frame = sealed(dana, Signal.message, to: carol, body: 'for carol');
    wire.send(parcel(dana, carol, frame));
    await wire.reply('held', frame['id'] as String);
    expect(await Ledger.parcels(recipient: carol.address), hasLength(1));
    await wire.close();
  });

  test('held parcels are handed over when the recipient comes back', () async {
    final first = await Wire.open();
    final frame = sealed(alice, Signal.message, to: carol, body: 'waiting');
    first.send(parcel(alice, carol, frame));
    await first.reply('held', frame['id'] as String);
    await first.close();

    final carols = await Wire.open();
    carols.send(sealed(carol, Signal.ping));
    final handed = await carols.incoming.stream
        .firstWhere((item) => item['kind'] == 'parcel')
        .timeout(const Duration(seconds: 5));
    final inner = (jsonDecode(handed['body'] as String) as Map)['frame'] as Map;
    expect(inner['id'], frame['id']);
    expect(inner['from'], alice.address);
    var left = await Ledger.parcels(recipient: carol.address);
    for (var round = 0; round < 100 && left.isNotEmpty; round++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      left = await Ledger.parcels(recipient: carol.address);
    }
    expect(left, isEmpty);
    await carols.close();
  });

  test(
    'a relayed message is stored and its receipt goes back the same way',
    () async {
      final relay = await Wire.open();
      final frame = sealed(
        alice,
        Signal.message,
        body: await confide(alice, {
          'kind': 'text',
          'text': 'while you were out',
        }),
      );
      relay.send(parcel(carol, bob, frame));
      final back = await relay.incoming.stream
          .firstWhere((item) => item['kind'] == 'parcel')
          .timeout(const Duration(seconds: 5));
      expect(courier.threads[alice.address]?.single.text, 'while you were out');
      final receipt = (jsonDecode(back['body'] as String) as Map);
      expect(receipt['to'], alice.address);
      expect((receipt['frame'] as Map)['kind'], 'receipt');
      expect((receipt['frame'] as Map)['id'], frame['id']);
      await relay.close();
    },
  );

  test('a relayed receipt marks the message delivered', () async {
    final mine = Message(
      id: Courier.token(),
      peer: alice.address,
      mine: true,
      text: 'did it arrive?',
      time: DateTime.now(),
      status: Status.sent,
    );
    await courier.enqueue(mine);
    final relay = await Wire.open();
    relay.send(parcel(carol, bob, sealed(alice, Signal.receipt, id: mine.id)));
    await until(() => mine.status == Status.delivered);
    await relay.close();
  });

  test('messages for someone unreachable go to an online trustee', () async {
    courier.roster[dana.address] = Trustee(address: dana.address);
    await pairUp(bob, dana);
    final relay = await Wire.open();
    relay.send(sealed(alice, Signal.ping));
    await until(() => courier.channels[alice.address] != null);
    courier.track(alice.address).seen = DateTime.now();

    await courier.enqueue(
      Message(
        id: Courier.token(),
        peer: dana.address,
        mine: true,
        text: 'call me when you are back',
        time: DateTime.now(),
      ),
    );
    await courier.flush(dana.address);
    final handed = await relay.incoming.stream
        .firstWhere((item) => item['kind'] == 'parcel')
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(handed['body'] as String) as Map;
    expect(body['to'], dana.address);
    expect((body['frame'] as Map)['to'], dana.address);
    expect(jsonEncode(body), isNot(contains('call me when you are back')));
    await relay.close();
  });
}
