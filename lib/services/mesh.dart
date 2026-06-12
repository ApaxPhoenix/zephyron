import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:flutter/foundation.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/ratchet.dart';
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

  final Map<String, Community> communities = {};
  final Map<String, List<Post>> posts = {};
  final Set<String> known = {};
  int ticks = 0;

  Courier get courier => Courier.instance;

  Future<void> start() async {
    communities.clear();
    posts.clear();
    known.clear();
    for (final community in await Ledger.communities()) {
      communities[community.id] = community;
    }
    for (final post in await Ledger.posts()) {
      index(post);
    }
    notifyListeners();
  }

  void stop() {
    communities.clear();
    posts.clear();
    known.clear();
    ticks = 0;
    notifyListeners();
  }

  void index(Post post) {
    if (!known.add(post.id)) return;
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

  /// Members by seniority: the founder, then everyone in the order they
  /// joined. That order is the only thing that sets anyone apart.
  List<Member> members(String community) {
    final group = communities[community];
    if (group == null) return const [];
    final found = <String, Member>{
      group.founder: Member(
        address: group.founder,
        name: '',
        since: group.created,
      ),
    };
    for (final post in posts[community] ?? const <Post>[]) {
      if (post.note != Note.join) continue;
      final avatar = post.meta['avatar'];
      final existing = found[post.author];
      if (existing == null) {
        found[post.author] = Member(
          address: post.author,
          name: post.text,
          since: post.time,
          avatar: avatar is String && avatar.isNotEmpty
              ? base64.decode(avatar)
              : null,
        );
      } else {
        existing.name = post.text;
        if (avatar is String && avatar.isNotEmpty) {
          existing.avatar = base64.decode(avatar);
        }
      }
    }
    final list = found.values.toList()
      ..sort((alpha, beta) {
        if (alpha.address == group.founder) return -1;
        if (beta.address == group.founder) return 1;
        return alpha.since.compareTo(beta.since);
      });
    return list;
  }

  bool member(String community, String address) =>
      members(community).any((item) => item.address == address);

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

  List<Post> messages(String community, String channel) => [
    for (final post in posts[community] ?? const <Post>[])
      if (post.note == Note.text &&
          post.channel == channel &&
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
  List<Community> ordered() {
    DateTime active(Community group) => latest(group.id)?.time ?? group.joined;
    return communities.values.toList()..sort((alpha, beta) {
      if (alpha.pinned != beta.pinned) return alpha.pinned ? -1 : 1;
      return active(beta).compareTo(active(alpha));
    });
  }

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
        frame['x'],
      ].join('\n'),
    ),
  );

  static List<int> associated(Map<String, dynamic> frame) => utf8.encode(
    [frame['c'], frame['i'], frame['a'], frame['s'], frame['t']].join('\n'),
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
    };
    final keys = await material(community.key, frame['i'] as String);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(
        jsonEncode({'ch': channel, 'n': note.name, 'tx': text, 'm': meta}),
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

      final keys = await material(community.key, id);
      final bytes = base64.decode(sealed);
      if (bytes.length < 16) return null;
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          bytes.sublist(0, bytes.length - 16),
          nonce: keys.sublist(32),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: SecretKey(keys.sublist(0, 32)),
        aad: associated(frame),
      );
      final body = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
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
    if (!await Ledger.publish(post)) {
      known.add(post.id);
      return false;
    }
    index(post);
    if (post.note == Note.about) await revise(post);
    notifyListeners();
    return true;
  }

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
    'founder': community.founder,
    'created': community.created.millisecondsSinceEpoch,
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
    try {
      if (base64.decode(key).length != 32) return null;
    } catch (_) {
      return null;
    }
    return {
      'community': id,
      'name': Profile.clip(meta['name'], Community.names),
      'about': Profile.clip(meta['about'], Community.abouts),
      'key': key,
      'founder': founder,
      'created': created,
      'by': from,
    };
  }

  /// Joins from an invitation and asks whoever sent it for the history.
  Future<Community?> join(Map<String, dynamic> invitation) async {
    final id = invitation['community'] as String;
    final existing = communities[id];
    if (existing != null) return existing;
    final community = Community(
      id: id,
      name: invitation['name'] as String? ?? 'Community',
      about: invitation['about'] as String? ?? '',
      key: base64.decode(invitation['key'] as String),
      founder: invitation['founder'] as String,
      created: DateTime.fromMillisecondsSinceEpoch(
        invitation['created'] as int,
      ),
    );
    communities[id] = community;
    await Ledger.gather(community);
    final by = invitation['by'] as String?;
    await post(
      community,
      channel: community.general,
      note: Note.join,
      text: courier.me.name,
      meta: introduction(by),
    );
    if (by != null) unawaited(sync(community, by));
    notifyListeners();
    return community;
  }

  Future<void> leave(String id) async {
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
      case 'have':
        final proof = data['proof'];
        if (proof is Map<String, dynamic>) {
          final post = await verify(proof);
          if (post != null && post.author == from && post.note == Note.join) {
            await accept(post);
          }
        }
        if (!member(community.id, from)) return;
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
            'reply': true,
          });
        }
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
