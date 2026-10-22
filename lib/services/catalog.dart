import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart' as hashing;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/listing.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/sql/ledger.dart';

/// What this identity wants one of its listings to say.
typedef Draft = ({
  String name,
  String about,
  Uint8List? picture,
  int members,
  Map<String, dynamic> invitation,
});

/// An opt-in directory of people and communities, passed from phone to
/// phone between trustees so you can find people you have not met.
///
/// Nothing is listed unless its owner asks: a person lists themselves and a
/// founder lists their community. Every listing is signed, costs a few
/// seconds of proof of work, and lapses unless renewed. Taking one down
/// sends a signed notice that replaces it everywhere.
class Catalog extends ChangeNotifier {
  static final Catalog instance = Catalog._();

  Catalog._();

  /// Leading zero bits a listing's proof of work needs.
  static int difficulty = 20;

  /// Listings not renewed within this long are dropped everywhere.
  static const Duration lifetime = Duration(days: 14);

  /// How often this phone renews its own listings.
  static const Duration renewal = Duration(days: 3);

  /// Most listings one phone keeps; the oldest go first.
  static const int capacity = 600;

  /// Most communities one person may list.
  static const int share = 5;

  /// Largest picture in a listing.
  static const int pictures = 24 * 1024;

  /// Largest listing frame, picture included.
  static const int frames = 40 * 1024;

  /// Most bytes, and most listings, sent in one frame.
  static const int bundle = 380 * 1024;
  static const int batch = 200;

  /// Compare listings with a trustee every this many courier heartbeats.
  static const int cadence = 9;

  final Map<String, Listing> listings = {};

  /// Listings this person hid. They are neither shown nor passed along.
  final Set<String> hidden = {};
  final Expando<Uint8List> thumbs = Expando();
  final Map<String, String> labors = {};
  Future<void> renewing = Future.value();
  int ticks = 0;

  Courier get courier => Courier.instance;

  Future<void> start() async {
    listings.clear();
    hidden.clear();
    await Ledger.discardListings(DateTime.now().subtract(lifetime));
    for (final frame in await Ledger.listings()) {
      final listing = check(
        jsonDecode(frame) as Map<String, dynamic>,
        stored: true,
      );
      if (listing != null) listings[listing.id] = listing;
    }
    final saved = await Ledger.read('catalog');
    final names = saved?['hidden'];
    if (names is List) hidden.addAll(names.whereType<String>());
    notifyListeners();
    unawaited(refresh());
  }

  void stop() {
    listings.clear();
    hidden.clear();
    labors.clear();
    ticks = 0;
    notifyListeners();
  }

  // Views.

  bool expired(Listing listing) =>
      DateTime.now().difference(listing.time) > lifetime;

  /// What to show on [shelf]: live listings, newest first, leaving out your
  /// own listing, anything you hid and anyone you blocked.
  List<Listing> browse(Shelf shelf) {
    final self = courier.self?.address;
    return listings.values
        .where((item) => item.shelf == shelf && !item.gone && !expired(item))
        .where((item) => !(shelf == Shelf.person && item.subject == self))
        .where((item) => !hidden.contains(item.id))
        .where((item) => courier.roster[item.author]?.blocked != true)
        .toList()
      ..sort((alpha, beta) => beta.time.compareTo(alpha.time));
  }

  /// The founder's live listing of [community], if it is listed.
  Listing? listing(Community community) {
    final found =
        listings[Listing.key(Shelf.community, community.id, community.founder)];
    return found == null || found.gone || expired(found) ? null : found;
  }

  // Cryptography.

  static List<int> puzzle(
    String shelf,
    String subject,
    String author,
    String nonce,
  ) => utf8.encode('zephyron/listing\n$shelf\n$subject\n$author\n$nonce');

  /// Finds a nonce that makes the listing's puzzle start with [bits] zero
  /// bits. It depends only on who lists what, so renewals reuse it.
  static String labor(String shelf, String subject, String author, int bits) {
    for (var nonce = 0; ; nonce++) {
      final text = nonce.toRadixString(36);
      final digest = hashing.sha256.convert(
        puzzle(shelf, subject, author, text),
      );
      if (Mesh.zeros(digest.bytes) >= bits) return text;
    }
  }

  /// Sorts every map by key, so a listing always encodes the same way.
  static Object? sorted(Object? value) => switch (value) {
    Map() => {
      for (final key in value.keys.map((item) => '$item').toList()..sort())
        key: sorted(value[key]),
    },
    List() => [for (final item in value) sorted(item)],
    _ => value,
  };

  static Uint8List canonical(Map<String, dynamic> frame) => Uint8List.fromList(
    utf8.encode(
      'zephyron/listing\n${jsonEncode(sorted({...frame}..remove('g')))}',
    ),
  );

  /// Builds and signs a listing by this identity.
  Future<Map<String, dynamic>> compose(
    Shelf shelf,
    String subject, {
    String name = '',
    String about = '',
    Uint8List? picture,
    int members = 0,
    Map<String, dynamic> invitation = const {},
    bool gone = false,
  }) async {
    final self = courier.self!;
    final kind = shelf.name;
    final author = self.address;
    final bits = difficulty;
    final cache = '$kind:$subject:$author:$bits';
    final work =
        labors[cache] ??
        await Isolate.run<String>(() => labor(kind, subject, author, bits));
    labors[cache] = work;
    // Always later than the listing it replaces, even within a millisecond.
    final held = listings[Listing.key(shelf, subject, author)];
    final time = max(
      DateTime.now().millisecondsSinceEpoch,
      (held?.time.millisecondsSinceEpoch ?? 0) + 1,
    );
    final frame = <String, dynamic>{
      'h': kind,
      's': subject,
      'a': author,
      'k': self.public,
      't': time,
      if (gone)
        'd': true
      else ...{
        'n': name,
        'b': about,
        if (picture != null) 'p': base64.encode(picture),
        if (shelf == Shelf.community) ...{'m': members, 'j': invitation},
      },
      'w': work,
      'z': bits,
    };
    frame['g'] = Courier.encode(
      ed25519.sign(courier.secret!, canonical(frame)),
    );
    return frame;
  }

  /// Checks a listing and opens it, or returns null if it is forged,
  /// altered, stale, oversized or short of proof of work. Listings read back
  /// from this phone's store skip the signature and the work, which were
  /// checked when they arrived.
  static Listing? check(Map<String, dynamic> frame, {bool stored = false}) {
    try {
      final shelves = Shelf.values.where((item) => item.name == frame['h']);
      final subject = frame['s'];
      final author = frame['a'];
      final time = frame['t'];
      if (shelves.isEmpty || subject is! String || author is! String) {
        return null;
      }
      if (time is! int || !Identity.valid(author)) return null;
      final shelf = shelves.first;
      final community = shelf == Shelf.community;
      if (community
          ? !RegExp(r'^[0-9a-f]{32}$').hasMatch(subject)
          : subject != author) {
        return null;
      }
      final now = DateTime.now();
      final stamp = DateTime.fromMillisecondsSinceEpoch(time);
      if (stamp.isAfter(now.add(const Duration(hours: 1))) ||
          now.difference(stamp) > lifetime) {
        return null;
      }
      if (!stored) {
        if (jsonEncode(frame).length > frames) return null;
        final key = Courier.decode(frame['k'] as String);
        if (key.length != 32 || Identity.onion(key) != author) return null;
        final work = frame['w'];
        final bits = frame['z'];
        if (work is! String || bits is! int || bits < difficulty) return null;
        final digest = hashing.sha256.convert(
          puzzle(shelf.name, subject, author, work),
        );
        if (Mesh.zeros(digest.bytes) < bits) return null;
        if (!ed25519.verify(
          ed25519.PublicKey(key),
          canonical(frame),
          Courier.decode(frame['g'] as String),
        )) {
          return null;
        }
      }
      if (frame['d'] == true) {
        return Listing(
          shelf: shelf,
          subject: subject,
          author: author,
          time: stamp,
          frame: frame,
          gone: true,
        );
      }
      final name = Profile.clip(
        frame['n'],
        community ? Community.names : Profile.names,
      );
      final about = Profile.clip(
        frame['b'],
        community ? Community.abouts : Profile.bios,
      );
      final raw = frame['p'];
      final picture = raw is String && raw.isNotEmpty
          ? base64.decode(raw)
          : null;
      if ((picture?.length ?? 0) > pictures) return null;
      var members = 0;
      var invitation = const <String, dynamic>{};
      if (community) {
        final count = frame['m'];
        members = count is int ? count.clamp(0, 1000000) : 0;
        final keys = frame['j'];
        if (keys is! Map || name.isEmpty) return null;
        final valid = Mesh.valid({
          ...Map<String, dynamic>.from(keys),
          'community': subject,
          'name': name,
          'about': about,
          'founder': author,
          'group': false,
        }, author);
        if (valid == null) return null;
        invitation = valid;
      }
      return Listing(
        shelf: shelf,
        subject: subject,
        author: author,
        time: stamp,
        frame: frame,
        name: name,
        about: about,
        picture: picture,
        members: members,
        invitation: invitation,
      );
    } catch (_) {
      return null;
    }
  }

  /// Keeps [listing] if it is newer than the copy held, and returns whether
  /// it was kept.
  Future<bool> accept(Listing listing) async {
    final held = listings[listing.id];
    if (held != null && !listing.time.isAfter(held.time)) return false;
    if (held == null && listing.shelf == Shelf.community && !listing.gone) {
      final theirs = listings.values.where(
        (item) =>
            item.shelf == Shelf.community &&
            item.author == listing.author &&
            !item.gone,
      );
      if (theirs.length >= share) return false;
    }
    listings[listing.id] = listing;
    await Ledger.list(
      listing.id,
      jsonEncode(listing.frame),
      listing.time.millisecondsSinceEpoch,
    );
    await trim();
    notifyListeners();
    return true;
  }

  /// Drops lapsed listings, then the oldest beyond [capacity], never this
  /// identity's own.
  Future<void> trim() async {
    final self = courier.self?.address;
    final lapsed = listings.values.where(expired).toList();
    final rest =
        listings.values
            .where((item) => !expired(item) && item.author != self)
            .toList()
          ..sort((alpha, beta) => alpha.time.compareTo(beta.time));
    final excess = max(0, listings.length - lapsed.length - capacity);
    for (final item in [...lapsed, ...rest.take(excess)]) {
      listings.remove(item.id);
      await Ledger.unlist(item.id);
    }
  }

  // Actions.

  /// Stops showing [listing] here and stops passing it along.
  Future<void> hide(Listing listing) async {
    hidden.add(listing.id);
    while (hidden.length > 2000) {
      hidden.remove(hidden.first);
    }
    await Ledger.write('catalog', {'hidden': hidden.toList()});
    notifyListeners();
  }

  /// Joins a listed community with the keys its listing carries.
  Future<Community?> join(Listing listing) async {
    if (listing.shelf != Shelf.community || listing.gone) return null;
    final mesh = Mesh.instance;
    final community = await mesh.join(listing.invitation);
    if (community != null &&
        community.icon == null &&
        listing.picture != null) {
      community.icon = listing.picture;
      await mesh.amend(community);
    }
    return community;
  }

  /// Brings this identity's own listings in line with what it chose: lists
  /// or renews what should be listed and takes down the rest.
  Future<void> refresh() => renewing = renewing
      .then((_) => renew())
      .catchError(
        (Object error) => developer.log(
          'Could not update this identity\'s listings',
          name: 'Catalog.refresh',
          level: 900,
          error: error,
        ),
      );

  Future<void> renew() async {
    final self = courier.self;
    if (self == null || courier.secret == null) return;
    final me = courier.me;
    await settle(
      Shelf.person,
      self.address,
      courier.prefs.listed
          ? (
              name: me.name,
              about: me.bio,
              picture: await thumbnail(me.avatar),
              members: 0,
              invitation: const <String, dynamic>{},
            )
          : null,
    );
    final mesh = Mesh.instance;
    final wanted = <String>{};
    for (final community in mesh.communities.values.toList()) {
      if (community.founder != self.address ||
          community.group ||
          !community.listed) {
        continue;
      }
      wanted.add(community.id);
      final invitation = mesh.invitation(community);
      await settle(Shelf.community, community.id, (
        name: community.name,
        about: community.about,
        picture: await thumbnail(community.icon),
        members: mesh.members(community.id).length,
        invitation: {
          'key': invitation['key'],
          'keys': invitation['keys'],
          'created': invitation['created'],
        },
      ));
    }
    for (final item in listings.values.toList()) {
      if (item.shelf == Shelf.community &&
          item.author == self.address &&
          !item.gone &&
          !wanted.contains(item.subject)) {
        await settle(Shelf.community, item.subject, null);
      }
    }
  }

  /// Publishes [draft] as this identity's listing of [subject] when it
  /// differs from the one held or is due for renewal, or takes the listing
  /// down when [draft] is null.
  Future<void> settle(Shelf shelf, String subject, Draft? draft) async {
    final held = listings[Listing.key(shelf, subject, courier.self!.address)];
    if (draft == null) {
      if (held != null && !held.gone) {
        await publish(await compose(shelf, subject, gone: true));
      }
      return;
    }
    final current =
        held != null &&
        !held.gone &&
        DateTime.now().difference(held.time) < renewal &&
        held.name == draft.name &&
        held.about == draft.about &&
        listEquals(held.picture, draft.picture) &&
        held.invitation['key'] == draft.invitation['key'];
    if (current) return;
    await publish(
      await compose(
        shelf,
        subject,
        name: draft.name,
        about: draft.about,
        picture: draft.picture,
        members: draft.members,
        invitation: draft.invitation,
      ),
    );
  }

  /// Keeps one of this identity's own listings and hands it to trustees who
  /// are connected; the rest get it when they next connect.
  Future<void> publish(Map<String, dynamic> frame) async {
    final listing = check(frame);
    if (listing == null || !await accept(listing)) return;
    for (final entry in courier.channels.entries.toList()) {
      if (!entry.value.alive || courier.roster[entry.key]?.trusted != true) {
        continue;
      }
      deliver(entry.value, entry.key, [frame]);
    }
  }

  /// A picture small enough for a listing: [bytes] as they are when they
  /// fit, otherwise a small JPEG made from them.
  Future<Uint8List?> thumbnail(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    if (bytes.length <= pictures) return bytes;
    final cached = thumbs[bytes];
    if (cached != null) return cached;
    final small = await Isolate.run(() => shrink(bytes));
    if (small != null) thumbs[bytes] = small;
    return small;
  }

  static Uint8List? shrink(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    for (final (width, quality) in [(160, 80), (128, 70), (96, 60)]) {
      final encoded = img.encodeJpg(
        img.copyResize(decoded, width: min(width, decoded.width)),
        quality: quality,
      );
      if (encoded.length <= pictures) return encoded;
    }
    return null;
  }

  // Network.

  void send(Channel channel, String peer, Map<String, dynamic> body) {
    channel.send(courier.seal(Signal.listing, peer, body: jsonEncode(body)));
  }

  /// When each listing held was written, so a trustee can send what is newer.
  Map<String, int> clock() => {
    for (final item in listings.values)
      item.id: item.time.millisecondsSinceEpoch,
  };

  /// What this phone passes along: everything it holds, or only its own
  /// listings when passing along is off.
  Iterable<Listing> offered() {
    final self = courier.self?.address;
    return listings.values.where(
      (item) =>
          !expired(item) &&
          !hidden.contains(item.id) &&
          (courier.prefs.spread || item.author == self),
    );
  }

  /// Sends [items] in frames small enough for one line each.
  void deliver(
    Channel channel,
    String peer,
    Iterable<Map<String, dynamic>> items,
  ) {
    var pending = <Map<String, dynamic>>[];
    var size = 0;
    for (final item in items) {
      final length = jsonEncode(item).length;
      if (pending.isNotEmpty &&
          (size + length > bundle || pending.length >= batch)) {
        send(channel, peer, {'op': 'cards', 'items': pending});
        pending = [];
        size = 0;
      }
      pending.add(item);
      size += length;
    }
    if (pending.isNotEmpty) {
      send(channel, peer, {'op': 'cards', 'items': pending});
    }
  }

  /// Called when a channel to a trustee opens, to compare listings.
  void greet(String peer, Channel channel) {
    if (courier.self == null) return;
    send(channel, peer, {'op': 'have', 'clock': clock()});
  }

  /// Every few heartbeats, renews this identity's listings and compares
  /// notes with one connected trustee.
  void heartbeat() {
    ticks += 1;
    if (ticks % cadence != 0) return;
    unawaited(trim().then((_) => refresh()));
    final open = courier.channels.entries
        .where(
          (entry) =>
              entry.value.alive && courier.roster[entry.key]?.trusted == true,
        )
        .toList();
    if (open.isEmpty) return;
    final pick = open[Random().nextInt(open.length)];
    send(pick.value, pick.key, {'op': 'have', 'clock': clock()});
  }

  Future<void> receive(String from, Channel channel, String body) async {
    if (courier.roster[from]?.trusted != true) return;
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) return;

    switch (data['op']) {
      case 'have':
        final theirs = <String, int>{};
        final raw = data['clock'];
        if (raw is Map) {
          for (final entry in raw.entries.take(capacity * 2)) {
            if (entry.key is String && entry.value is int) {
              theirs[entry.key as String] = entry.value as int;
            }
          }
        }
        final missing =
            offered()
                .where(
                  (item) =>
                      item.time.millisecondsSinceEpoch > (theirs[item.id] ?? 0),
                )
                .toList()
              ..sort((alpha, beta) => beta.time.compareTo(alpha.time));
        deliver(channel, from, missing.map((item) => item.frame));
        final behind = theirs.entries.any(
          (entry) =>
              !hidden.contains(entry.key) &&
              entry.value >
                  (listings[entry.key]?.time.millisecondsSinceEpoch ?? 0),
        );
        if (behind && data['reply'] != true) {
          send(channel, from, {'op': 'have', 'clock': clock(), 'reply': true});
        }
      case 'cards':
        final items = data['items'];
        if (items is! List) return;
        final fresh = <Map<String, dynamic>>[];
        for (final item in items.take(batch)) {
          if (item is! Map<String, dynamic>) continue;
          final listing = check(item);
          if (listing == null || hidden.contains(listing.id)) continue;
          if (await accept(listing)) fresh.add(item);
        }
        if (fresh.isEmpty || !courier.prefs.spread) return;
        developer.log(
          'Passing ${fresh.length} new listings on to connected trustees',
          name: 'Catalog.receive',
          level: 500,
        );
        for (final entry in courier.channels.entries.toList()) {
          if (entry.key == from ||
              !entry.value.alive ||
              courier.roster[entry.key]?.trusted != true) {
            continue;
          }
          deliver(entry.value, entry.key, fresh);
        }
    }
  }
}
