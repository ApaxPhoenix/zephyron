import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:flutter/foundation.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/broadcast.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/services/stage.dart';
import 'package:zephyron/sql/ledger.dart';

/// Peer-to-peer communities with no owner and no server.
///
/// Every post is encrypted with the community key and signed by its author,
/// so members relay posts for each other without being able to read them if
/// they lack the key, or to forge or alter them if they have it. Each author
/// numbers their posts, so two members can compare what they hold and fill in
/// exactly what the other is missing; a member who was offline catches up
/// from whoever is online.
class Mesh extends ChangeNotifier {
  static final Mesh instance = Mesh._();

  Mesh._();

  /// Longest message in a channel.
  static const int limit = 4000;

  /// Largest community icon and banner, so their posts fit in one frame.
  static const int icons = 96 * 1024;
  static const int banners = 200 * 1024;

  /// Most bytes of posts sent in one sync frame.
  static const int bundle = 380 * 1024;

  /// Members dialed directly when a new post is pushed.
  static const int reach = 5;

  /// Sync with a couple of members every this many courier heartbeats.
  static const int cadence = 6;

  /// Leading zero bits a join's proof of work needs: a few seconds of work
  /// on a phone, which makes joining by the thousand expensive.
  static int difficulty = 20;

  /// How long someone must have been a member before their vote counts, so
  /// a flood of new accounts cannot swing a removal.
  static Duration seasoning = const Duration(hours: 1);

  /// Most posts one member may make within a minute; the rest are dropped.
  static const int burst = 30;

  static List<int> puzzle(String community, String author, String nonce) =>
      utf8.encode('zephyron/join\n$community\n$author\n$nonce');

  static int zeros(List<int> digest) {
    var count = 0;
    for (final byte in digest) {
      if (byte == 0) {
        count += 8;
        continue;
      }
      var mask = 0x80;
      while (mask > 0 && byte & mask == 0) {
        count += 1;
        mask >>= 1;
      }
      break;
    }
    return count;
  }

  /// Finds a nonce whose hash, with the community and the joiner, starts
  /// with [bits] zero bits.
  static String labor(String community, String author, int bits) {
    for (var nonce = 0; ; nonce++) {
      final text = nonce.toRadixString(36);
      if (zeros(
            hashing.sha256.convert(puzzle(community, author, text)).bytes,
          ) >=
          bits) {
        return text;
      }
    }
  }

  /// Whether a join carries enough proof of work.
  static bool proven(
    String community,
    String author,
    Object? work,
    Object? bits,
  ) {
    if (work is! String || bits is! int || bits < difficulty) return false;
    return zeros(
          hashing.sha256.convert(puzzle(community, author, work)).bytes,
        ) >=
        bits;
  }

  final Map<String, Community> communities = {};
  final Map<String, List<Post>> posts = {};
  final Set<String> known = {};
  final Map<String, Standing> tallies = {};

  /// Communities waiting to rotate their key after a removal, by id.
  final Map<String, Timer> rotations = {};
  int ticks = 0;

  Courier get courier => Courier.instance;

  Future<void> start() async {
    communities.clear();
    posts.clear();
    known.clear();
    tallies.clear();
    for (final community in await Ledger.communities()) {
      communities[community.id] = community;
    }
    for (final post in await Ledger.posts()) {
      index(post);
    }
    notifyListeners();
  }

  void stop() {
    Stage.instance.reset();
    for (final timer in rotations.values) {
      timer.cancel();
    }
    rotations.clear();
    tallies.clear();
    communities.clear();
    posts.clear();
    known.clear();
    ticks = 0;
    notifyListeners();
  }

  void index(Post post) {
    if (!known.add(post.id)) return;
    tallies.remove(post.community);
    final list = posts.putIfAbsent(post.community, () => []);
    var at = list.length;
    while (at > 0 && list[at - 1].time.isAfter(post.time)) {
      at -= 1;
    }
    list.insert(at, post);
  }

  // Views.

  List<Room> rooms(String community) {
    final group = communities[community];
    if (group == null) return const [];
    final found = <String, Room>{
      group.general: Room(
        id: group.general,
        community: community,
        name: 'general',
        kind: Space.text,
        author: group.founder,
        created: group.created,
      ),
    };
    for (final post in posts[community] ?? const <Post>[]) {
      if (post.note != Note.channel) continue;
      final kind = Space.values.where((item) => item.name == post.meta['kind']);
      found.putIfAbsent(
        post.meta['id'] as String? ?? post.id,
        () => Room(
          id: post.meta['id'] as String? ?? post.id,
          community: community,
          name: post.text,
          kind: kind.isEmpty ? Space.text : kind.first,
          author: post.author,
          created: post.time,
        ),
      );
    }
    return found.values.toList()
      ..sort((alpha, beta) => alpha.created.compareTo(beta.created));
  }

  /// Who is in [community] right now, who was voted out, and the votes
  /// still open, worked out from the posts alone so every phone with the
  /// same posts agrees.
  Standing standing(String community) =>
      tallies[community] ??= tally(community);

  Standing tally(String community) {
    final group = communities[community];
    final found = <String, Member>{};
    final removed = <String, DateTime>{};
    final votes = <String, Set<String>>{};
    if (group == null) return Standing(found, removed, votes);
    found[group.founder] = Member(
      address: group.founder,
      name: '',
      since: group.created,
    );

    void settle(DateTime when) {
      var changed = true;
      while (changed) {
        changed = false;
        for (final target in votes.keys.toList()) {
          // Only people who have been here a while decide; the founder
          // counts from the start so a young community can still act.
          final electorate = {
            for (final entry in found.entries)
              if (entry.key != target &&
                  (entry.key == group.founder ||
                      !entry.value.since.isAfter(when.subtract(seasoning))))
                entry.key,
          };
          final yes = votes[target]!.intersection(electorate).length;
          if (electorate.isNotEmpty && yes * 2 > electorate.length) {
            removed[target] = when;
            found.remove(target);
            votes.remove(target);
            for (final ballots in votes.values) {
              ballots.remove(target);
            }
            changed = true;
          }
        }
      }
    }

    for (final post in posts[community] ?? const <Post>[]) {
      switch (post.note) {
        case Note.join:
          if (removed.containsKey(post.author)) continue;
          if (post.author != group.founder &&
              !proven(
                community,
                post.author,
                post.meta['work'],
                post.meta['bits'],
              )) {
            continue;
          }
          final avatar = post.meta['avatar'];
          final picture = avatar is String && avatar.isNotEmpty
              ? base64.decode(avatar)
              : null;
          final existing = found[post.author];
          if (existing == null) {
            found[post.author] = Member(
              address: post.author,
              name: post.text,
              since: post.time,
              avatar: picture,
            );
          } else {
            existing.name = post.text;
            if (picture != null) existing.avatar = picture;
          }
        case Note.vote:
          final target = post.meta['target'];
          if (target is! String || target == post.author) continue;
          if (!found.containsKey(post.author) || !found.containsKey(target)) {
            continue;
          }
          final ballots = votes.putIfAbsent(target, () => {});
          if (post.meta['withdraw'] == true) {
            ballots.remove(post.author);
          } else {
            ballots.add(post.author);
          }
          if (ballots.isEmpty) votes.remove(target);
          settle(post.time);
        default:
          break;
      }
    }
    return Standing(found, removed, votes);
  }

  /// Members by seniority: the founder, then everyone in the order they
  /// joined. That order is the only thing that sets anyone apart.
  List<Member> members(String community) {
    final group = communities[community];
    if (group == null) return const [];
    return standing(community).members.values.toList()..sort((alpha, beta) {
      if (alpha.address == group.founder) return -1;
      if (beta.address == group.founder) return 1;
      return alpha.since.compareTo(beta.since);
    });
  }

  bool member(String community, String address) =>
      standing(community).members.containsKey(address);

  /// People voted out of [community], with when it happened.
  Map<String, DateTime> removed(String community) =>
      standing(community).removed;

  /// Who has voted to remove each member, for votes still short of a
  /// majority.
  Map<String, Set<String>> ballots(String community) =>
      standing(community).votes;

  /// How many votes removing [target] needs: more than half of everyone else.
  int needed(String community, String target) {
    final others = standing(
      community,
    ).members.keys.where((item) => item != target);
    return others.length ~/ 2 + 1;
  }

  /// A member's display name: what you call them if they are a trustee,
  /// otherwise the name they gave the community.
  String called(String community, String address) {
    if (address == courier.self?.address) {
      return courier.me.name.isEmpty ? 'You' : courier.me.name;
    }
    final trustee = courier.roster[address];
    if (trustee != null && trustee.label != trustee.short) return trustee.label;
    final known = members(community).where((item) => item.address == address);
    if (known.isNotEmpty && known.first.name.isNotEmpty) {
      return known.first.name;
    }
    return address.substring(0, 10);
  }

  /// Whether [post] came from someone after they were voted out.
  bool silenced(Post post) {
    final out = removed(post.community)[post.author];
    return out != null && !post.time.isBefore(out);
  }

  List<Post> messages(String community, String channel) => [
    for (final post in posts[community] ?? const <Post>[])
      if (post.note == Note.text &&
          post.channel == channel &&
          !silenced(post) &&
          courier.roster[post.author]?.blocked != true)
        post,
  ];

  Post? latest(String community) {
    final list = posts[community] ?? const <Post>[];
    for (final post in list.reversed) {
      if (post.note == Note.text) return post;
    }
    return null;
  }

  /// Communities with pinned ones first, then by latest activity.
  List<Community> ordered({bool groups = false}) {
    return communities.values.where((item) => item.group == groups).toList()
      ..sort((alpha, beta) {
        if (alpha.pinned != beta.pinned) return alpha.pinned ? -1 : 1;
        return active(beta).compareTo(active(alpha));
      });
  }

  /// When anything last happened in [group].
  DateTime active(Community group) => latest(group.id)?.time ?? group.joined;

  /// Private group chats, newest activity first.
  List<Community> groups() => ordered(groups: true);

  /// The highest post number held from each author with no gaps below it.
  Map<String, int> clock(String community) {
    final seen = <String, Set<int>>{};
    for (final post in posts[community] ?? const <Post>[]) {
      seen.putIfAbsent(post.author, () => {}).add(post.seq);
    }
    return {
      for (final entry in seen.entries)
        entry.key: () {
          var top = 0;
          while (entry.value.contains(top + 1)) {
            top += 1;
          }
          return top;
        }(),
    };
  }

  // Cryptography.

  static Uint8List canonical(Map<String, dynamic> frame) => Uint8List.fromList(
    utf8.encode(
      [
        'zephyron/post',
        frame['c'],
        frame['i'],
        frame['a'],
        frame['s'],
        frame['t'],
        if (frame['e'] != null) frame['e'],
        frame['x'],
      ].join('\n'),
    ),
  );

  static List<int> associated(Map<String, dynamic> frame) => utf8.encode(
    [
      frame['c'],
      frame['i'],
      frame['a'],
      frame['s'],
      frame['t'],
      if (frame['e'] != null) frame['e'],
    ].join('\n'),
  );

  static Future<Uint8List> material(Uint8List key, String id) =>
      Ratchet.derive(key, info: 'zephyron/post:$id', length: 44);

  /// Builds the signed, encrypted frame for a new post by this identity.
  Future<Map<String, dynamic>> compose(
    Community community, {
    required String channel,
    required Note note,
    String text = '',
    Map<String, dynamic> meta = const {},
  }) async {
    final self = courier.self!;
    if (note == Note.join &&
        meta['work'] == null &&
        community.founder != self.address) {
      meta = {
        ...meta,
        'work': labor(community.id, self.address, difficulty),
        'bits': difficulty,
      };
    }
    final mine = (posts[community.id] ?? const <Post>[])
        .where((post) => post.author == self.address)
        .fold<int>(0, (top, post) => max(top, post.seq));
    final frame = <String, dynamic>{
      'c': community.id,
      'i': Courier.token(),
      'a': self.address,
      'k': self.public,
      's': mine + 1,
      't': DateTime.now().millisecondsSinceEpoch,
      'e': community.epoch,
    };
    final keys = await material(community.key, frame['i'] as String);
    final box = await AesGcm.with256bits().encrypt(
      Ratchet.pad(
        utf8.encode(
          jsonEncode({'ch': channel, 'n': note.name, 'tx': text, 'm': meta}),
        ),
      ),
      secretKey: SecretKey(keys.sublist(0, 32)),
      nonce: keys.sublist(32),
      aad: associated(frame),
    );
    frame['x'] = base64.encode([...box.cipherText, ...box.mac.bytes]);
    frame['g'] = Courier.encode(
      ed25519.sign(courier.secret!, canonical(frame)),
    );
    return frame;
  }

  /// Checks a relayed frame and opens it, or returns null if it is forged,
  /// altered, for a community this identity is not in, or unreadable.
  Future<Post?> verify(Map<String, dynamic> frame) async {
    try {
      final community = communities[frame['c']];
      if (community == null) return null;
      final id = frame['i'];
      final author = frame['a'];
      final seq = frame['s'];
      final time = frame['t'];
      final sealed = frame['x'];
      if (id is! String || author is! String || seq is! int || seq < 1) {
        return null;
      }
      if (time is! int || sealed is! String) return null;
      final key = Courier.decode(frame['k'] as String);
      if (key.length != 32 || Identity.onion(key) != author) return null;
      if (!ed25519.verify(
        ed25519.PublicKey(key),
        canonical(frame),
        Courier.decode(frame['g'] as String),
      )) {
        return null;
      }

      final bytes = base64.decode(sealed);
      if (bytes.length < 16) return null;
      final epoch = frame['e'];
      final candidates = epoch is String
          ? [?community.keys[epoch]]
          : community.keys.values.toList();
      List<int>? clear;
      for (final secret in candidates) {
        try {
          final keys = await material(secret, id);
          clear = await AesGcm.with256bits().decrypt(
            SecretBox(
              bytes.sublist(0, bytes.length - 16),
              nonce: keys.sublist(32),
              mac: Mac(bytes.sublist(bytes.length - 16)),
            ),
            secretKey: SecretKey(keys.sublist(0, 32)),
            aad: associated(frame),
          );
          break;
        } on SecretBoxAuthenticationError {
          continue;
        }
      }
      if (clear == null) return null;
      final body =
          jsonDecode(utf8.decode(Ratchet.unpad(Uint8List.fromList(clear))))
              as Map<String, dynamic>;
      final note = Note.values.where((item) => item.name == body['n']);
      if (note.isEmpty) return null;
      final text = Profile.clip(body['tx'], limit);
      final meta = body['m'] is Map
          ? Map<String, dynamic>.from(body['m'] as Map)
          : <String, dynamic>{};
      final now = DateTime.now();
      final stamp = DateTime.fromMillisecondsSinceEpoch(time);
      return Post(
        id: id,
        community: community.id,
        channel: '${body['ch'] ?? ''}',
        author: author,
        seq: seq,
        time: stamp.isAfter(now) ? now : stamp,
        note: note.first,
        text: text,
        meta: meta,
        frame: jsonEncode(frame),
      );
    } catch (_) {
      return null;
    }
  }

  /// Stores a verified post and applies what it changes.
  Future<bool> accept(Post post) async {
    if (known.contains(post.id)) return false;
    final crowded = (posts[post.community] ?? const <Post>[])
        .where(
          (other) =>
              other.author == post.author &&
              other.time.difference(post.time).abs() <
                  const Duration(minutes: 1),
        )
        .length;
    if (crowded >= burst) {
      known.add(post.id);
      return false;
    }
    final before = removed(post.community).keys.toSet();
    if (!await Ledger.publish(post)) {
      known.add(post.id);
      return false;
    }
    index(post);
    if (post.note == Note.about) await revise(post);
    if (post.note == Note.vote) {
      final fresh = removed(post.community).keys.toSet().difference(before);
      if (fresh.isNotEmpty) settle(post);
    }
    notifyListeners();
    return true;
  }

  /// After someone is voted out, makes sure a key they never saw takes over.
  /// Whoever cast the deciding vote rotates at once; everyone else waits a
  /// little, so the key usually changes once, and steps in only if nothing
  /// newer arrived. A second key is harmless: everyone keeps both.
  void settle(Post decider) {
    final group = communities[decider.community];
    if (group == null || group.rotated > decider.time.millisecondsSinceEpoch) {
      return;
    }
    if (decider.author == courier.self?.address) {
      unawaited(rotate(group));
      return;
    }
    rotations[group.id]?.cancel();
    rotations[group.id] = Timer(
      Duration(seconds: 20 + Random.secure().nextInt(70)),
      () {
        rotations.remove(group.id);
        final latest = removed(group.id).values.fold<int>(
          0,
          (top, when) => max(top, when.millisecondsSinceEpoch),
        );
        if (group.rotated <= latest) unawaited(rotate(group));
      },
    );
  }

  /// Starts a new community key and hands it to every remaining member,
  /// end-to-end encrypted, so whoever was removed cannot read what follows.
  Future<void> rotate(Community group) async {
    group.rekey(Ratchet.random(32), DateTime.now().millisecondsSinceEpoch);
    await Ledger.gather(group);
    notifyListeners();
    final self = courier.self?.address;
    for (final peer in members(group.id).map((item) => item.address)) {
      if (peer == self) continue;
      unawaited(hand(group, peer, group.epoch));
    }
  }

  /// Sends [peer] the community key [id] inside an end-to-end session.
  Future<void> hand(Community group, String peer, String id) async {
    final secret = group.keys[id];
    if (secret == null || !member(group.id, peer)) return;
    try {
      final channel = await courier.dial(peer);
      final sealed = await courier.whisper(
        peer,
        channel,
        utf8.encode(
          jsonEncode({
            'id': id,
            'key': base64.encode(secret),
            'at': id == group.epoch ? group.rotated : 0,
          }),
        ),
      );
      send(channel, peer, {'op': 'rekey', 'c': group.id, 'k': sealed});
    } catch (error) {
      developer.log(
        'Could not hand a community key to a member yet',
        name: 'Mesh.hand',
        level: 800,
        error: error,
      );
    }
  }

  /// Votes to remove [target], or takes the vote back with [withdraw].
  Future<void> vote(
    Community community,
    String target, {
    bool withdraw = false,
  }) => post(
    community,
    channel: community.general,
    note: Note.vote,
    meta: {'target': target, if (withdraw) 'withdraw': true},
  );

  /// Applies a description post when it is the newest one.
  Future<void> revise(Post post) async {
    final group = communities[post.community];
    if (group == null) return;
    final stamp = post.time.millisecondsSinceEpoch;
    if (stamp < group.revised) return;
    final name = post.meta['name'];
    final about = post.meta['about'];
    final icon = post.meta['icon'];
    final banner = post.meta['banner'];
    if (name is String && name.trim().isNotEmpty) {
      group.name = Profile.clip(name, Community.names);
    }
    if (about is String) group.about = Profile.clip(about, Community.abouts);
    if (icon is String) {
      final bytes = icon.isEmpty ? null : base64.decode(icon);
      if ((bytes?.length ?? 0) <= icons) group.icon = bytes;
    }
    if (banner is String) {
      final bytes = banner.isEmpty ? null : base64.decode(banner);
      if ((bytes?.length ?? 0) <= banners) group.banner = bytes;
    }
    group.revised = stamp;
    await Ledger.gather(group);
  }

  // Actions.

  Future<Post> post(
    Community community, {
    required String channel,
    required Note note,
    String text = '',
    Map<String, dynamic> meta = const {},
  }) async {
    final frame = await compose(
      community,
      channel: channel,
      note: note,
      text: text,
      meta: meta,
    );
    final post = (await verify(frame))!;
    await accept(post);
    unawaited(push(community, [frame]));
    return post;
  }

  /// The join post that introduces this identity, with its picture when
  /// small enough to share.
  Map<String, dynamic> introduction(String? by) {
    final avatar = courier.me.avatar;
    return {
      'by': ?by,
      if (avatar != null && avatar.length <= icons)
        'avatar': base64.encode(avatar),
    };
  }

  Future<Community> create({
    required String name,
    String about = '',
    Uint8List? icon,
    Uint8List? banner,
    bool group = false,
  }) async {
    final self = courier.self!;
    final community = Community(
      id: Courier.token(),
      name: Profile.clip(name, Community.names),
      about: Profile.clip(about, Community.abouts),
      key: Ratchet.random(32),
      founder: self.address,
      icon: icon,
      banner: banner,
      group: group,
    );
    communities[community.id] = community;
    await Ledger.gather(community);
    await post(
      community,
      channel: community.general,
      note: Note.join,
      text: courier.me.name,
      meta: introduction(null),
    );
    await describe(
      community,
      name: community.name,
      about: community.about,
      icon: icon,
      banner: banner,
    );
    notifyListeners();
    return community;
  }

  /// Publishes a new look for the community. Any member may; the newest
  /// change wins everywhere.
  Future<void> describe(
    Community community, {
    String? name,
    String? about,
    Uint8List? icon,
    Uint8List? banner,
    bool clearIcon = false,
    bool clearBanner = false,
  }) async {
    await post(
      community,
      channel: community.general,
      note: Note.about,
      meta: {
        'name': ?name,
        'about': ?about,
        'icon': ?(clearIcon
            ? ''
            : icon == null
            ? null
            : base64.encode(icon)),
      },
    );
    if (banner != null || clearBanner) {
      await post(
        community,
        channel: community.general,
        note: Note.about,
        meta: {'banner': clearBanner ? '' : base64.encode(banner!)},
      );
    }
  }

  Future<Room> channel(Community community, String name, Space kind) async {
    final id = Courier.token();
    final clean = Profile.clip(
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
      32,
    );
    final made = await post(
      community,
      channel: id,
      note: Note.channel,
      text: clean.isEmpty ? 'channel' : clean,
      meta: {'id': id, 'kind': kind.name},
    );
    return rooms(community.id).firstWhere((room) => room.id == made.channel);
  }

  Future<void> say(Community community, String channel, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    for (var at = 0; at < body.length; at += limit) {
      await post(
        community,
        channel: channel,
        note: Note.text,
        text: body.substring(at, min(at + limit, body.length)),
      );
    }
  }

  /// What a trustee needs to join, sent to them end-to-end encrypted.
  Map<String, dynamic> invitation(Community community) => {
    'community': community.id,
    'name': community.name,
    'about': community.about,
    'key': base64.encode(community.key),
    'keys': {
      for (final entry in community.keys.entries)
        entry.key: base64.encode(entry.value),
    },
    'founder': community.founder,
    'created': community.created.millisecondsSinceEpoch,
    if (community.group) 'group': true,
  };

  /// Sends [community]'s invitation to a trustee as a chat message.
  Future<void> invite(Community community, String peer) async {
    await courier.promote(peer);
    await courier.enqueue(
      Message(
        id: Courier.token(),
        peer: peer,
        mine: true,
        kind: Kind.invite,
        text: '',
        time: DateTime.now(),
        meta: invitation(community),
      ),
    );
    unawaited(courier.flush(peer));
  }

  /// Checks an invitation received from [from], keeping only what is valid.
  static Map<String, dynamic>? valid(Map<String, dynamic> meta, String from) {
    final id = meta['community'];
    final key = meta['key'];
    final founder = '${meta['founder'] ?? ''}'.toLowerCase();
    final created = meta['created'];
    if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return null;
    if (key is! String || created is! int || !Identity.valid(founder)) {
      return null;
    }
    final ring = <String, String>{};
    try {
      if (base64.decode(key).length != 32) return null;
      final keys = meta['keys'];
      if (keys is Map) {
        for (final entry in keys.entries.take(64)) {
          final secret = base64.decode(entry.value as String);
          if (secret.length == 32 &&
              Community.fingerprint(secret) == entry.key) {
            ring[entry.key as String] = entry.value as String;
          }
        }
      }
    } catch (_) {
      return null;
    }
    return {
      'keys': ring,
      'community': id,
      'name': Profile.clip(meta['name'], Community.names),
      'about': Profile.clip(meta['about'], Community.abouts),
      'key': key,
      'founder': founder,
      'created': created,
      'group': meta['group'] == true,
      'by': from,
    };
  }

  /// Joins from an invitation and asks whoever sent it for the history.
  Future<Community?> join(Map<String, dynamic> invitation) async {
    final id = invitation['community'] as String;
    final existing = communities[id];
    if (existing != null) return existing;
    final current = base64.decode(invitation['key'] as String);
    final ring = <String, Uint8List>{
      for (final entry in (invitation['keys'] as Map? ?? const {}).entries)
        entry.key as String: base64.decode(entry.value as String),
    };
    final community = Community(
      id: id,
      name: invitation['name'] as String? ?? 'Community',
      about: invitation['about'] as String? ?? '',
      key: current,
      keys: {...ring, Community.fingerprint(current): current},
      epoch: Community.fingerprint(current),
      founder: invitation['founder'] as String,
      created: DateTime.fromMillisecondsSinceEpoch(
        invitation['created'] as int,
      ),
      group: invitation['group'] == true,
    );
    communities[id] = community;
    await Ledger.gather(community);
    final by = invitation['by'] as String?;
    final self = courier.self!.address;
    final bits = difficulty;
    final work = await Isolate.run(() => labor(id, self, bits));
    await post(
      community,
      channel: community.general,
      note: Note.join,
      text: courier.me.name,
      meta: {...introduction(by), 'work': work, 'bits': bits},
    );
    if (by != null) unawaited(sync(community, by));
    notifyListeners();
    return community;
  }

  Future<void> leave(String id) async {
    rotations.remove(id)?.cancel();
    tallies.remove(id);
    communities.remove(id);
    for (final post in posts.remove(id) ?? const <Post>[]) {
      known.remove(post.id);
    }
    await Ledger.disband(id);
    notifyListeners();
  }

  Future<void> amend(Community community) async {
    await Ledger.gather(community);
    notifyListeners();
  }

  // Network.

  Map<String, dynamic>? proof(String community) {
    final self = courier.self?.address;
    for (final post in posts[community] ?? const <Post>[]) {
      if (post.note == Note.join && post.author == self) {
        return jsonDecode(post.frame) as Map<String, dynamic>;
      }
    }
    return null;
  }

  void send(Channel channel, String peer, Map<String, dynamic> body) {
    channel.send(courier.seal(Signal.mesh, peer, body: jsonEncode(body)));
  }

  /// Tells [peer] what this identity holds so they can fill in the rest.
  Future<void> sync(
    Community community,
    String peer, {
    bool reply = false,
  }) async {
    try {
      final channel = await courier.dial(peer);
      send(channel, peer, {
        'op': 'have',
        'c': community.id,
        'clock': clock(community.id),
        'keys': community.keys.keys.toList(),
        'proof': proof(community.id),
        'reply': reply,
      });
    } catch (_) {}
  }

  /// Sends new posts to members who are connected, and dials a few more.
  Future<void> push(
    Community community,
    List<Map<String, dynamic>> frames,
  ) async {
    final self = courier.self?.address;
    final others =
        members(community.id)
            .map((item) => item.address)
            .where((address) => address != self)
            .where((address) => courier.roster[address]?.blocked != true)
            .toList()
          ..shuffle();
    final open = others
        .where((address) => courier.channels[address]?.alive == true)
        .toSet();
    final targets = {
      ...open,
      ...others.where((a) => !open.contains(a)).take(reach),
    };
    for (final peer in targets) {
      try {
        await Courier.hesitate();
        final channel = await courier.dial(peer);
        send(channel, peer, {
          'op': 'posts',
          'c': community.id,
          'items': frames,
        });
      } catch (_) {}
    }
  }

  /// Called when a channel to [peer] opens, to catch up on shared communities.
  void greet(String peer) {
    for (final community in communities.values) {
      if (member(community.id, peer)) unawaited(sync(community, peer));
    }
  }

  /// Every few heartbeats, compares notes with a couple of random members.
  void heartbeat() {
    ticks += 1;
    if (ticks % cadence != 0) return;
    final self = courier.self?.address;
    for (final community in communities.values) {
      final others =
          members(community.id)
              .map((item) => item.address)
              .where((address) => address != self)
              .where((address) => courier.roster[address]?.blocked != true)
              .toList()
            ..shuffle();
      for (final peer in others.take(2)) {
        unawaited(sync(community, peer));
      }
    }
  }

  Future<void> receive(String from, Channel channel, String body) async {
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) return;
    final community = communities[data['c']];
    if (community == null) return;

    switch (data['op']) {
      case 'fetch' || 'piece':
        await Broadcast.instance.receive(from, channel, community, data);
      case 'room' || 'voice':
        await Stage.instance.receive(from, channel, community, data);
      case 'have':
        final proof = data['proof'];
        if (proof is Map<String, dynamic>) {
          final post = await verify(proof);
          if (post != null && post.author == from && post.note == Note.join) {
            await accept(post);
          }
        }
        if (!member(community.id, from)) return;
        final held = data['keys'];
        if (held is List) {
          for (final id in community.keys.keys) {
            if (!held.contains(id)) unawaited(hand(community, from, id));
          }
        }
        final theirs = <String, int>{};
        final raw = data['clock'];
        if (raw is Map) {
          for (final entry in raw.entries) {
            if (entry.key is String && entry.value is int) {
              theirs[entry.key as String] = entry.value as int;
            }
          }
        }
        final missing = [
          for (final post in posts[community.id] ?? const <Post>[])
            if (post.seq > (theirs[post.author] ?? 0)) post,
        ]..sort((alpha, beta) => alpha.seq.compareTo(beta.seq));
        var batch = <Map<String, dynamic>>[];
        var size = 0;
        for (final post in missing) {
          if (size + post.frame.length > bundle && batch.isNotEmpty) {
            send(channel, from, {
              'op': 'posts',
              'c': community.id,
              'items': batch,
            });
            batch = [];
            size = 0;
          }
          batch.add(jsonDecode(post.frame) as Map<String, dynamic>);
          size += post.frame.length;
        }
        if (batch.isNotEmpty) {
          send(channel, from, {
            'op': 'posts',
            'c': community.id,
            'items': batch,
          });
        }
        final ours = clock(community.id);
        final behind = theirs.entries.any(
          (entry) => entry.value > (ours[entry.key] ?? 0),
        );
        if (behind && data['reply'] != true) {
          send(channel, from, {
            'op': 'have',
            'c': community.id,
            'clock': ours,
            'keys': community.keys.keys.toList(),
            'reply': true,
          });
        }
      case 'rekey':
        if (!member(community.id, from)) return;
        final sealed = data['k'];
        if (sealed is! String) return;
        final inner = await courier.reveal(from, channel, sealed);
        if (inner == null) return;
        final given = jsonDecode(inner) as Map;
        final secret = base64.decode(given['key'] as String);
        final id = given['id'];
        final at = given['at'];
        if (secret.length != 32 || id != Community.fingerprint(secret)) return;
        if (community.keys.containsKey(id)) return;
        community.keys[id as String] = secret;
        if (at is int && at > community.rotated) {
          community
            ..epoch = id
            ..rotated = at;
          rotations.remove(community.id)?.cancel();
        }
        await Ledger.gather(community);
        notifyListeners();
      case 'posts':
        final items = data['items'];
        if (items is! List) return;
        final fresh = <Map<String, dynamic>>[];
        for (final item in items.take(500)) {
          if (item is! Map<String, dynamic>) continue;
          final post = await verify(item);
          if (post != null && await accept(post)) fresh.add(item);
        }
        if (fresh.isNotEmpty) {
          developer.log(
            'Received ${fresh.length} new community posts from a member',
            name: 'Mesh.receive',
            level: 500,
          );
        }
    }
  }
}

/// What the posts of a community add up to.
class Standing {
  final Map<String, Member> members;
  final Map<String, DateTime> removed;
  final Map<String, Set<String>> votes;

  const Standing(this.members, this.removed, this.votes);
}
