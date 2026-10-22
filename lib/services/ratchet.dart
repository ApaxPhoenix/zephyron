import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/sql/ledger.dart';

/// Thrown when a message cannot be opened with the session held for a peer.
class Unreadable implements Exception {
  final String reason;

  const Unreadable(this.reason);

  @override
  String toString() => 'Unreadable message: $reason';
}

/// Thrown when there is no session yet and one has to be agreed first.
class Unpaired implements Exception {
  const Unpaired();
}

/// An X25519 key pair kept as raw bytes.
class Pair {
  final Uint8List secret;
  final Uint8List public;

  const Pair(this.secret, this.public);

  static final X25519 curve = X25519();

  static Future<Pair> fresh() async => seeded(Ratchet.random(32));

  static Future<Pair> seeded(List<int> seed) async {
    final pair = await curve.newKeyPairFromSeed(seed);
    final public = await pair.extractPublicKey();
    return Pair(
      Uint8List.fromList(await pair.extractPrivateKeyBytes()),
      Uint8List.fromList(public.bytes),
    );
  }

  Future<Uint8List> agree(List<int> remote) async {
    final shared = await curve.sharedSecretKey(
      keyPair: SimpleKeyPairData(
        secret,
        publicKey: SimplePublicKey(public, type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      ),
      remotePublicKey: SimplePublicKey(remote, type: KeyPairType.x25519),
    );
    return Uint8List.fromList(await shared.extractBytes());
  }

  Map<String, dynamic> toJson() => {
    'secret': base64.encode(secret),
    'public': base64.encode(public),
  };

  factory Pair.fromJson(Map<String, dynamic> json) => Pair(
    base64.decode(json['secret'] as String),
    base64.decode(json['public'] as String),
  );
}

/// Double Ratchet state for one trustee.
class Bond {
  Uint8List root;
  Pair mine;
  Uint8List? theirs;
  Uint8List? sending;
  Uint8List? receiving;
  int sent;
  int received;
  int previous;

  /// Keys for messages that arrived out of order, by "ratchet key:number".
  final Map<String, String> skipped;

  /// X3DH details repeated on every message until the peer answers.
  Map<String, dynamic>? opening;

  Bond({
    required this.root,
    required this.mine,
    this.theirs,
    this.sending,
    this.receiving,
    this.sent = 0,
    this.received = 0,
    this.previous = 0,
    Map<String, String>? skipped,
    this.opening,
  }) : skipped = skipped ?? {};

  Map<String, dynamic> toJson() => {
    'root': base64.encode(root),
    'mine': mine.toJson(),
    'theirs': theirs == null ? null : base64.encode(theirs!),
    'sending': sending == null ? null : base64.encode(sending!),
    'receiving': receiving == null ? null : base64.encode(receiving!),
    'sent': sent,
    'received': received,
    'previous': previous,
    'skipped': skipped,
    'opening': opening,
  };

  factory Bond.fromJson(Map<String, dynamic> json) {
    Uint8List? bytes(Object? value) =>
        value is String ? base64.decode(value) : null;
    return Bond(
      root: base64.decode(json['root'] as String),
      mine: Pair.fromJson(Map<String, dynamic>.from(json['mine'] as Map)),
      theirs: bytes(json['theirs']),
      sending: bytes(json['sending']),
      receiving: bytes(json['receiving']),
      sent: json['sent'] as int? ?? 0,
      received: json['received'] as int? ?? 0,
      previous: json['previous'] as int? ?? 0,
      skipped: Map<String, String>.from(json['skipped'] as Map? ?? {}),
      opening: json['opening'] == null
          ? null
          : Map<String, dynamic>.from(json['opening'] as Map),
    );
  }
}

/// End-to-end encryption between two identities, on top of Tor.
///
/// Sessions start with X3DH against the peer's identity and signed prekey,
/// then follow the Double Ratchet, so every message has its own key and a
/// stolen key exposes neither earlier nor later messages. Bundles travel in
/// Ed25519-signed frames, which is what makes them trustworthy.
///
/// Of each pair, the identity with the smaller address always starts the
/// session (the lead). The other asks it to, so two people writing to each
/// other at the same moment never end up with mismatched sessions.
class Ratchet {
  /// Prekeys are replaced this often...
  static const Duration rotation = Duration(days: 7);

  /// ...and old ones kept this long for sessions started against them.
  static const Duration retention = Duration(days: 30);

  /// Most message keys skipped in one chain, and kept in total.
  static const int gap = 500;
  static const int hoard = 1000;

  static final Map<String, Future<void>> locks = {};

  /// Smallest size class a sealed message is padded to.
  static const int floor = 256;

  /// The size class for [length] bytes: 256, 512, 1024 and so on, so a
  /// ciphertext's length tells an observer only roughly how big it is.
  static int bucket(int length) {
    var size = floor;
    while (size < length) {
      size *= 2;
    }
    return size;
  }

  /// Prefixes [clear] with its length and pads it with zeros to [width],
  /// or to its size class. The zeros are hidden by the encryption around it.
  static Uint8List pad(List<int> clear, {int? width}) {
    final size = width ?? bucket(clear.length + 4);
    if (clear.length + 4 > size) {
      throw ArgumentError('${clear.length} bytes do not fit in $size');
    }
    final out = Uint8List(size);
    ByteData.view(out.buffer).setUint32(0, clear.length);
    out.setRange(4, 4 + clear.length, clear);
    return out;
  }

  static Uint8List unpad(Uint8List padded) {
    if (padded.length < 4) throw const Unreadable('too short to unpad');
    final length = ByteData.view(
      padded.buffer,
      padded.offsetInBytes,
    ).getUint32(0);
    if (length > padded.length - 4) throw const Unreadable('bad padding');
    return Uint8List.sublistView(padded, 4, 4 + length);
  }

  static Uint8List random(int length) {
    final source = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => source.nextInt(256)),
    );
  }

  /// Runs [task] after any other work on the session in [slot] has finished.
  static Future<T> guarded<T>(String slot, Future<T> Function() task) {
    final previous = locks[slot] ?? Future<void>.value();
    final result = previous.then((_) => task());
    locks[slot] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// This identity's long-term X25519 key, derived from its seed.
  static Future<Pair> identity(Identity self) {
    final seed = hex(self.private).sublist(0, 32);
    return Pair.seeded(
      hashing.sha256.convert([...utf8.encode('zephyron/ik'), ...seed]).bytes,
    );
  }

  static bool lead(Identity self, String peer) =>
      self.address.compareTo(peer) < 0;

  static Uint8List hex(String text) {
    final bytes = Uint8List(text.length ~/ 2);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = int.parse(
        text.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    return bytes;
  }

  static Future<List<Map<String, dynamic>>> prekeys(Identity self) async {
    final stored = await Ledger.read('prekeys:${self.address}');
    final list = (stored?['keys'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    final fresh =
        list.isNotEmpty &&
        now - (list.last['created'] as int) < rotation.inMilliseconds;
    if (fresh) return list;

    final pair = await Pair.fresh();
    list.add({
      'id': list.isEmpty ? 1 : (list.last['id'] as int) + 1,
      'created': now,
      ...pair.toJson(),
    });
    list.removeWhere(
      (item) =>
          item != list.last &&
          now - (item['created'] as int) > retention.inMilliseconds,
    );
    await Ledger.write('prekeys:${self.address}', {'keys': list});
    return list;
  }

  /// What a peer needs to start a session with this identity.
  static Future<Map<String, dynamic>> bundle(Identity self) async {
    final current = (await prekeys(self)).last;
    return {
      'ik': base64.encode((await identity(self)).public),
      'id': current['id'],
      'spk': current['public'],
    };
  }

  /// Remembers a peer's bundle, taken from a frame they signed.
  static Future<void> learn(String peer, Object? bundle) async {
    if (bundle is! Map) return;
    final ik = bundle['ik'];
    final spk = bundle['spk'];
    final id = bundle['id'];
    if (ik is! String || spk is! String || id is! int) return;
    if (base64.decode(ik).length != 32 || base64.decode(spk).length != 32) {
      return;
    }
    await Ledger.write('bundle:$peer', {'ik': ik, 'spk': spk, 'id': id});
  }

  static String slot(Identity self, String peer) =>
      'ratchet:${self.address}:$peer';

  static Future<Bond?> session(Identity self, String peer) async {
    final stored = await Ledger.read(slot(self, peer));
    return stored == null ? null : Bond.fromJson(stored);
  }

  static Future<void> keep(Identity self, String peer, Bond state) =>
      Ledger.write(slot(self, peer), state.toJson());

  static Future<bool> paired(Identity self, String peer) async =>
      await Ledger.read(slot(self, peer)) != null;

  static Future<void> forget(Identity self, String peer) =>
      Ledger.remove(slot(self, peer));

  static Future<Uint8List> derive(
    List<int> material, {
    List<int> salt = const [],
    required String info,
    int length = 32,
  }) async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: length).deriveKey(
      secretKey: SecretKey(material),
      nonce: salt,
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Root chain step: a new root key and a new chain key.
  static Future<(Uint8List, Uint8List)> step(
    Uint8List root,
    Uint8List shared,
  ) async {
    final out = await derive(
      shared,
      salt: root,
      info: 'zephyron/ratchet',
      length: 64,
    );
    return (out.sublist(0, 32), out.sublist(32));
  }

  /// Symmetric chain step: the next chain key and this message's key.
  static (Uint8List, Uint8List) advance(Uint8List chain) {
    final mac = hashing.Hmac(hashing.sha256, chain);
    return (
      Uint8List.fromList(mac.convert([2]).bytes),
      Uint8List.fromList(mac.convert([1]).bytes),
    );
  }

  /// Starts a session as the lead, against the peer's stored bundle.
  static Future<Bond> begin(Identity self, String peer) async {
    final stored = await Ledger.read('bundle:$peer');
    if (stored == null) throw const Unpaired();
    final ik = base64.decode(stored['ik'] as String);
    final spk = base64.decode(stored['spk'] as String);
    final mine = await identity(self);
    final ephemeral = await Pair.fresh();

    final secret = await derive([
      ...List.filled(32, 0xFF),
      ...await mine.agree(spk),
      ...await ephemeral.agree(ik),
      ...await ephemeral.agree(spk),
    ], info: 'zephyron/x3dh');
    final ratchet = await Pair.fresh();
    final (root, sending) = await step(secret, await ratchet.agree(spk));
    final state = Bond(
      root: root,
      mine: ratchet,
      theirs: spk,
      sending: sending,
      opening: {
        'ik': base64.encode(mine.public),
        'ek': base64.encode(ephemeral.public),
        'id': stored['id'],
      },
    );
    await keep(self, peer, state);
    return state;
  }

  /// Answers a lead's opening as the other side of the session.
  static Future<Bond> answer(
    Identity self,
    Map<String, dynamic> opening,
  ) async {
    final keys = await prekeys(self);
    final chosen = keys.where((item) => item['id'] == opening['id']);
    if (chosen.isEmpty) throw const Unreadable('prekey has expired');
    final prekey = Pair.fromJson(chosen.first);
    final mine = await identity(self);
    final ik = base64.decode(opening['ik'] as String);
    final ek = base64.decode(opening['ek'] as String);

    final secret = await derive([
      ...List.filled(32, 0xFF),
      ...await prekey.agree(ik),
      ...await mine.agree(ek),
      ...await prekey.agree(ek),
    ], info: 'zephyron/x3dh');
    return Bond(root: secret, mine: prekey);
  }

  static Future<Uint8List> lock(
    Uint8List key,
    List<int> clear,
    List<int> header,
  ) async {
    final material = await derive(key, info: 'zephyron/message', length: 44);
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: SecretKey(material.sublist(0, 32)),
      nonce: material.sublist(32),
      aad: header,
    );
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Uint8List> unlock(
    Uint8List key,
    Uint8List sealed,
    List<int> header,
  ) async {
    if (sealed.length < 16) throw const Unreadable('too short');
    final material = await derive(key, info: 'zephyron/message', length: 44);
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          sealed.sublist(0, sealed.length - 16),
          nonce: material.sublist(32),
          mac: Mac(sealed.sublist(sealed.length - 16)),
        ),
        secretKey: SecretKey(material.sublist(0, 32)),
        aad: header,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const Unreadable('authentication failed');
    }
  }

  /// Encrypts [clear] for [peer]. Throws [Unpaired] when the other side has
  /// to start the session first.
  static Future<Map<String, dynamic>> seal(
    Identity self,
    String peer,
    List<int> clear,
  ) => guarded(slot(self, peer), () async {
    var state = await session(self, peer);
    if (state == null) {
      if (!lead(self, peer)) throw const Unpaired();
      state = await begin(self, peer);
    }
    if (state.sending == null) {
      // The answering side has not heard from the lead since a restart of
      // the session; it cannot send until the lead's ratchet key arrives.
      throw const Unpaired();
    }
    final (chain, key) = advance(state.sending!);
    final header = {
      'dh': base64.encode(state.mine.public),
      'pn': state.previous,
      'n': state.sent,
      if (state.opening != null) 'x3dh': state.opening,
    };
    final encoded = utf8.encode(jsonEncode(header));
    final sealed = await lock(key, pad(clear), encoded);
    state
      ..sending = chain
      ..sent += 1;
    await keep(self, peer, state);
    return {'h': header, 'c': base64.encode(sealed)};
  });

  /// Decrypts an envelope from [peer], starting a session if it opens one.
  static Future<Uint8List> open(
    Identity self,
    String peer,
    Map<String, dynamic> envelope,
  ) => guarded(slot(self, peer), () async {
    final header = envelope['h'];
    final body = envelope['c'];
    if (header is! Map<String, dynamic> || body is! String) {
      throw const Unreadable('malformed');
    }
    final dh = base64.decode(header['dh'] as String);
    final count = header['n'] as int;
    final previous = header['pn'] as int;
    final encoded = utf8.encode(jsonEncode(header));
    final sealed = base64.decode(body);

    var state = await session(self, peer);
    final opening = header['x3dh'];
    if (opening is Map<String, dynamic> && !lead(self, peer)) {
      final known = state?.theirs;
      final same = known != null && _equal(known, dh) && state!.received > 0;
      if (state == null || !same) {
        state = await answer(self, opening);
      }
    }
    if (state == null) throw const Unreadable('no session');

    final slot = '${base64.encode(dh)}:$count';
    final kept = state.skipped.remove(slot);
    if (kept != null) {
      final clear = await unlock(base64.decode(kept), sealed, encoded);
      await keep(self, peer, state);
      return unpad(clear);
    }

    final working = Bond.fromJson(state.toJson());
    if (working.theirs == null || !_equal(working.theirs!, dh)) {
      await skip(working, previous);
      working
        ..previous = working.sent
        ..sent = 0
        ..received = 0
        ..theirs = dh;
      final (root, receiving) = await step(
        working.root,
        await working.mine.agree(dh),
      );
      working.mine = await Pair.fresh();
      final (next, sending) = await step(root, await working.mine.agree(dh));
      working
        ..root = next
        ..receiving = receiving
        ..sending = sending;
    }
    await skip(working, count);
    final (chain, key) = advance(working.receiving!);
    final clear = await unlock(key, sealed, encoded);
    working
      ..receiving = chain
      ..received += 1
      ..opening = null;
    await keep(self, peer, working);
    return unpad(clear);
  });

  /// Stores keys for messages up to [until] that have not arrived yet.
  static Future<void> skip(Bond state, int until) async {
    if (state.receiving == null) return;
    if (until - state.received > gap) throw const Unreadable('too far ahead');
    while (state.received < until) {
      final (chain, key) = advance(state.receiving!);
      state.skipped['${base64.encode(state.theirs!)}:${state.received}'] =
          base64.encode(key);
      state
        ..receiving = chain
        ..received += 1;
    }
    while (state.skipped.length > hoard) {
      state.skipped.remove(state.skipped.keys.first);
    }
  }

  static bool _equal(List<int> alpha, List<int> beta) {
    if (alpha.length != beta.length) return false;
    for (var index = 0; index < alpha.length; index++) {
      if (alpha[index] != beta[index]) return false;
    }
    return true;
  }

  /// Seals one attachment chunk with the per-file key from its manifest.
  /// With [width], every chunk is padded to that many bytes, so the last
  /// one looks like the rest and the file's exact size stays hidden.
  static Future<Uint8List> chunk(
    Uint8List key,
    int seq,
    List<int> clear, {
    int? width,
  }) {
    return lock(
      key,
      pad(clear, width: width == null ? null : width + 4),
      utf8.encode('chunk:$seq'),
    );
  }

  static Future<Uint8List> unchunk(
    Uint8List key,
    int seq,
    Uint8List sealed,
  ) async {
    return unpad(await unlock(key, sealed, utf8.encode('chunk:$seq')));
  }
}
