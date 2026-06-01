import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'support.dart';

void main() {
  final courier = Courier.instance;
  final mesh = Mesh.instance;

  setUpAll(unlock);

  setUp(() async {
    reset();
    courier.me = Profile(name: 'Bob Stone');
    await mesh.start();
  });

  Future<Community> founded() => mesh.create(name: 'Night Shift', about: 'ops');

  /// Builds a post as [author], then switches back to bob.
  Future<Map<String, dynamic>> as(
    Identity author,
    Community community, {
    Note note = Note.text,
    String text = 'hello',
    Map<String, dynamic> meta = const {},
  }) async {
    become(author);
    final frame = await mesh.compose(
      community,
      channel: community.general,
      note: note,
      text: text,
      meta: meta,
    );
    become(bob);
    return frame;
  }

  test(
    'a new community starts with its founder and a general channel',
    () async {
      final community = await founded();
      expect(community.key, hasLength(32));
      expect(mesh.members(community.id).single.address, bob.address);
      expect(mesh.rooms(community.id).single.name, 'general');
      expect(mesh.ordered().first.id, community.id);
    },
  );

  test('posts from other members verify, forged ones do not', () async {
    final community = await founded();
    final frame = await as(alice, community, text: 'shift starts at 9');
    final post = await mesh.verify(frame);
    expect(post?.author, alice.address);
    expect(post?.text, 'shift starts at 9');
    expect(jsonEncode(frame), isNot(contains('shift starts at 9')));

    expect(await mesh.verify({...frame, 't': (frame['t'] as int) + 1}), isNull);
    expect(await mesh.verify({...frame, 'a': carol.address}), isNull);
    expect(await mesh.verify({...frame, 'c': Courier.token()}), isNull);
  });

  test('members are listed by seniority, founder first', () async {
    final community = await founded();
    await mesh.accept(
      (await mesh.verify(
        await as(carol, community, note: Note.join, text: 'Carol'),
      ))!,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await mesh.accept(
      (await mesh.verify(
        await as(alice, community, note: Note.join, text: 'Alice'),
      ))!,
    );
    expect(mesh.members(community.id).map((item) => item.address), [
      bob.address,
      carol.address,
      alice.address,
    ]);
    expect(mesh.called(community.id, carol.address), 'Carol');
  });

  test('the sync clock stops at the first missing post', () async {
    final community = await founded();
    Post numbered(int seq) => Post(
      id: Courier.token(),
      community: community.id,
      channel: community.general,
      author: alice.address,
      seq: seq,
      time: DateTime.now(),
      note: Note.text,
      text: 'post $seq',
      frame: '{}',
    );
    mesh.index(numbered(1));
    mesh.index(numbered(3));
    expect(mesh.clock(community.id)[alice.address], 1);
    mesh.index(numbered(2));
    expect(mesh.clock(community.id)[alice.address], 3);
  });

  test('invitations are checked before anything is joined', () {
    final good = {
      'community': '0123456789abcdef0123456789abcdef',
      'name': 'Night Shift',
      'key': base64.encode(List.filled(32, 1)),
      'founder': bob.address,
      'created': 1,
    };
    expect(Mesh.valid(good, alice.address)?['by'], alice.address);
    expect(Mesh.valid({...good, 'community': 'nope'}, alice.address), isNull);
    expect(
      Mesh.valid({
        ...good,
        'key': base64.encode([1, 2]),
      }, alice.address),
      isNull,
    );
    expect(Mesh.valid({...good, 'founder': 'x.onion'}, alice.address), isNull);
  });

  test('a member who joined catches up over the wire', () async {
    final community = await founded();
    await mesh.say(community, community.general, 'welcome aboard');
    final join = await as(alice, community, note: Note.join, text: 'Alice');

    final wire = await Wire.open();
    wire.send(
      sealed(
        alice,
        Signal.mesh,
        body: jsonEncode({
          'op': 'have',
          'c': community.id,
          'clock': {},
          'proof': join,
        }),
      ),
    );
    final reply = await wire.incoming.stream
        .firstWhere((frame) => frame['kind'] == 'mesh')
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(reply['body'] as String) as Map;
    expect(body['op'], 'posts');
    final items = (body['items'] as List).cast<Map<String, dynamic>>();
    final texts = [for (final item in items) (await mesh.verify(item))?.text];
    expect(texts, contains('welcome aboard'));
    expect(mesh.member(community.id, alice.address), isTrue);
    await wire.close();
  });

  test('someone who is not a member learns nothing', () async {
    final community = await founded();
    await mesh.say(community, community.general, 'members only');
    final wire = await Wire.open();
    wire.send(
      sealed(
        carol,
        Signal.mesh,
        body: jsonEncode({'op': 'have', 'c': community.id, 'clock': {}}),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(wire.replies.where((frame) => frame['kind'] == 'mesh'), isEmpty);
    await wire.close();
  });

  test('an invitation arrives as an encrypted chat card', () async {
    final community = await founded();
    final wire = await Wire.open();
    final frame = sealed(
      alice,
      Signal.message,
      body: await confide(alice, {
        'kind': 'invite',
        'text': '',
        'meta': mesh.invitation(community),
      }),
    );
    wire.send(frame);
    await wire.reply('receipt', frame['id'] as String);
    final card = courier.threads[alice.address]!.single;
    expect(card.kind, Kind.invite);
    expect(card.meta['by'], alice.address);
    expect(card.meta['community'], community.id);
    await wire.close();
  });

  test('posts of different lengths look the same size', () async {
    final community = await founded();
    final short = await as(alice, community, text: 'hi');
    final longer = await as(
      alice,
      community,
      text: 'see everyone at the handoff tonight',
    );
    expect((short['x'] as String).length, (longer['x'] as String).length);
    expect(
      (await mesh.verify(longer))?.text,
      'see everyone at the handoff tonight',
    );
  });

  test('sends wait a short random moment by default', () {
    final pauses = {for (var round = 0; round < 50; round++) Courier.natural()};
    expect(pauses.length, greaterThan(1));
    for (final pause in pauses) {
      expect(pause.inMilliseconds, inInclusiveRange(150, 1200));
    }
  });

  group('removal by vote', () {
    late Community community;
    late Identity dana;

    Future<void> joins(Identity who, String name) async {
      await mesh.accept(
        (await mesh.verify(
          await as(who, community, note: Note.join, text: name),
        ))!,
      );
    }

    Future<void> ballot(
      Identity voter,
      Identity target, {
      bool back = false,
    }) async {
      await mesh.accept(
        (await mesh.verify(
          await as(
            voter,
            community,
            note: Note.vote,
            meta: {'target': target.address, if (back) 'withdraw': true},
          ),
        ))!,
      );
    }

    setUp(() async {
      dana = Identity.fromInput(
        'dana vote ${DateTime.now().microsecondsSinceEpoch}',
      );
      community = await founded();
      await joins(alice, 'Alice');
      await joins(carol, 'Carol');
      await joins(dana, 'Dana');
    });

    test('it takes more than half of everyone else', () async {
      expect(mesh.needed(community.id, carol.address), 2);
      await ballot(alice, carol);
      expect(mesh.member(community.id, carol.address), isTrue);
      expect(mesh.ballots(community.id)[carol.address], {alice.address});
      await ballot(dana, carol);
      expect(mesh.member(community.id, carol.address), isFalse);
      expect(mesh.removed(community.id).keys, [carol.address]);
      expect(mesh.ballots(community.id), isEmpty);
    });

    test('votes can be taken back, and nobody votes on themselves', () async {
      await ballot(alice, carol);
      await ballot(alice, carol, back: true);
      expect(mesh.ballots(community.id), isEmpty);
      await ballot(carol, carol);
      expect(mesh.ballots(community.id), isEmpty);
    });

    test(
      'the deciding vote rotates the key and history stays readable',
      () async {
        final before = community.epoch;
        final old = await as(alice, community, text: 'before the vote');
        await ballot(alice, carol);
        await mesh.vote(community, carol.address);
        expect(mesh.member(community.id, carol.address), isFalse);
        await until(() => community.epoch != before);
        expect(community.keys.keys, containsAll([before, community.epoch]));
        expect((await mesh.verify(old))?.text, 'before the vote');
        final fresh = await as(alice, community, text: 'after the vote');
        expect(fresh['e'], community.epoch);
      },
    );

    test(
      'someone removed gets nothing and their new posts are hidden',
      () async {
        await ballot(alice, carol);
        await ballot(dana, carol);
        await mesh.accept(
          (await mesh.verify(await as(carol, community, text: 'still here?')))!,
        );
        expect(
          mesh
              .messages(community.id, community.general)
              .map((post) => post.text),
          isNot(contains('still here?')),
        );
        final wire = await Wire.open();
        wire.send(
          sealed(
            carol,
            Signal.mesh,
            body: jsonEncode({'op': 'have', 'c': community.id, 'clock': {}}),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(wire.replies.where((frame) => frame['kind'] == 'mesh'), isEmpty);
        await wire.close();
      },
    );

    test('a key handed over by a member is adopted', () async {
      final next = Uint8List.fromList(List.generate(32, (index) => index + 7));
      final id = Community.fingerprint(next);
      final wire = await Wire.open();
      wire.send(
        sealed(
          alice,
          Signal.mesh,
          body: jsonEncode({
            'op': 'rekey',
            'c': community.id,
            'k': await confide(alice, {
              'id': id,
              'key': base64.encode(next),
              'at': DateTime.now().millisecondsSinceEpoch,
            }),
          }),
        ),
      );
      await until(() => community.epoch == id);
      expect(community.key, next);
      await wire.close();
    });

    test('invitations carry every key so new members can read history', () {
      final invitation = Mesh.valid(mesh.invitation(community), alice.address)!;
      expect((invitation['keys'] as Map).keys, contains(community.epoch));
      final forged = Mesh.valid({
        ...mesh.invitation(community),
        'keys': {'0000000000000000': base64.encode(List.filled(32, 3))},
      }, alice.address)!;
      expect(forged['keys'], isEmpty);
    });
  });
}
