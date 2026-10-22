import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/stage.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final courier = Courier.instance;
  final mesh = Mesh.instance;
  final stage = Stage.instance;

  setUpAll(unlock);

  setUp(() async {
    reset();
    courier.me = Profile(name: 'Bob Stone');
    await mesh.start();
  });

  tearDown(() => stage.leave());

  Future<(Community, Room)> lounge() async {
    final community = await mesh.create(name: 'Late Night');
    final room = await mesh.channel(community, 'lounge', Space.voice);
    return (community, room);
  }

  Future<void> admit(Identity who, Community community) async {
    become(who);
    final frame = await mesh.compose(
      community,
      channel: community.general,
      note: Note.join,
      text: 'Someone',
    );
    become(bob);
    await mesh.accept((await mesh.verify(frame))!);
  }

  Int16List tone(int seed) {
    final random = Random(seed);
    return Int16List.fromList(
      List.generate(
        Stage.frame,
        (index) => (sin(index / 6) * 12000 + random.nextInt(400) - 200).round(),
      ),
    );
  }

  test('µ-law keeps speech within the codec\'s usual error', () {
    for (final sample in [
      -32000,
      -9000,
      -1000,
      -40,
      0,
      40,
      1000,
      9000,
      32000,
    ]) {
      final back = Stage.stretch(Stage.squeeze(sample));
      expect(
        (back - sample).abs(),
        lessThanOrEqualTo(max(16, (sample.abs() * 0.04).round())),
        reason: 'sample $sample came back as $back',
      );
    }
    expect(Stage.compress(tone(1)), hasLength(Stage.frame));
  });

  test('packets open only for the right room, sender and order', () async {
    final (community, room) = await lounge();
    final pcm = tone(2);
    final packet = await Stage.pack(community, room.id, alice.address, 7, pcm);
    expect(
      jsonEncode(packet),
      isNot(contains(base64.encode(Stage.compress(pcm)))),
    );

    final heard = await Stage.unpack(community, alice.address, packet);
    expect(heard, hasLength(Stage.frame));
    expect(await Stage.unpack(community, carol.address, packet), isNull);
    expect(
      await Stage.unpack(community, alice.address, {...packet, 'q': 8}),
      isNull,
    );
    expect(
      await Stage.unpack(community, alice.address, {...packet, 'r': 'other'}),
      isNull,
    );
  });

  test('a member joining hears back from people already in the room', () async {
    final (community, room) = await lounge();
    await admit(alice, community);
    expect(await stage.join(community, room.id), isTrue);

    final wire = await Wire.open();
    wire.send(
      sealed(
        alice,
        Signal.mesh,
        body: jsonEncode({
          'op': 'room',
          'c': community.id,
          'r': room.id,
          'state': 'join',
        }),
      ),
    );
    final reply = await wire.incoming.stream
        .where((frame) => frame['kind'] == 'mesh')
        .map((frame) => jsonDecode(frame['body'] as String) as Map)
        .firstWhere((body) => body['op'] == 'room')
        .timeout(const Duration(seconds: 5));
    expect(reply['state'], 'here');
    expect(stage.others, [alice.address]);
    await wire.close();
  });

  test('speech is buffered per speaker, then mixed', () async {
    final (community, room) = await lounge();
    await admit(alice, community);
    await stage.join(community, room.id);

    final wire = await Wire.open();
    final channel = courier.live.last;
    for (var seq = 0; seq < 3; seq++) {
      await stage.receive(
        alice.address,
        channel,
        community,
        await Stage.pack(community, room.id, alice.address, seq, tone(seq)),
      );
    }
    expect(stage.buffers[alice.address], hasLength(3));
    expect(stage.seated(room.id)[alice.address]!.level, greaterThan(0.1));

    final mixed = stage.mix();
    expect(mixed, hasLength(Stage.frame));
    expect(mixed.any((sample) => sample != 0), isTrue);
    expect(stage.buffers[alice.address], hasLength(2));
    await wire.close();
  });

  test('a full room turns new people away', () async {
    final (community, room) = await lounge();
    for (var index = 0; index < Stage.seats - 1; index++) {
      stage.seated(room.id)['peer$index.onion'] = Seat(seen: DateTime.now());
    }
    expect(await stage.join(community, room.id), isFalse);
    expect(stage.joined, isFalse);
    stage.rooms.clear();
  });

  test('the first person in a group call rings everyone else', () async {
    final group = await mesh.create(name: 'Family', group: true);
    await admit(alice, group);
    await admit(carol, group);
    final wire = await Wire.open();
    final channel = courier.live.last;

    Map<String, dynamic> enter(String state) => {
      'op': 'room',
      'c': group.id,
      'r': group.general,
      'state': state,
    };

    await stage.receive(alice.address, channel, group, enter('join'));
    expect(stage.ringing?.community, group.id);
    expect(stage.ringing?.from, alice.address);

    stage.silence();
    await stage.receive(carol.address, channel, group, enter('join'));
    expect(stage.ringing, isNull, reason: 'the call had already started');

    await stage.receive(carol.address, channel, group, enter('leave'));
    await stage.receive(alice.address, channel, group, enter('leave'));
    await stage.receive(alice.address, channel, group, enter('join'));
    expect(stage.ringing, isNotNull);
    await stage.receive(alice.address, channel, group, enter('leave'));
    expect(stage.ringing, isNull, reason: 'nobody is left on the call');

    group.muted = true;
    await stage.receive(alice.address, channel, group, enter('join'));
    expect(stage.ringing, isNull, reason: 'a muted group does not ring');
    stage.rooms.clear();
    await wire.close();
  });

  test('voice channels in communities never ring', () async {
    final (community, room) = await lounge();
    await admit(alice, community);
    final wire = await Wire.open();
    await stage.receive(alice.address, courier.live.last, community, {
      'op': 'room',
      'c': community.id,
      'r': room.id,
      'state': 'join',
    });
    expect(stage.ringing, isNull);
    expect(stage.seated(room.id).keys, contains(alice.address));
    stage.rooms.clear();
    await wire.close();
  });
}
