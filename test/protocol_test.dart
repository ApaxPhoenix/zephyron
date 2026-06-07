import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/sql/ledger.dart';
import 'support.dart';

void main() {
  final courier = Courier.instance;

  setUpAll(unlock);
  setUp(() {
    reset();
    courier.prefs.strangers = true;
  });

  test(
    'a stranger message is stored, receipted and becomes a request',
    () async {
      final wire = await Wire.open();
      final frame = sealed(
        alice,
        Signal.message,
        body: await confide(alice, {'kind': 'text', 'text': 'hello bob'}),
      );
      wire.send(frame);

      final receipt = await wire.reply('receipt', frame['id'] as String);
      become(alice);
      expect(courier.authentic(receipt), isTrue);
      become(bob);

      expect(courier.roster[alice.address]?.trust, Trust.stranger);
      expect(courier.threads[alice.address]?.single.text, 'hello bob');
      expect(courier.threads[alice.address]?.single.mine, isFalse);
      expect(await Ledger.exists(frame['id'] as String), isTrue);
      await wire.close();
    },
  );

  test('replayed messages are acknowledged but stored once', () async {
    final wire = await Wire.open();
    final frame = sealed(
      alice,
      Signal.message,
      body: await confide(alice, {'kind': 'text', 'text': 'once'}),
    );
    wire.send(frame);
    await wire.reply('receipt', frame['id'] as String);
    wire.replies.clear();
    wire.send(frame);
    await wire.reply('receipt', frame['id'] as String);

    expect(courier.threads[alice.address], hasLength(1));
    await wire.close();
  });

  test('requests are refused when message requests are turned off', () async {
    courier.prefs.strangers = false;
    final wire = await Wire.open();
    final frame = sealed(
      carol,
      Signal.message,
      body: await confide(carol, {'kind': 'text', 'text': 'let me in'}),
    );
    wire.send(frame);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(courier.roster.containsKey(carol.address), isFalse);
    expect(wire.replies.where((item) => item['kind'] == 'receipt'), isEmpty);
    await wire.close();
  });

  test('forged frames are ignored', () async {
    final wire = await Wire.open();
    final frame = sealed(
      alice,
      Signal.message,
      body: await confide(alice, {'kind': 'text', 'text': 'genuine'}),
    );
    frame['body'] = await confide(alice, {'kind': 'text', 'text': 'tampered'});
    wire.send(frame);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(courier.threads[alice.address], isNull);
    expect(wire.replies, isEmpty);
    await wire.close();
  });

  test('blocked senders are dropped', () async {
    courier.roster[alice.address] = Trustee(
      address: alice.address,
      trust: Trust.blocked,
    );
    final wire = await Wire.open();
    wire.send(
      sealed(
        alice,
        Signal.message,
        body: await confide(alice, {'kind': 'text', 'text': 'still here?'}),
      ),
    );
    await until(() => wire.closed);

    expect(courier.threads[alice.address], isNull);
    await wire.close();
  });

  test('attachments are reassembled, verified and stored encrypted', () async {
    final wire = await Wire.open();
    final payload = pattern(Courier.slice * 2 + 1234);
    final key = Ratchet.random(32);
    final manifest = sealed(
      alice,
      Signal.file,
      body: await confide(alice, {
        'key': base64.encode(key),
        'kind': 'image',
        'text': 'sunset',
        'name': 'sunset.png',
        'mime': 'image/png',
        'size': payload.length,
        'width': 640,
        'height': 480,
        'sha': sha256.convert(payload).toString(),
      }),
    );
    final id = manifest['id'] as String;
    wire.send(manifest);
    for (var seq = 0, offset = 0; offset < payload.length; seq++) {
      final end = (offset + Courier.slice).clamp(0, payload.length);
      wire.send(await piece(id, key, seq, payload.sublist(offset, end)));
      offset = end;
    }

    await wire.reply('receipt', id);
    final message = courier.threads[alice.address]!.single;
    expect(message.kind, Kind.image);
    expect(message.text, 'sunset');
    expect(message.width, 640);
    expect(message.size, payload.length);

    Locker.cache.clear();
    Locker.cached = 0;
    expect(await Locker.load(message), payload);
    await wire.close();
  });

  test('attachments with a wrong hash are discarded', () async {
    final wire = await Wire.open();
    final payload = pattern(1000);
    final key = Ratchet.random(32);
    final manifest = sealed(
      alice,
      Signal.file,
      body: await confide(alice, {
        'key': base64.encode(key),
        'kind': 'file',
        'name': 'notes.txt',
        'size': payload.length,
        'sha': sha256.convert(pattern(999)).toString(),
      }),
    );
    wire.send(manifest);
    wire.send(await piece(manifest['id'] as String, key, 0, payload));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(courier.threads[alice.address], isNull);
    expect(courier.transfers, isEmpty);
    await wire.close();
  });

  test('trustees receive profiles and read receipts update status', () async {
    courier.roster[alice.address] = Trustee(address: alice.address);
    final mine = Message(
      id: Courier.token(),
      peer: alice.address,
      mine: true,
      text: 'did you see this?',
      time: DateTime.now(),
      status: Status.delivered,
    );
    await courier.enqueue(mine);
    final wire = await Wire.open();

    wire.send(
      sealed(
        alice,
        Signal.profile,
        body: jsonEncode({
          'name': 'Alice',
          'mood': 'reviewing',
          'bio': 'cryptographer',
          'availability': 'away',
          'revision': 42,
        }),
      ),
    );
    wire.send(sealed(alice, Signal.read, body: mine.id));
    await until(
      () =>
          courier.roster[alice.address]!.alias == 'Alice' &&
          mine.status == Status.read,
    );

    final trustee = courier.roster[alice.address]!;
    expect(trustee.label, 'Alice');
    expect(trustee.mood, 'reviewing');
    expect(trustee.availability, Availability.away);
    expect(trustee.revision, 42);
    await wire.close();
  });

  test(
    'pings from trustees are answered, pings from strangers are not',
    () async {
      courier.roster[alice.address] = Trustee(address: alice.address);
      final wire = await Wire.open();
      final ping = sealed(alice, Signal.ping);
      wire.send(ping);
      final pong = await wire.reply('pong', ping['id'] as String);
      expect(pong['from'], bob.address);
      await wire.close();

      final other = await Wire.open();
      other.send(sealed(carol, Signal.ping));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(other.replies.where((item) => item['kind'] == 'pong'), isEmpty);
      await other.close();
    },
  );

  test('a channel cannot switch identities once bound', () async {
    final wire = await Wire.open();
    final first = sealed(
      alice,
      Signal.message,
      body: await confide(alice, {'kind': 'text', 'text': 'from alice'}),
    );
    wire.send(first);
    await wire.reply('receipt', first['id'] as String);
    wire.send(
      sealed(
        carol,
        Signal.message,
        body: await confide(carol, {'kind': 'text', 'text': 'from carol'}),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(courier.threads[carol.address], isNull);
    await wire.close();
  });

  test('timed messages are deleted once their timer runs out', () async {
    courier.roster[alice.address] = Trustee(address: alice.address);
    final wire = await Wire.open();
    final frame = sealed(
      alice,
      Signal.message,
      body: await confide(alice, {
        'kind': 'text',
        'text': 'burn after reading',
        'fuse': 1,
      }),
    );
    wire.send(frame);
    await wire.reply('receipt', frame['id'] as String);

    final message = courier.threads[alice.address]!.single;
    expect(message.fuse, 1);
    await courier.expire();
    expect(courier.threads[alice.address], hasLength(1));

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await courier.expire();
    expect(courier.threads[alice.address], isEmpty);
    expect(await Ledger.exists(frame['id'] as String), isFalse);
    await wire.close();
  });

  test('a trustee can set the chat timer, a stranger cannot', () async {
    courier.roster[alice.address] = Trustee(address: alice.address, fused: 10);
    courier.roster[carol.address] = Trustee(
      address: carol.address,
      trust: Trust.stranger,
    );
    final wire = await Wire.open();
    wire.send(
      sealed(
        alice,
        Signal.timer,
        body: jsonEncode({'fuse': 3600, 'fused': 20}),
      ),
    );
    await until(() => courier.roster[alice.address]!.fuse == 3600);
    expect(courier.timed(alice.address), {'fuse': 3600});

    wire.send(
      sealed(alice, Signal.timer, body: jsonEncode({'fuse': 60, 'fused': 15})),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(courier.roster[alice.address]!.fuse, 3600);
    await wire.close();

    final other = await Wire.open();
    other.send(
      sealed(carol, Signal.timer, body: jsonEncode({'fuse': 60, 'fused': 99})),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(courier.roster[carol.address]!.fuse, 0);
    await other.close();
  });

  test('a timer longer than four weeks is capped', () {
    expect(Courier.clamp(Fuse.ceiling * 10), Fuse.ceiling);
    expect(Courier.clamp(-5), 0);
    expect(Courier.clamp('soon'), 0);
    expect(Fuse.of(4000), Fuse.hour);
  });

  test('trustee banners are stored and oversized ones are refused', () async {
    courier.roster[alice.address] = Trustee(address: alice.address);
    final wire = await Wire.open();
    final picture = List<int>.generate(2048, (index) => index % 251);
    wire.send(
      sealed(
        alice,
        Signal.banner,
        body: jsonEncode({'banner': base64.encode(picture)}),
      ),
    );
    await until(() => courier.roster[alice.address]!.banner != null);
    expect(courier.roster[alice.address]!.banner, picture);

    wire.send(
      sealed(
        alice,
        Signal.banner,
        body: jsonEncode({
          'banner': base64.encode(List<int>.filled(Courier.banner + 1, 1)),
        }),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(courier.roster[alice.address]!.banner, picture);
    await wire.close();
  });

  test('profile frames leave the banner for its own frame', () {
    courier.me
      ..name = 'Bob'
      ..banner = Uint8List.fromList([1, 2, 3]);
    expect(courier.me.toJson(banner: false).containsKey('banner'), isFalse);
    expect(courier.me.toJson()['banner'], base64.encode([1, 2, 3]));
    expect(jsonDecode(courier.cover())['banner'], base64.encode([1, 2, 3]));
    courier.me.banner = null;
  });

  test('unencrypted messages are refused', () async {
    final wire = await Wire.open();
    wire.send(
      sealed(
        alice,
        Signal.message,
        body: jsonEncode({'kind': 'text', 'text': 'in the clear'}),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(courier.threads[alice.address], isNull);
    expect(wire.replies.where((item) => item['kind'] == 'receipt'), isEmpty);
    await wire.close();
  });

  test('a frame that cannot be opened asks for a fresh session', () async {
    final stranger = Identity.fromInput('mend test ${DateTime.now()}');
    final wire = await Wire.open();
    wire.send(
      sealed(
        stranger,
        Signal.message,
        body: jsonEncode({
          'h': {'dh': base64.encode(List.filled(32, 7)), 'n': 0, 'pn': 0},
          'c': base64.encode(List.filled(40, 1)),
        }),
      ),
    );
    final repair = await wire.incoming.stream
        .firstWhere((frame) => frame['kind'] == 'session')
        .timeout(const Duration(seconds: 5));
    expect(courier.threads[stranger.address], isNull);
    final exchange = jsonDecode(repair['body'] as String) as Map;
    expect(exchange['bundle'], isNotNull);
    await wire.close();
  });

  test('a session can be agreed over the wire from either side', () async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final peer = Identity.fromInput('handshake $attempt ${DateTime.now()}');
      final leads = Ratchet.lead(peer, bob.address);
      final wire = await Wire.open();
      final ask = sealed(
        peer,
        Signal.session,
        body: jsonEncode({'bundle': await Ratchet.bundle(peer), 'want': true}),
      );
      wire.send(ask);
      final answer = await wire.incoming.stream
          .firstWhere((frame) => frame['kind'] == 'session')
          .timeout(const Duration(seconds: 5));
      final exchange = jsonDecode(answer['body'] as String) as Map;
      await Ratchet.learn(bob.address, exchange['bundle']);
      if (leads) {
        expect(exchange['init'], isNull);
      } else {
        expect(exchange['init'], isNotNull);
        await Ratchet.open(
          peer,
          bob.address,
          Map<String, dynamic>.from(exchange['init'] as Map),
        );
      }
      final frame = sealed(
        peer,
        Signal.message,
        body: jsonEncode(
          await Ratchet.seal(
            peer,
            bob.address,
            utf8.encode(jsonEncode({'kind': 'text', 'text': 'over the wire'})),
          ),
        ),
      );
      wire.send(frame);
      await wire.reply('receipt', frame['id'] as String);
      expect(courier.threads[peer.address]?.single.text, 'over the wire');
      await wire.close();
    }
  });

  test('outgoing messages open only for the trustee', () async {
    await pairUp(bob, carol);
    final wire = await Wire.open();
    final channel = courier.live.last;
    final body = await courier.whisper(
      carol.address,
      channel,
      utf8.encode('for carol only'),
    );
    expect(body, isNot(contains('for carol only')));
    final clear = await Ratchet.open(
      carol,
      bob.address,
      Map<String, dynamic>.from(jsonDecode(body) as Map),
    );
    expect(utf8.decode(clear), 'for carol only');
    await wire.close();
  });
}
