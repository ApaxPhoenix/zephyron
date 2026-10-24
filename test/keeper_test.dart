import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/keeper.dart';
import 'package:zephyron/sql/ledger.dart';
import 'support.dart';

void main() {
  final courier = Courier.instance;
  final keeper = Keeper.instance;

  setUpAll(unlock);

  setUp(() async {
    reset();
    courier.preferences = Preferences();
    courier.kept = null;
    courier.roster[alice.address] = Trustee(address: alice.address);
    await Keeper.wipe();
    await keeper.prepare();
    keeper.begin();
  });

  Map<String, dynamic> frame(String id, {String kind = 'message'}) => {
    'v': Courier.protocol,
    'kind': kind,
    'id': id,
    'from': alice.address,
    'to': bob.address,
    'time': DateTime.now().millisecondsSinceEpoch,
    'body': 'sealed',
  };

  test('held frames open again only with the store\'s holding key', () async {
    expect(await keeper.hold(bob.address, frame('one')), isTrue);
    expect(await keeper.hold(bob.address, frame('two')), isTrue);
    final file = await Keeper.file(bob.address);
    expect(await file.readAsString(), isNot(contains(alice.address)));

    final released = await keeper.release(bob.address);
    expect(released.map((item) => item['id']), ['one', 'two']);
    expect(await file.exists(), isFalse);
    expect(await keeper.release(bob.address), isEmpty);
  });

  test('duplicates are noticed and floods are capped', () async {
    expect(await keeper.hold(bob.address, frame('same')), isTrue);
    expect(await keeper.hold(bob.address, frame('same')), isNull);
    for (var index = 1; index < Keeper.share; index++) {
      await keeper.hold(bob.address, frame('flood$index'));
    }
    expect(await keeper.hold(bob.address, frame('one too many')), isFalse);
    expect(keeper.messages, Keeper.share);
  });

  test('a different holding key cannot open what was held', () async {
    await keeper.hold(bob.address, frame('secret'));
    await Ledger.remove('holding');
    await keeper.prepare();
    expect(await keeper.release(bob.address), isEmpty);
  });

  test(
    'a locked phone keeps a message, says so, and reads it at unlock',
    () async {
      await introduce(alice, bob);
      final message = sealed(
        alice,
        Signal.message,
        body: await confide(alice, {
          'kind': 'text',
          'text': 'while you were locked',
        }),
      );
      final typing = sealed(alice, Signal.typing);
      await courier.stop(keep: true);
      expect(courier.kept, bob.address);
      expect(courier.self, isNull);

      final wire = await Wire.open();
      wire.send(typing);
      wire.send(message);
      final kept = await wire.reply('kept', message['id'] as String);
      expect(kept['sig'], isNull);
      expect(courier.threads, isEmpty);
      await wire.close();

      become(bob);
      courier.kept = null;
      courier.roster[alice.address] = Trustee(address: alice.address);
      await courier.resume();
      final thread = courier.threads[alice.address]!;
      expect(thread.single.text, 'while you were locked');
      expect(await keeper.release(bob.address), isEmpty);
    },
  );

  test('a locked phone ignores frames for anyone else or not signed', () async {
    final stranger = {...frame('forged'), 'sig': 'nope', 'key': 'nope'};
    final elsewhere = sealed(
      alice,
      Signal.message,
      to: carol,
      body: 'not for bob',
    );
    await courier.stop(keep: true);
    final wire = await Wire.open();
    wire.send(stranger);
    wire.send(elsewhere);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(wire.replies.where((item) => item['kind'] == 'kept'), isEmpty);
    await wire.close();
    become(bob);
    courier.kept = null;
    expect(await keeper.release(bob.address), isEmpty);
  });

  test('only a phone this one dialed can say it kept a message', () async {
    final mine = Message(
      id: Courier.token(),
      peer: alice.address,
      mine: true,
      text: 'are you there?',
      time: DateTime.now(),
      status: Status.sent,
    );
    await courier.enqueue(mine);

    final inbound = await Wire.open();
    inbound.send({'v': Courier.protocol, 'kind': 'kept', 'id': mine.id});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(mine.status, Status.sent);
    await inbound.close();

    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );
    final server = await listener.first;
    await listener.close();
    courier.adopt(Channel(server, peer: alice.address), server);
    client.write(
      '${jsonEncode({'v': Courier.protocol, 'kind': 'kept', 'id': mine.id})}\n',
    );
    await until(() => mine.status == Status.delivered);
    client.destroy();
    server.destroy();
  });
}
