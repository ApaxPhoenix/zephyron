import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/broadcast.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/ratchet.dart';
import 'support.dart';

void main() {
  final courier = Courier.instance;
  final mesh = Mesh.instance;
  final broadcast = Broadcast.instance;

  setUpAll(unlock);

  setUp(() async {
    reset();
    courier.me = Profile(name: 'Bob Stone');
    await mesh.start();
  });

  Future<(Community, Room)> station() async {
    final community = await mesh.create(name: 'Radio Free');
    final room = await mesh.channel(community, 'weekly', Space.podcast);
    return (community, room);
  }

  /// Makes [who] a member by accepting their join post.
  Future<void> admit(Identity who, Community community) async {
    become(who);
    final frame = await mesh.compose(
      community,
      channel: community.general,
      note: Note.join,
      text: 'Alice',
    );
    become(bob);
    await mesh.accept((await mesh.verify(frame))!);
  }

  test('publishing keeps the audio and posts the episode', () async {
    final (community, room) = await station();
    final audio = pattern(Broadcast.piece * 2 + 100);
    final post = await broadcast.publish(
      community,
      room.id,
      bytes: audio,
      title: 'Pilot',
      duration: const Duration(minutes: 3),
    );
    expect(broadcast.episodes(community.id, room.id).single.text, 'Pilot');
    expect(post.meta['size'], audio.length);
    expect(await broadcast.held(Broadcast.blob(post)), isTrue);
    expect(await broadcast.audio(Broadcast.blob(post)), audio);
  });

  test('members get encrypted pieces, outsiders get nothing', () async {
    final (community, room) = await station();
    final audio = pattern(Broadcast.piece + 10);
    final post = await broadcast.publish(
      community,
      room.id,
      bytes: audio,
      title: 'Pilot',
    );
    final id = Broadcast.blob(post);
    await admit(alice, community);

    final wire = await Wire.open();
    wire.send(
      sealed(
        alice,
        Signal.mesh,
        body: jsonEncode({'op': 'fetch', 'c': community.id, 'b': id, 's': 1}),
      ),
    );
    final reply = await wire.incoming.stream
        .firstWhere((frame) => frame['kind'] == 'mesh')
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(reply['body'] as String) as Map<String, dynamic>;
    expect(body['op'], 'piece');
    final sealed0 = base64.decode(body['d'] as String);
    expect(sealed0, isNot(audio.sublist(Broadcast.piece)));
    final clear = await Ratchet.unchunk(
      await Broadcast.key(community, id),
      1,
      sealed0,
    );
    expect(clear, audio.sublist(Broadcast.piece));
    await wire.close();

    final outsider = await Wire.open();
    outsider.send(
      sealed(
        carol,
        Signal.mesh,
        body: jsonEncode({'op': 'fetch', 'c': community.id, 'b': id, 's': 0}),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(outsider.replies.where((frame) => frame['kind'] == 'mesh'), isEmpty);
    await outsider.close();
  });

  test('an episode nobody has is reported missing', () async {
    final (community, _) = await station();
    await admit(alice, community);
    final wire = await Wire.open();
    wire.send(
      sealed(
        alice,
        Signal.mesh,
        body: jsonEncode({
          'op': 'fetch',
          'c': community.id,
          'b': Courier.token(),
          's': 0,
        }),
      ),
    );
    final reply = await wire.incoming.stream
        .firstWhere((frame) => frame['kind'] == 'mesh')
        .timeout(const Duration(seconds: 5));
    expect((jsonDecode(reply['body'] as String) as Map)['missing'], isTrue);
    await wire.close();
  });

  test('an episode downloads piece by piece from another member', () async {
    final (community, room) = await station();
    await admit(alice, community);
    final audio = pattern(Broadcast.piece * 5 + 321);
    final id = Courier.token();

    // Alice publishes; Bob only has her post.
    become(alice);
    final frame = await mesh.compose(
      community,
      channel: room.id,
      note: Note.episode,
      text: 'From Alice',
      meta: {
        'blob': id,
        'size': audio.length,
        'sha': sha(audio),
        'duration': 1000,
      },
    );
    become(bob);
    final post = (await mesh.verify(frame))!;
    await mesh.accept(post);

    final wire = await Wire.open();
    wire.send(sealed(alice, Signal.ping));
    await until(() => courier.channels[alice.address] != null);

    final serving = wire.incoming.stream
        .where((frame) => frame['kind'] == 'mesh')
        .listen((frame) async {
          final ask = jsonDecode(frame['body'] as String) as Map;
          if (ask['op'] != 'fetch') return;
          final seq = ask['s'] as int;
          final start = seq * Broadcast.piece;
          final end = (start + Broadcast.piece).clamp(0, audio.length);
          wire.send(
            sealed(
              alice,
              Signal.mesh,
              body: jsonEncode({
                'op': 'piece',
                'c': community.id,
                'b': id,
                's': seq,
                'd': base64.encode(
                  await Ratchet.chunk(
                    await Broadcast.key(community, id),
                    seq,
                    audio.sublist(start, end),
                  ),
                ),
              }),
            ),
          );
        });

    await broadcast.download(community, post);
    expect(await broadcast.held(id), isTrue);
    expect(await broadcast.audio(id), audio);
    await serving.cancel();
    await wire.close();
  });
}

String sha(Uint8List bytes) => sha256.convert(bytes).toString();
