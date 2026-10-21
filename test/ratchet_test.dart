import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/sql/ledger.dart';
import 'support.dart';

void main() {
  late Identity lead;
  late Identity follower;

  setUpAll(unlock);

  setUp(() async {
    final pair = [
      Identity.fromInput(
        'ratchet lead ${DateTime.now().microsecondsSinceEpoch}',
      ),
      Identity.fromInput(
        'ratchet other ${DateTime.now().microsecondsSinceEpoch}',
      ),
    ]..sort((alpha, beta) => alpha.address.compareTo(beta.address));
    lead = pair.first;
    follower = pair.last;
    await Ratchet.learn(follower.address, await Ratchet.bundle(follower));
    await Ratchet.learn(lead.address, await Ratchet.bundle(lead));
  });

  Future<Map<String, dynamic>> send(Identity from, Identity to, String text) =>
      Ratchet.seal(from, to.address, utf8.encode(text));

  Future<String> read(
    Identity at,
    Identity from,
    Map<String, dynamic> box,
  ) async => utf8.decode(await Ratchet.open(at, from.address, box));

  test('only the lead can start a session', () async {
    expect(Ratchet.lead(lead, follower.address), isTrue);
    expect(() => send(follower, lead, 'too early'), throwsA(isA<Unpaired>()));
  });

  test('a conversation works in both directions', () async {
    for (var round = 0; round < 3; round++) {
      final first = await send(lead, follower, 'lead $round');
      expect(await read(follower, lead, first), 'lead $round');
      final second = await send(follower, lead, 'follower $round');
      expect(await read(lead, follower, second), 'follower $round');
    }
  });

  test('the opening is repeated until the follower answers', () async {
    final one = await send(lead, follower, 'one');
    final two = await send(lead, follower, 'two');
    expect((one['h'] as Map)['x3dh'], isNotNull);
    expect((two['h'] as Map)['x3dh'], isNotNull);
    expect(await read(follower, lead, one), 'one');
    expect(await read(follower, lead, two), 'two');
    final reply = await send(follower, lead, 'got them');
    expect(await read(lead, follower, reply), 'got them');
    final three = await send(lead, follower, 'three');
    expect((three['h'] as Map)['x3dh'], isNull);
  });

  test('messages can arrive out of order', () async {
    final opening = await send(lead, follower, 'hello');
    await read(follower, lead, opening);
    final boxes = [
      for (var index = 0; index < 5; index++)
        await send(follower, lead, 'message $index'),
    ];
    for (final index in [3, 0, 4, 1, 2]) {
      expect(await read(lead, follower, boxes[index]), 'message $index');
    }
  });

  test('a message opens only once and tampering is caught', () async {
    final box = await send(lead, follower, 'secret');
    expect(await read(follower, lead, box), 'secret');
    expect(() => read(follower, lead, box), throwsA(isA<Unreadable>()));

    final next = await send(lead, follower, 'untouched');
    final sealed = base64.decode(next['c'] as String);
    sealed[0] ^= 0xFF;
    final forged = {'h': next['h'], 'c': base64.encode(sealed)};
    expect(() => read(follower, lead, forged), throwsA(isA<Unreadable>()));
    expect(await read(follower, lead, next), 'untouched');
  });

  test('ciphertext never contains the message', () async {
    final box = await send(lead, follower, 'plainly visible words');
    expect(jsonEncode(box), isNot(contains('plainly visible words')));
  });

  test('the lead can start over and the follower follows', () async {
    final first = await send(lead, follower, 'before');
    await read(follower, lead, first);
    await Ratchet.forget(lead, follower.address);

    final fresh = await send(lead, follower, 'after');
    expect(await read(follower, lead, fresh), 'after');
    final reply = await send(follower, lead, 'still here');
    expect(await read(lead, follower, reply), 'still here');
  });

  test('prekeys rotate weekly and keep old ones for late openings', () async {
    final keys = await Ratchet.prekeys(lead);
    final record = await Ledger.read('prekeys:${lead.address}');
    final stale = Map<String, dynamic>.from(keys.last)
      ..['created'] = DateTime.now()
          .subtract(Ratchet.rotation + const Duration(hours: 1))
          .millisecondsSinceEpoch;
    await Ledger.write('prekeys:${lead.address}', {
      ...record!,
      'keys': [stale],
    });
    final rotated = await Ratchet.prekeys(lead);
    expect(rotated, hasLength(2));
    expect(rotated.last['id'], (stale['id'] as int) + 1);
  });
}
