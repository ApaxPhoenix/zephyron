import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/listing.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/catalog.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/sql/ledger.dart';
import 'support.dart';

void main() {
  final courier = Courier.instance;
  final catalog = Catalog.instance;
  final mesh = Mesh.instance;
  final dana = Identity.fromInput('dana catalog test seed');

  setUpAll(unlock);

  setUp(() async {
    reset();
    courier.prefs = Preferences();
    courier.me = Profile(name: 'Bob Stone', bio: 'Night owl');
    courier.roster[alice.address] = Trustee(address: alice.address);
    for (final id in catalog.listings.keys.toList()) {
      await Ledger.unlist(id);
    }
    await Ledger.remove('catalog');
    await mesh.start();
    await catalog.start();
    await catalog.renewing;
  });

  /// A listing written and signed by [author].
  Future<Map<String, dynamic>> as(
    Identity author,
    Shelf shelf,
    String subject, {
    String name = 'Someone',
    String about = '',
    Map<String, dynamic> invitation = const {},
    bool gone = false,
  }) async {
    become(author);
    try {
      return await catalog.compose(
        shelf,
        subject,
        name: name,
        about: about,
        invitation: invitation,
        gone: gone,
      );
    } finally {
      become(bob);
    }
  }

  /// Signs [frame] again as [author] after a test changed it.
  Map<String, dynamic> resign(Identity author, Map<String, dynamic> frame) {
    become(author);
    frame['g'] = Courier.encode(
      ed25519.sign(courier.secret!, Catalog.canonical(frame)),
    );
    become(bob);
    return frame;
  }

  Map<String, dynamic> keys() {
    final key = Ratchet.random(32);
    return {
      'key': base64.encode(key),
      'keys': <String, String>{},
      'created': DateTime.now().millisecondsSinceEpoch,
    };
  }

  String id() => Courier.token();

  test('a signed listing opens, and any change to it does not', () async {
    final frame = await as(
      alice,
      Shelf.person,
      alice.address,
      name: 'Alice Moreau',
      about: 'Climber',
    );
    final listing = Catalog.check(frame)!;
    expect(listing.name, 'Alice Moreau');
    expect(listing.about, 'Climber');
    expect(listing.author, alice.address);

    expect(Catalog.check({...frame, 'n': 'Mallory'}), isNull);
    expect(
      Catalog.check({...frame, 'a': carol.address, 's': carol.address}),
      isNull,
    );
    expect(Catalog.check(await as(alice, Shelf.person, carol.address)), isNull);

    final stale = resign(alice, {
      ...frame,
      't': DateTime.now()
          .subtract(Catalog.lifetime + const Duration(hours: 1))
          .millisecondsSinceEpoch,
    });
    expect(Catalog.check(stale), isNull);
    final early = resign(alice, {
      ...frame,
      't': DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch,
    });
    expect(Catalog.check(early), isNull);

    final easy = Catalog.difficulty;
    Catalog.difficulty = easy + 12;
    try {
      expect(Catalog.check(frame), isNull);
    } finally {
      Catalog.difficulty = easy;
    }
  });

  test(
    'a newer listing replaces an older one, and a takedown hides it',
    () async {
      final first = await as(alice, Shelf.person, alice.address, name: 'Alice');
      expect(await catalog.accept(Catalog.check(first)!), isTrue);
      final second = await as(
        alice,
        Shelf.person,
        alice.address,
        name: 'Alice M',
      );
      expect(await catalog.accept(Catalog.check(second)!), isTrue);
      expect(catalog.browse(Shelf.person).single.name, 'Alice M');
      expect(await catalog.accept(Catalog.check(first)!), isFalse);

      final gone = await as(alice, Shelf.person, alice.address, gone: true);
      expect(await catalog.accept(Catalog.check(gone)!), isTrue);
      expect(catalog.browse(Shelf.person), isEmpty);
      expect(await catalog.accept(Catalog.check(second)!), isFalse);
    },
  );

  test('a community listing has to carry keys that open it', () async {
    expect(
      Catalog.check(
        await as(alice, Shelf.community, id(), invitation: {'key': 'nope'}),
      ),
      isNull,
    );
    expect(
      Catalog.check(await as(alice, Shelf.community, 'not an id')),
      isNull,
    );
    final good = Catalog.check(
      await as(
        alice,
        Shelf.community,
        id(),
        name: 'Open Mic',
        invitation: keys(),
      ),
    )!;
    expect(good.invitation['founder'], alice.address);
    expect(good.invitation['group'], isFalse);
  });

  test('one person can only list a few communities', () async {
    for (var count = 0; count < Catalog.share; count++) {
      final frame = await as(
        alice,
        Shelf.community,
        id(),
        name: 'Room $count',
        invitation: keys(),
      );
      expect(await catalog.accept(Catalog.check(frame)!), isTrue);
    }
    final extra = await as(
      alice,
      Shelf.community,
      id(),
      name: 'One too many',
      invitation: keys(),
    );
    expect(await catalog.accept(Catalog.check(extra)!), isFalse);
  });

  test('only trustees can hand this phone listings', () async {
    final wire = await Wire.open();
    final frame = await as(carol, Shelf.person, carol.address, name: 'Carol');
    wire.send(
      sealed(
        dana,
        Signal.listing,
        body: jsonEncode({
          'op': 'cards',
          'items': [frame],
        }),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(catalog.listings, isEmpty);
    await wire.close();

    final trusted = await Wire.open();
    trusted.send(
      sealed(
        alice,
        Signal.listing,
        body: jsonEncode({
          'op': 'cards',
          'items': [frame],
        }),
      ),
    );
    await until(() => catalog.browse(Shelf.person).isNotEmpty);
    expect(catalog.browse(Shelf.person).single.author, carol.address);
    await trusted.close();
  });

  test('a trustee is sent the listings it is missing', () async {
    final theirs = await as(carol, Shelf.person, carol.address, name: 'Carol');
    await catalog.accept(Catalog.check(theirs)!);
    courier.prefs.listed = true;
    await catalog.refresh();

    Future<List<String>> offered() async {
      final wire = await Wire.open();
      wire.send(
        sealed(
          alice,
          Signal.listing,
          body: jsonEncode({'op': 'have', 'clock': <String, int>{}}),
        ),
      );
      final reply = await wire.incoming.stream
          .where((item) => item['kind'] == 'listing')
          .map((item) => jsonDecode(item['body'] as String) as Map)
          .firstWhere((item) => item['op'] == 'cards')
          .timeout(const Duration(seconds: 5));
      await wire.close();
      return [
        for (final item in reply['items'] as List) (item as Map)['a'] as String,
      ];
    }

    expect(await offered(), unorderedEquals([bob.address, carol.address]));
    courier.prefs.spread = false;
    expect(await offered(), [bob.address]);
  });

  test('listing yourself publishes, and unlisting takes it down', () async {
    courier.prefs.listed = true;
    await catalog.refresh();
    final mine =
        catalog.listings[Listing.key(Shelf.person, bob.address, bob.address)]!;
    expect(mine.name, 'Bob Stone');
    expect(mine.about, 'Night owl');
    expect(catalog.browse(Shelf.person), isEmpty);

    await catalog.refresh();
    expect(
      catalog.listings[mine.id]!.time,
      mine.time,
      reason: 'nothing changed, so nothing is published again',
    );

    courier.me.bio = 'Early bird';
    await catalog.refresh();
    expect(catalog.listings[mine.id]!.about, 'Early bird');

    courier.prefs.listed = false;
    await catalog.refresh();
    expect(catalog.listings[mine.id]!.gone, isTrue);
  });

  test('a founder lists a community, and anyone can join from it', () async {
    final community = await mesh.create(name: 'Open Mic', about: 'Poetry');
    community.listed = true;
    await catalog.refresh();
    final listing = catalog.listing(community)!;
    expect(listing.name, 'Open Mic');
    expect(listing.members, 1);
    expect(listing.invitation['key'], base64.encode(community.key));

    final group = await mesh.create(name: 'Family', group: true);
    group.listed = true;
    await catalog.refresh();
    expect(catalog.listing(group), isNull);

    community.listed = false;
    await catalog.refresh();
    expect(catalog.listing(community), isNull);

    final elsewhere = id();
    final invitation = keys();
    final theirs = Catalog.check(
      await as(
        alice,
        Shelf.community,
        elsewhere,
        name: 'Board Games',
        invitation: invitation,
      ),
    )!;
    final joined = (await catalog.join(theirs))!;
    expect(joined.id, elsewhere);
    expect(joined.founder, alice.address);
    expect(base64.encode(joined.key), invitation['key']);
    expect(joined.group, isFalse);
    expect(mesh.ordered().map((item) => item.id), contains(elsewhere));
    for (final item in [community, group, joined]) {
      await mesh.leave(item.id);
    }
  });

  test('hidden listings stay hidden and are not passed along', () async {
    final frame = await as(carol, Shelf.person, carol.address, name: 'Carol');
    final listing = Catalog.check(frame)!;
    await catalog.accept(listing);
    await catalog.hide(listing);
    expect(catalog.browse(Shelf.person), isEmpty);
    expect(catalog.offered(), isEmpty);
    await catalog.start();
    expect(catalog.hidden, contains(listing.id));
  });

  test('a large picture is shrunk to fit a listing', () async {
    final random = Random(7);
    final noise = img.Image(width: 400, height: 400);
    for (final pixel in noise) {
      pixel
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    final large = Uint8List.fromList(img.encodePng(noise));
    expect(large.length, greaterThan(Catalog.pictures));
    final small = (await catalog.thumbnail(large))!;
    expect(small.length, lessThanOrEqualTo(Catalog.pictures));
    expect(img.decodeJpg(small), isNotNull);
  });
}
