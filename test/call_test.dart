import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/services/stage.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final courier = Courier.instance;
  final stage = Stage.instance;
  final dana = Identity.fromInput('dana call test seed');

  setUpAll(unlock);

  setUp(() async {
    reset();
    stage.reset();
    Stage.patience = const Duration(seconds: 45);
    courier.prefs = Preferences();
    courier.me = Profile(name: 'Bob Stone');
    courier.roster[alice.address] = Trustee(address: alice.address);
    await Mesh.instance.start();
  });

  tearDown(() => stage.leave());

  Int16List tone(int seed) {
    final random = Random(seed);
    return Int16List.fromList(
      List.generate(
        Stage.frame,
        (index) => (sin(index / 6) * 12000 + random.nextInt(400) - 200).round(),
      ),
    );
  }

  /// What came back over [wire] for the call signal with [op], whether it
  /// already arrived or is still on its way.
  Future<Map> heard(Wire wire, String op) {
    Map? match(Map<String, dynamic> frame) {
      if (frame['kind'] != 'call') return null;
      final body = jsonDecode(frame['body'] as String) as Map;
      return body['op'] == op ? body : null;
    }

    for (final frame in wire.replies) {
      final found = match(frame);
      if (found != null) return Future.value(found);
    }
    return wire.incoming.stream
        .map(match)
        .firstWhere((body) => body != null)
        .then((body) => body!)
        .timeout(const Duration(seconds: 5));
  }

  /// Alice rings this phone over [wire] and returns the call's id and key.
  Future<(String, Uint8List)> ring(Wire wire, {Identity? from}) async {
    final caller = from ?? alice;
    final id = Courier.token();
    final key = Ratchet.random(32);
    wire.send(
      sealed(
        caller,
        Signal.call,
        body: jsonEncode({
          'op': 'ring',
          'r': id,
          'k': await confide(caller, {'call': id, 'key': base64.encode(key)}),
        }),
      ),
    );
    return (id, key);
  }

  List<Message> calls(Identity who) => [
    for (final message in courier.threads[who.address] ?? const <Message>[])
      if (message.kind == Kind.call) message,
  ];

  test('a call key opens only its own call\'s speech', () async {
    final key = Ratchet.random(32);
    final packet = await Stage.seal(
      await Stage.line(key, 'call-1'),
      'direct',
      'call-1',
      alice.address,
      0,
      tone(1),
    );
    final secret = await Stage.line(key, 'call-1');
    expect(
      await Stage.unseal(secret, 'direct', alice.address, packet),
      hasLength(Stage.frame),
    );
    expect(await Stage.unseal(secret, 'direct', carol.address, packet), isNull);
    expect(
      await Stage.unseal(
        await Stage.line(key, 'call-2'),
        'direct',
        alice.address,
        packet,
      ),
      isNull,
    );
  });

  test('a trustee rings, and a call they give up on is missed', () async {
    final wire = await Wire.open();
    final (id, _) = await ring(wire);
    await until(() => stage.ringing != null);
    expect(stage.ringing!.from, alice.address);
    expect(stage.ringing!.direct, isTrue);

    wire.send(
      sealed(alice, Signal.call, body: jsonEncode({'op': 'hangup', 'r': id})),
    );
    await until(() => stage.ringing == null);
    await until(() => calls(alice).isNotEmpty);
    final missed = calls(alice).single;
    expect(missed.mine, isFalse);
    expect(missed.preview, 'Missed call');
    expect(missed.status, Status.delivered);
    await wire.close();
  });

  test('strangers cannot ring this phone', () async {
    final wire = await Wire.open();
    await ring(wire, from: dana);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(stage.ringing, isNull);
    await wire.close();
  });

  test('do not disturb turns a call away and notes it', () async {
    courier.me.availability = Availability.busy;
    final wire = await Wire.open();
    final (id, _) = await ring(wire);
    final reply = await heard(wire, 'busy');
    expect(reply['r'], id);
    expect(stage.ringing, isNull);
    await until(() => calls(alice).isNotEmpty);
    await wire.close();
  });

  test(
    'answering connects, speech is heard, and hanging up notes the call',
    () async {
      final wire = await Wire.open();
      final (id, key) = await ring(wire);
      await until(() => stage.ringing != null);
      expect(await stage.pickUp(), isTrue);
      expect(stage.direct, isTrue);
      expect(stage.connected, isNotNull);
      expect((await heard(wire, 'answer'))['r'], id);

      for (var seq = 0; seq < 2; seq++) {
        wire.send(
          sealed(
            alice,
            Signal.call,
            body: jsonEncode(
              await Stage.seal(
                await Stage.line(key, id),
                'direct',
                id,
                alice.address,
                seq,
                tone(seq),
              ),
            ),
          ),
        );
      }
      await until(() => (stage.buffers[alice.address]?.length ?? 0) == 2);

      wire.send(
        sealed(alice, Signal.call, body: jsonEncode({'op': 'hangup', 'r': id})),
      );
      await until(() => !stage.joined);
      expect(stage.ended, 'ended');
      await until(() => calls(alice).isNotEmpty);
      expect(calls(alice).single.preview, startsWith('Voice call'));
      await wire.close();
    },
  );

  test('ringing a trustee seals the call key for them alone', () async {
    await pairUp(bob, alice);
    final wire = await Wire.open();
    wire.send(sealed(alice, Signal.ping));
    await until(() => courier.channels[alice.address] != null);

    expect(await stage.dial(alice.address), isTrue);
    final rang = await heard(wire, 'ring');
    final inner =
        jsonDecode(
              utf8.decode(
                await Ratchet.open(
                  alice,
                  bob.address,
                  jsonDecode(rang['k'] as String) as Map<String, dynamic>,
                ),
              ),
            )
            as Map;
    expect(inner['call'], rang['r']);
    expect(base64.decode(inner['key'] as String), stage.secret);
    expect(stage.connected, isNull);

    wire.send(
      sealed(
        alice,
        Signal.call,
        body: jsonEncode({'op': 'answer', 'r': rang['r']}),
      ),
    );
    await until(() => stage.connected != null);
    await stage.leave();
    expect((await heard(wire, 'hangup'))['r'], rang['r']);
    await until(() => calls(alice).isNotEmpty);
    expect(calls(alice).single.mine, isTrue);
    await wire.close();
  });

  test('a call nobody answers gives up', () async {
    Stage.patience = const Duration(milliseconds: 300);
    await pairUp(bob, alice);
    final wire = await Wire.open();
    wire.send(sealed(alice, Signal.ping));
    await until(() => courier.channels[alice.address] != null);

    await stage.dial(alice.address);
    await until(() => !stage.joined);
    expect(stage.ended, 'unanswered');
    await until(() => calls(alice).isNotEmpty);
    expect(calls(alice).single.preview, 'No answer');
    await wire.close();
  });
}
