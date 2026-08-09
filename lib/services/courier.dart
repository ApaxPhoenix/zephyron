import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hashing;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/services/catalog.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/services/shield.dart';
import 'package:zephyron/services/stage.dart';
import 'package:zephyron/services/still.dart';
import 'package:zephyron/sql/ledger.dart';
import 'package:zephyron/sql/session.dart';
import 'package:zephyron/wrappers/tor.dart';

class Presence {
  DateTime? seen;
  DateTime? typing;
  DateTime? probed;
  int? latency;

  bool get online =>
      seen != null && DateTime.now().difference(seen!) < Courier.horizon;

  bool get composing => typing != null && DateTime.now().isBefore(typing!);
}

class Channel {
  final Socket socket;
  final bool inbound;
  final DateTime opened = DateTime.now();
  String? peer;
  DateTime used = DateTime.now();
  int sent = 0;
  int received = 0;
  StreamSubscription<Uint8List>? subscription;
  Future<bool> pipe = Future.value(true);
  Future<void> inbox = Future.value();
  bool alive = true;
  bool greeted = false;

  Channel(this.socket, {this.peer, this.inbound = false});

  Future<bool> send(Map<String, dynamic> frame) {
    if (!alive) return Future.value(false);
    final line = '${jsonEncode(frame)}\n';
    used = DateTime.now();
    sent += line.length;
    return pipe = pipe.then((_) async {
      if (!alive) return false;
      try {
        socket.write(line);
        await socket.flush();
        return true;
      } catch (_) {
        close();
        return false;
      }
    });
  }

  void close() {
    if (!alive) return;
    alive = false;
    subscription?.cancel();
    socket.destroy();
  }
}

class Transfer {
  final String id;
  final String peer;
  final Channel channel;
  final Kind kind;
  final String text;
  final String name;
  final String mime;
  final String sha;
  final int size;
  final int width;
  final int height;
  final int time;
  final int fuse;
  final int duration;

  /// A video's thumbnail, as base64 JPEG.
  final String? thumb;

  /// Key that seals each chunk, carried inside the encrypted manifest.
  final Uint8List key;
  final BytesBuilder buffer = BytesBuilder(copy: false);
  int next = 0;

  Transfer({
    required this.id,
    required this.peer,
    required this.channel,
    required this.kind,
    required this.text,
    required this.name,
    required this.mime,
    required this.sha,
    required this.size,
    required this.width,
    required this.height,
    required this.time,
    required this.key,
    this.fuse = 0,
    this.duration = 0,
    this.thumb,
  });

  double get progress => size == 0 ? 0 : buffer.length / size;
}

class Courier extends ChangeNotifier {
  static final Courier instance = Courier._();

  Courier._();

  static const int port = 8080;
  static const int limit = 4096;
  static const int line = 512 * 1024;
  static const int slice = 48 * 1024;
  static const int portrait = 256 * 1024;

  /// Largest banner, so its frame stays under [line] once base64 encoded.
  static const int banner = 360 * 1024;
  static const String protocol = 'zephyron/1';
  static const Duration horizon = Duration(seconds: 90);

  /// A random pause before messages, files and receipts go out, so their
  /// timing says less about when someone typed or read. Tests set it to
  /// nothing.
  static Duration Function() jitter = natural;

  static Duration natural() =>
      Duration(milliseconds: 150 + Random.secure().nextInt(1050));

  static Future<void> hesitate() async {
    final pause = jitter();
    if (pause > Duration.zero) await Future<void>.delayed(pause);
  }

  final ValueNotifier<Reach> reach = ValueNotifier<Reach>(Reach.offline);
  final ValueNotifier<ThemeMode> theme = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  /// Whether screen security is on; it stays on while the vault is locked.
  final ValueNotifier<bool> shielded = ValueNotifier<bool>(true);
  final StreamController<Message> arrivals =
      StreamController<Message>.broadcast();

  Identity? self;
  ed25519.PrivateKey? secret;
  ServerSocket? server;
  Timer? pulse;
  Timer? sweeper;
  String? focus;
  int generation = 0;
  Profile me = Profile();
  Preferences prefs = Preferences();

  final Map<String, Trustee> roster = {};
  final Map<String, List<Message>> threads = {};
  final Map<String, Presence> presence = {};
  final Map<String, Channel> channels = {};
  final Map<String, Future<Channel>> dialing = {};
  final Map<String, Completer<void>> waiting = {};

  /// Peers we are waiting on to agree an end-to-end session.
  final Map<String, Completer<void>> pairing = {};

  /// When each peer was last asked to repair a broken session.
  final Map<String, DateTime> mended = {};

  /// Messages handed to trustees to pass on, by id.
  final Set<String> entrusted = {};

  /// When parcels were last offered to each recipient.
  final Map<String, DateTime> forwarded = {};

  /// How long a trustee holds a parcel before giving up.
  static const Duration keep = Duration(days: 7);
  final Map<String, Transfer> transfers = {};
  final Map<String, double> progress = {};
  final Map<String, DateTime> hinted = {};
  final Set<String> flushing = {};
  final Set<Channel> live = {};

  bool get ready => self != null;

  bool get invisible => me.availability == Availability.invisible;

  Future<void> start(Identity identity) async {
    if (self?.address == identity.address) return;
    await stop();

    final epoch = ++generation;
    self = identity;
    secret = ed25519.PrivateKey(decode(identity.private));

    try {
      await Ledger.ensure();
      final people = await Ledger.trustees();
      final history = await Ledger.everything();
      final stored = await Ledger.read('profile');
      final chosen = await Ledger.read('preferences');
      if (epoch != generation) return;

      final profile = stored == null ? Profile() : Profile.fromJson(stored);
      if (profile.name.isEmpty) profile.name = Session.profile ?? '';
      if (profile.revision == 0) profile.revision = 1;
      me = profile;
      prefs = chosen == null ? Preferences() : Preferences.fromJson(chosen);
      theme.value = prefs.theme;
      shielded.value = prefs.shield;
      unawaited(Shield.apply(prefs.shield));

      roster
        ..clear()
        ..addEntries(people.map((item) => MapEntry(item.address, item)));
      threads.clear();
      for (final message in history) {
        threads.putIfAbsent(message.peer, () => []).add(message);
      }
      await Mesh.instance.start();
      await Catalog.instance.start();
      notifyListeners();
    } catch (error) {
      developer.log(
        'Failed to hydrate trustees, profile and history from identity store',
        name: 'Courier.start',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }

    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      if (epoch != generation) {
        await socket.close();
        return;
      }
      server = socket;
      server!.listen(
        (wire) => adopt(Channel(wire, inbound: true), wire),
        onError: (Object error) {
          developer.log(
            'Onion service listener reported a socket error',
            name: 'Courier.start',
            level: 900,
            error: error,
          );
        },
      );
      developer.log(
        'Bound onion service listener on 127.0.0.1:$port',
        name: 'Courier.start',
        level: 800,
      );
    } catch (error) {
      developer.log(
        'Failed to bind onion service listener on 127.0.0.1:$port',
        name: 'Courier.start',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }

    unawaited(connect(epoch));
    pulse = Timer.periodic(const Duration(seconds: 20), (_) => heartbeat());
    unawaited(expire());
    sweeper = Timer.periodic(const Duration(seconds: 10), (_) => expire());
  }

  Future<void> stop() async {
    generation += 1;
    pulse?.cancel();
    pulse = null;
    sweeper?.cancel();
    sweeper = null;

    final address = self?.address;
    self = null;
    secret = null;
    focus = null;
    me = Profile();
    prefs = Preferences();

    await server?.close();
    server = null;

    for (final channel in {...channels.values, ...live}) {
      channel.close();
    }
    channels.clear();
    live.clear();
    dialing.clear();
    flushing.clear();
    hinted.clear();
    transfers.clear();
    progress.clear();
    for (final pending in [...waiting.values, ...pairing.values]) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Courier stopped'));
      }
    }
    waiting.clear();
    pairing.clear();
    mended.clear();
    roster.clear();
    threads.clear();
    presence.clear();
    Mesh.instance.stop();
    Catalog.instance.stop();
    reach.value = Reach.offline;
    theme.value = ThemeMode.system;
    shielded.value = true;
    unawaited(Shield.apply(true));
    await Locker.sweep();

    if (address != null) await Sentinel.summon().retract(address);
    notifyListeners();
  }

  Future<void> connect(int epoch) async {
    reach.value = Reach.connecting;
    try {
      final folder = await getApplicationSupportDirectory();
      await Sentinel.summon().prepare('${folder.path}/tor');
      if (epoch != generation) return;
      reach.value = Reach.online;
      heartbeat();
    } catch (error) {
      if (epoch != generation) return;
      reach.value = Reach.offline;
      developer.log(
        'Tor daemon unavailable, retrying shortly',
        name: 'Courier.connect',
        level: 900,
        error: error,
      );
      Timer(const Duration(seconds: 15), () {
        if (epoch == generation) connect(epoch);
      });
    }
  }

  void heartbeat() {
    if (reach.value != Reach.online || self == null) return;
    Mesh.instance.heartbeat();
    Catalog.instance.heartbeat();
    unawaited(dispatch());
    final now = DateTime.now();
    for (final trustee in roster.values.toList()) {
      if (trustee.blocked) continue;
      final peer = trustee.address;
      if (undelivered(peer).isNotEmpty) {
        unawaited(flush(peer));
        continue;
      }
      if (!trustee.trusted) continue;
      final state = track(peer);
      final quiet =
          state.seen == null || now.difference(state.seen!) > horizon * 0.6;
      final rested =
          state.probed == null ||
          now.difference(state.probed!) > const Duration(seconds: 60);
      if (quiet && rested) unawaited(ping(peer));
    }
  }

  Presence track(String peer) => presence.putIfAbsent(peer, Presence.new);

  Presence status(String peer) => presence[peer] ?? Presence();

  bool online(String peer) {
    if (roster[peer]?.availability == Availability.invisible) return false;
    return status(peer).online;
  }

  void adopt(Channel channel, Stream<Uint8List> stream) {
    final pending = BytesBuilder(copy: false);
    live.add(channel);
    notifyListeners();
    channel.subscription = stream.listen(
      (chunk) {
        channel.received += chunk.length;
        var start = 0;
        for (var index = 0; index < chunk.length; index++) {
          if (chunk[index] != 0x0A) continue;
          pending.add(chunk.sublist(start, index));
          start = index + 1;
          final text = utf8.decode(pending.takeBytes(), allowMalformed: true);
          if (text.trim().isEmpty) continue;
          channel.inbox = channel.inbox
              .then((_) => receive(channel, text))
              .catchError((Object _) {});
        }
        if (start < chunk.length) pending.add(chunk.sublist(start));
        if (pending.length > line) drop(channel);
      },
      onError: (Object _) => drop(channel),
      onDone: () => drop(channel),
      cancelOnError: true,
    );
  }

  void drop(Channel channel) {
    channel.close();
    if (live.remove(channel)) notifyListeners();
    transfers.removeWhere((_, item) => identical(item.channel, channel));
    final peer = channel.peer;
    if (peer != null && identical(channels[peer], channel)) {
      channels.remove(peer);
    }
  }

  Future<Channel> dial(String peer) {
    final open = channels[peer];
    if (open != null && open.alive) return Future.value(open);

    return dialing[peer] ??= () async {
      final epoch = generation;
      try {
        final tunnel = await Tor.connect(peer, 80);
        final channel = Channel(tunnel.socket, peer: peer);
        if (epoch != generation) {
          channel.close();
          throw StateError('Courier restarted while dialing');
        }
        adopt(channel, tunnel.stream);
        channels[peer] = channel;
        greet(peer, channel);
        return channel;
      } finally {
        dialing.remove(peer);
      }
    }();
  }

  void greet(String peer, Channel channel) {
    if (channel.greeted || roster[peer]?.trusted != true || self == null) {
      return;
    }
    channel.greeted = true;
    Mesh.instance.greet(peer);
    Catalog.instance.greet(peer, channel);
    final known = roster[peer]!;
    final identity = self!;
    unawaited(() async {
      channel.send(
        seal(
          Signal.hello,
          peer,
          body: jsonEncode({
            'revision': me.revision,
            'fuse': known.fuse,
            'fused': known.fused,
            'bundle': await Ratchet.bundle(identity),
          }),
        ),
      );
    }());
  }

  /// Makes sure an end-to-end session with [peer] exists or can be started.
  Future<void> pair(String peer, Channel channel) async {
    final identity = self!;
    if (await Ratchet.paired(identity, peer)) return;
    if (Ratchet.lead(identity, peer) &&
        await Ledger.read('bundle:$peer') != null) {
      return;
    }
    final waiter = pairing.putIfAbsent(peer, Completer<void>.new);
    channel.send(
      seal(
        Signal.session,
        peer,
        body: jsonEncode({
          'bundle': await Ratchet.bundle(identity),
          'want': true,
        }),
      ),
    );
    try {
      await waiter.future.timeout(const Duration(seconds: 30));
    } finally {
      if (identical(pairing[peer], waiter)) pairing.remove(peer);
    }
  }

  void settle(String peer) {
    final waiter = pairing.remove(peer);
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  /// Encrypts [clear] for [peer], agreeing a session first when needed.
  Future<String> whisper(String peer, Channel channel, List<int> clear) async {
    await pair(peer, channel);
    try {
      return jsonEncode(await Ratchet.seal(self!, peer, clear));
    } on Unpaired {
      await Ratchet.forget(self!, peer);
      await pair(peer, channel);
      return jsonEncode(await Ratchet.seal(self!, peer, clear));
    }
  }

  /// Decrypts a frame body from [peer], or asks for the session to be
  /// repaired and returns null when it cannot be read.
  Future<String?> reveal(
    String peer,
    Channel channel,
    String body, {
    bool repair = true,
  }) async {
    try {
      final envelope = jsonDecode(body);
      if (envelope is! Map<String, dynamic>) return null;
      final clear = await Ratchet.open(self!, peer, envelope);
      return utf8.decode(clear);
    } catch (error) {
      developer.log(
        'Could not open an end-to-end encrypted frame, asking for a fresh session',
        name: 'Courier.reveal',
        level: 900,
        error: error,
      );
      // A relayed frame came through someone else, so asking them would not
      // reach the sender.
      if (repair) await mend(peer, channel);
      return null;
    }
  }

  /// Restarts a session that no longer lines up on both sides.
  Future<void> mend(String peer, Channel channel) async {
    final last = mended[peer];
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    mended[peer] = now;
    final identity = self!;
    if (Ratchet.lead(identity, peer) &&
        await Ledger.read('bundle:$peer') != null) {
      await Ratchet.forget(identity, peer);
      await open(peer, channel);
      return;
    }
    channel.send(
      seal(
        Signal.session,
        peer,
        body: jsonEncode({
          'bundle': await Ratchet.bundle(identity),
          'want': true,
        }),
      ),
    );
  }

  /// As the lead, starts a fresh session and sends its opening.
  Future<void> open(String peer, Channel channel) async {
    final identity = self!;
    final opening = await Ratchet.seal(identity, peer, utf8.encode('{}'));
    channel.send(
      seal(
        Signal.session,
        peer,
        body: jsonEncode({
          'bundle': await Ratchet.bundle(identity),
          'init': opening,
        }),
      ),
    );
  }

  Map<String, dynamic> seal(
    Signal kind,
    String to, {
    String? id,
    String body = '',
    DateTime? time,
  }) {
    final me = self!;
    final frame = <String, dynamic>{
      'v': protocol,
      'kind': kind.name,
      'id': id ?? token(),
      'from': me.address,
      'to': to,
      'time': (time ?? DateTime.now()).millisecondsSinceEpoch,
      'body': body,
      'key': me.public,
    };
    final signature = ed25519.sign(secret!, canonical(frame));
    frame['sig'] = encode(signature);
    return frame;
  }

  Uint8List canonical(Map<String, dynamic> frame) {
    return Uint8List.fromList(
      utf8.encode(
        [
          protocol,
          frame['kind'],
          frame['id'],
          frame['from'],
          frame['to'],
          frame['time'],
          frame['body'],
        ].join('\n'),
      ),
    );
  }

  bool authentic(Map<String, dynamic> frame) {
    try {
      if (frame['v'] != protocol) return false;
      if (frame['to'] != self?.address) return false;
      if (frame['kind'] is! String || frame['id'] is! String) return false;
      if (frame['time'] is! int || frame['body'] is! String) return false;
      final key = decode(frame['key'] as String);
      if (key.length != 32) return false;
      if (Identity.onion(key) != frame['from']) return false;
      final signature = decode(frame['sig'] as String);
      return ed25519.verify(
        ed25519.PublicKey(key),
        canonical(frame),
        signature,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> receive(Channel channel, String text) async {
    final epoch = generation;
    final now = DateTime.now();
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;

      if (decoded['kind'] == Signal.chunk.name) {
        final id = decoded['id'];
        final transfer = id is String ? transfers[id] : null;
        if (transfer == null || !identical(transfer.channel, channel)) return;

        final seq = decoded['seq'];
        final data = decoded['data'];
        if (seq != transfer.next || data is! String) {
          transfers.remove(transfer.id);
          return;
        }
        try {
          transfer.buffer.add(
            await Ratchet.unchunk(transfer.key, seq, base64.decode(data)),
          );
        } catch (_) {
          transfers.remove(transfer.id);
          return;
        }
        transfer.next += 1;
        if (transfer.buffer.length > transfer.size) {
          transfers.remove(transfer.id);
          return;
        }
        if (transfer.buffer.length < transfer.size) {
          if (transfer.next % 4 == 0) notifyListeners();
          return;
        }

        transfers.remove(transfer.id);
        final clear = transfer.buffer.takeBytes();
        if (hashing.sha256.convert(clear).toString() != transfer.sha) return;

        final sealed = await Locker.store(transfer.id, clear);
        if (epoch != generation) return;
        final sent = DateTime.fromMillisecondsSinceEpoch(transfer.time);
        final message = Message(
          id: transfer.id,
          peer: transfer.peer,
          mine: false,
          kind: transfer.kind,
          text: transfer.text,
          time: sent.isAfter(now) ? now : sent,
          status: Status.delivered,
          meta: {
            ...sealed,
            if (transfer.fuse > 0) 'fuse': transfer.fuse,
            'name': transfer.name,
            'mime': transfer.mime,
            'size': transfer.size,
            'width': transfer.width,
            'height': transfer.height,
            if (transfer.duration > 0) 'duration': transfer.duration,
            'thumb': ?transfer.thumb,
          },
        );
        if (!await Ledger.record(message)) return;
        deliver(message);
        acknowledge(channel, transfer.peer, transfer.id);
        notifyListeners();
        return;
      }
      if (!authentic(decoded)) return;

      final from = decoded['from'] as String;
      if (roster[from]?.blocked == true) {
        drop(channel);
        return;
      }
      channel.peer ??= from;
      if (channel.peer != from) return;
      final current = channels[from];
      if (current == null || !current.alive) channels[from] = channel;
      channel.used = now;
      greet(from, channel);

      final state = track(from);
      final wasOnline = state.online;
      state.seen = now;
      final offered = forwarded[from];
      if (offered == null ||
          now.difference(offered) > const Duration(seconds: 30)) {
        forwarded[from] = now;
        unawaited(release(from, channel));
      }

      final id = decoded['id'] as String;
      final body = decoded['body'] as String;
      final stamp = DateTime.fromMillisecondsSinceEpoch(decoded['time'] as int);
      final signal = Signal.values.where(
        (item) => item.name == decoded['kind'],
      );
      if (signal.isEmpty) return;

      switch (signal.first) {
        case Signal.hello:
          final greeting = jsonDecode(body) as Map;
          final known = roster[from];
          if (known != null && known.revision != greeting['revision']) {
            channel.send(seal(Signal.whois, from));
          }
          await adjust(from, greeting['fuse'], greeting['fused']);
          await Ratchet.learn(from, greeting['bundle']);
          if (Ratchet.lead(self!, from)) settle(from);
        case Signal.whois:
          if (roster[from]?.trusted == true) {
            channel.send(
              seal(
                Signal.profile,
                from,
                body: jsonEncode(me.toJson(banner: false)),
              ),
            );
            channel.send(seal(Signal.banner, from, body: cover()));
          }
        case Signal.profile:
          final known = roster[from];
          if (known == null || known.blocked) break;
          final profile = Profile.fromJson(
            Map<String, dynamic>.from(jsonDecode(body) as Map),
          );
          known.mailbox = Identity.valid(profile.mailbox)
              ? profile.mailbox
              : '';
          known
            ..alias = profile.name
            ..bio = profile.bio
            ..mood = profile.mood
            ..availability = profile.availability
            ..avatar = (profile.avatar?.length ?? 0) <= portrait
                ? profile.avatar
                : null
            ..revision = profile.revision;
          await Ledger.keep(known);
        case Signal.message:
          await incoming(
            from,
            id,
            stamp,
            body,
            channel: channel,
            answer: () => acknowledge(channel, from, id),
          );
        case Signal.file:
          if (await Ledger.exists(id)) {
            acknowledge(channel, from, id);
            break;
          }
          final inner = await reveal(from, channel, body);
          if (inner == null) break;
          final data = Map<String, dynamic>.from(jsonDecode(inner) as Map);
          final secret = data['key'];
          if (secret is! String) break;
          final key = base64.decode(secret);
          if (key.length != 32) break;
          final kind = Kind.values.firstWhere(
            (item) => item.name == data['kind'],
            orElse: () => Kind.text,
          );
          if (!const {
            Kind.image,
            Kind.gif,
            Kind.file,
            Kind.voice,
            Kind.video,
          }.contains(kind)) {
            break;
          }
          final size = data['size'];
          final sha = '${data['sha'] ?? ''}';
          if (size is! int || size <= 0 || size > Locker.ceiling) break;
          if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) break;
          if (!await admit(from)) break;

          final active = transfers.values
              .where((item) => item.peer == from)
              .length;
          if (active >= 3 || transfers.containsKey(id)) break;

          final name = Profile.clip(
            data['name'],
            120,
          ).replaceAll(RegExp(r'[/\\]'), '_');
          int dimension(Object? value) =>
              value is int && value > 0 && value < 20000 ? value : 0;
          transfers[id] = Transfer(
            id: id,
            peer: from,
            channel: channel,
            kind: kind,
            text: Profile.clip(data['text'], limit),
            name: name.isEmpty ? 'file' : name,
            mime: Profile.clip(data['mime'], 80),
            sha: sha,
            size: size,
            width: dimension(data['width']),
            height: dimension(data['height']),
            time: stamp.millisecondsSinceEpoch,
            fuse: clamp(data['fuse']),
            key: key,
            duration: switch (data['duration']) {
              final int value when value > 0 && value < 24 * 3600 * 1000 =>
                value,
              _ => 0,
            },
            thumb: switch (data['thumb']) {
              final String value
                  when kind == Kind.video &&
                      value.length <= Still.ceiling * 4 ~/ 3 + 4 =>
                value,
              _ => null,
            },
          );
        case Signal.chunk:
          break;
        case Signal.receipt:
          waiting.remove(id)?.complete();
          await upgrade(from, id, Status.delivered);
        case Signal.read:
          for (final item in body.split(',')) {
            await upgrade(from, item, Status.read);
          }
        case Signal.typing:
          state.typing = now.add(const Duration(seconds: 6));
          Timer(const Duration(seconds: 6, milliseconds: 50), notifyListeners);
        case Signal.ping:
          if (roster[from]?.trusted == true && !invisible) {
            channel.send(seal(Signal.pong, from, id: id));
          }
        case Signal.pong:
          waiting.remove(id)?.complete();
        case Signal.mesh:
          await Mesh.instance.receive(from, channel, body);
        case Signal.listing:
          await Catalog.instance.receive(from, channel, body);
        case Signal.call:
          await Stage.instance.call(from, channel, body);
        case Signal.parcel:
          final data = jsonDecode(body) as Map;
          final to = data['to'];
          final inner = data['frame'];
          if (to is! String || inner is! Map<String, dynamic>) break;
          if (to == self!.address) {
            await unwrap(from, channel, inner);
          } else if (inner['to'] == to && Identity.valid(to)) {
            await carry(from, channel, to, inner);
          }
        case Signal.held:
          for (final entry in threads.entries) {
            if (entry.value.any((item) => item.id == id && item.mine)) {
              await upgrade(entry.key, id, Status.sent);
            }
          }
        case Signal.timer:
          final choice = jsonDecode(body) as Map;
          await adjust(from, choice['fuse'], choice['fused']);
        case Signal.session:
          final exchange = jsonDecode(body) as Map;
          await Ratchet.learn(from, exchange['bundle']);
          final opening = exchange['init'];
          if (opening is Map<String, dynamic>) {
            if (!Ratchet.lead(self!, from)) {
              try {
                await Ratchet.open(self!, from, opening);
              } catch (_) {}
            }
            settle(from);
          } else if (Ratchet.lead(self!, from)) {
            if (exchange['want'] == true ||
                !await Ratchet.paired(self!, from)) {
              await Ratchet.forget(self!, from);
              await open(from, channel);
            }
            settle(from);
          } else if (exchange['want'] == true) {
            channel.send(
              seal(
                Signal.session,
                from,
                body: jsonEncode({'bundle': await Ratchet.bundle(self!)}),
              ),
            );
          }
        case Signal.banner:
          final known = roster[from];
          if (known == null || known.blocked) break;
          final picture = (jsonDecode(body) as Map)['banner'];
          if (picture is! String) break;
          final bytes = picture.isEmpty ? null : base64.decode(picture);
          if ((bytes?.length ?? 0) > banner) break;
          known.banner = bytes;
          await Ledger.keep(known);
      }

      if (epoch != generation) return;
      if (!wasOnline && undelivered(from).isNotEmpty) unawaited(flush(from));
      notifyListeners();
    } catch (error) {
      developer.log(
        'Failed to process an inbound frame',
        name: 'Courier.receive',
        level: 900,
        error: error,
      );
    }
  }

  /// Timer seconds from a peer, kept within what this app allows.
  static int clamp(Object? value) =>
      value is int && value > 0 ? min(value, Fuse.ceiling) : 0;

  /// Adopts a trustee's disappearing message timer when theirs is newer.
  Future<void> adjust(String from, Object? fuse, Object? fused) async {
    final known = roster[from];
    if (known == null || !known.trusted || fused is! int) return;
    if (fused <= known.fused) return;
    known
      ..fuse = clamp(fuse)
      ..fused = fused;
    await Ledger.keep(known);
  }

  /// Sets the disappearing message timer for [peer] and tells them.
  Future<void> fuse(String peer, int seconds) async {
    final known = roster[peer];
    if (known == null) return;
    known
      ..fuse = clamp(seconds)
      ..fused = DateTime.now().millisecondsSinceEpoch;
    await Ledger.keep(known);
    notifyListeners();
    try {
      final channel = await dial(peer);
      channel.send(
        seal(
          Signal.timer,
          peer,
          body: jsonEncode({'fuse': known.fuse, 'fused': known.fused}),
        ),
      );
    } catch (_) {
      // They learn the timer from the next hello instead.
    }
  }

  /// Deletes every message whose timer has run out, on this phone.
  Future<void> expire() async {
    final now = DateTime.now();
    final spent = [
      for (final list in threads.values)
        for (final message in list)
          if (message.expiry?.isBefore(now) ?? false) message,
    ];
    for (final message in spent) {
      try {
        await erase(message);
      } catch (error) {
        developer.log(
          'Failed to delete an expired message',
          name: 'Courier.expire',
          level: 900,
          error: error,
        );
      }
    }
  }

  /// Meta that makes a new outgoing message disappear on schedule.
  Map<String, dynamic> timed(String peer) {
    final seconds = roster[peer]?.fuse ?? 0;
    return seconds > 0 ? {'fuse': seconds} : {};
  }

  /// Takes a text, card or invitation that reached this phone directly or
  /// through a trustee, and calls [answer] to acknowledge it.
  Future<void> incoming(
    String from,
    String id,
    DateTime stamp,
    String body, {
    required Channel channel,
    required void Function() answer,
    bool relayed = false,
  }) async {
    final epoch = generation;
    final now = DateTime.now();
    if (await Ledger.exists(id)) {
      answer();
      return;
    }
    final inner = await reveal(from, channel, body, repair: !relayed);
    if (inner == null) return;
    var kind = Kind.text;
    var words = inner;
    var meta = <String, dynamic>{};
    var fuse = 0;
    try {
      final envelope = jsonDecode(inner);
      if (envelope is Map<String, dynamic>) {
        kind = Kind.values.firstWhere(
          (item) => item.name == envelope['kind'],
          orElse: () => Kind.text,
        );
        words = envelope['text'] as String? ?? '';
        final extra = envelope['meta'];
        if (extra is Map<String, dynamic>) meta = extra;
        fuse = clamp(envelope['fuse']);
      }
    } catch (_) {}

    if (kind == Kind.invite) {
      final invitation = Mesh.valid(meta, from);
      if (invitation == null) return;
      meta = invitation;
      words = '';
    } else if (kind == Kind.card) {
      final address = '${meta['address'] ?? ''}'.toLowerCase();
      if (!Identity.valid(address)) return;
      meta = {'address': address, 'name': Profile.clip(meta['name'], 64)};
      words = '';
    } else if (kind != Kind.text || words.trim().isEmpty) {
      return;
    } else {
      meta = {};
    }
    if (words.length > limit || !await admit(from)) return;
    if (fuse > 0) meta['fuse'] = fuse;

    if (!await Ledger.exists(id)) {
      final message = Message(
        id: id,
        peer: from,
        mine: false,
        kind: kind,
        text: words,
        meta: meta,
        time: stamp.isAfter(now) ? now : stamp,
        status: Status.delivered,
      );
      if (!await Ledger.record(message) || epoch != generation) return;
      deliver(message);
    }
    answer();
  }

  /// A trustee handing over something that waited for this phone.
  Future<void> unwrap(
    String relay,
    Channel channel,
    Map<String, dynamic> frame,
  ) async {
    if (!authentic(frame)) return;
    final sender = frame['from'] as String;
    if (sender == relay || roster[sender]?.blocked == true) return;
    final id = frame['id'] as String;
    switch (frame['kind']) {
      case 'message':
        await incoming(
          sender,
          id,
          DateTime.fromMillisecondsSinceEpoch(frame['time'] as int),
          frame['body'] as String,
          channel: channel,
          relayed: true,
          answer: () => respond(
            sender,
            seal(Signal.receipt, sender, id: id),
            relay,
            channel,
          ),
        );
      case 'receipt':
        waiting.remove(id)?.complete();
        entrusted.remove(id);
        await upgrade(sender, id, Status.delivered);
    }
    notifyListeners();
  }

  /// Sends [frame] to [peer] directly when connected, otherwise back through
  /// the trustee that brought the message.
  void respond(
    String peer,
    Map<String, dynamic> frame,
    String relay,
    Channel via,
  ) {
    final direct = channels[peer];
    if (direct != null && direct.alive) {
      direct.send(frame);
      return;
    }
    via.send(
      seal(
        Signal.parcel,
        relay,
        body: jsonEncode({'to': peer, 'frame': frame}),
      ),
    );
  }

  /// Holds a sealed frame for [to] on behalf of [from]: for trustees when
  /// carrying is on, for anyone writing to the person this phone is a
  /// mailbox for, and replies heading back to a trustee.
  Future<void> carry(
    String from,
    Channel channel,
    String to,
    Map<String, dynamic> frame,
  ) async {
    final friend = roster[from]?.trusted == true;
    final allowed =
        (prefs.carry && (friend || roster[to]?.trusted == true)) ||
        (prefs.serve.isNotEmpty && prefs.serve == to);
    if (!allowed || roster[from]?.blocked == true) return;
    final id = frame['id'];
    if (id is! String) return;
    final kept = await Ledger.hold(
      id: id,
      sender: from,
      recipient: to,
      frame: jsonEncode(frame),
    );
    if (!kept) return;
    channel.send(seal(Signal.held, from, id: id));
    final open = channels[to];
    if (open != null && open.alive) unawaited(release(to, open));
  }

  /// Hands [to] everything this phone has been holding for them.
  Future<void> release(String to, Channel channel) async {
    final held = await Ledger.parcels(recipient: to);
    for (final parcel in held) {
      final frame =
          jsonDecode(parcel['frame'] as String) as Map<String, dynamic>;
      final sent = await channel.send(
        seal(Signal.parcel, to, body: jsonEncode({'to': to, 'frame': frame})),
      );
      if (sent) await Ledger.handed(parcel['id'] as String);
    }
  }

  /// Every couple of minutes per recipient, tries to reach people this phone
  /// is holding parcels for, and drops parcels older than [keep].
  Future<void> dispatch() async {
    if (self == null) return;
    try {
      await Ledger.discardParcels(DateTime.now().subtract(keep));
      final now = DateTime.now();
      final recipients = {
        for (final parcel in await Ledger.parcels())
          parcel['recipient'] as String,
      };
      for (final to in recipients) {
        final last = forwarded[to];
        if (last != null && now.difference(last) < const Duration(minutes: 2)) {
          continue;
        }
        forwarded[to] = now;
        unawaited(
          dial(to).then((channel) => release(to, channel)).catchError((_) {}),
        );
      }
    } catch (error) {
      developer.log(
        'Could not pass on held parcels yet',
        name: 'Courier.dispatch',
        level: 800,
        error: error,
      );
    }
  }

  /// Who should hold messages for [peer]: their mailbox first, then
  /// trustees who are online right now.
  List<String> relays(String peer) {
    final mailbox = roster[peer]?.mailbox ?? '';
    final mine = self?.address;
    return <String>[
      if (mailbox.isNotEmpty &&
          mailbox != mine &&
          roster[mailbox]?.blocked != true)
        mailbox,
      for (final trustee in roster.values)
        if (trustee.trusted &&
            trustee.address != peer &&
            trustee.address != mailbox &&
            online(trustee.address))
          trustee.address,
    ].take(2).toList();
  }

  /// Hands sealed copies of messages for [peer], who could not be reached,
  /// to trustees who will pass them on. Needs an end-to-end session already,
  /// since agreeing one takes both phones online.
  Future<void> entrust(String peer) async {
    final identity = self;
    if (identity == null) return;
    final pending = undelivered(peer)
        .where(
          (item) =>
              !item.attachment &&
              item.status == Status.sending &&
              !entrusted.contains(item.id),
        )
        .toList();
    if (pending.isEmpty) return;
    final carriers = relays(peer);
    if (carriers.isEmpty) return;
    for (final message in pending) {
      final Map<String, dynamic> sealed;
      try {
        sealed = await Ratchet.seal(
          identity,
          peer,
          utf8.encode(jsonEncode(envelope(message))),
        );
      } on Unpaired {
        return;
      }
      final frame = seal(
        Signal.message,
        peer,
        id: message.id,
        body: jsonEncode(sealed),
        time: message.time,
      );
      for (final relay in carriers) {
        try {
          final channel = await dial(relay);
          channel.send(
            seal(
              Signal.parcel,
              relay,
              body: jsonEncode({'to': peer, 'frame': frame}),
            ),
          );
        } catch (_) {}
      }
      entrusted.add(message.id);
    }
  }

  /// The inner, end-to-end encrypted part of a text, card or invitation.
  Map<String, dynamic> envelope(Message message) => {
    'kind': message.kind.name,
    'text': message.text,
    'meta': switch (message.kind) {
      Kind.card => {
        'address': message.meta['address'],
        'name': message.meta['name'],
      },
      Kind.invite => {
        for (final key in [
          'community',
          'name',
          'about',
          'key',
          'keys',
          'founder',
          'created',
          'group',
        ])
          key: message.meta[key],
      },
      _ => const <String, dynamic>{},
    },
    'fuse': message.fuse,
  };

  /// Acknowledges [id] after a short random pause.
  void acknowledge(Channel channel, String peer, String id) {
    unawaited(
      hesitate().then((_) {
        if (self == null) return;
        channel.send(seal(Signal.receipt, peer, id: id));
      }),
    );
  }

  Future<bool> admit(String from) async {
    final known = roster[from];
    if (known != null) return !known.blocked;
    if (!prefs.strangers) return false;
    final stranger = Trustee(address: from, trust: Trust.stranger);
    roster[from] = stranger;
    await Ledger.keep(stranger);
    return true;
  }

  void deliver(Message message) {
    insert(message);
    if (focus == message.peer) {
      unawaited(seen(message.peer));
    } else {
      arrivals.add(message);
    }
  }

  void insert(Message message) {
    final list = threads.putIfAbsent(message.peer, () => []);
    var index = list.length;
    while (index > 0 && list[index - 1].time.isAfter(message.time)) {
      index -= 1;
    }
    list.insert(index, message);
  }

  Future<void> upgrade(String peer, String id, Status status) async {
    final list = threads[peer];
    if (list == null) return;
    for (final message in list.reversed) {
      if (message.id != id) continue;
      if (!message.mine || message.status.index >= status.index) return;
      message.status = status;
      await Ledger.mark(id, status);
      notifyListeners();
      return;
    }
  }

  Future<void> send(String peer, String text) async {
    final body = text.trim();
    if (body.isEmpty || self == null) return;
    await promote(peer);

    for (var index = 0; index < body.length; index += limit) {
      await enqueue(
        Message(
          id: token(),
          peer: peer,
          mine: true,
          text: body.substring(index, min(index + limit, body.length)),
          time: DateTime.now(),
          meta: timed(peer),
        ),
      );
    }
    hinted.remove(peer);
    unawaited(flush(peer));
  }

  Future<void> attach(
    String peer,
    Uint8List bytes, {
    required Kind kind,
    required String name,
    String? mime,
    int width = 0,
    int height = 0,
    int duration = 0,
    Uint8List? thumb,
    String caption = '',
  }) async {
    if (self == null) return;
    if (bytes.length > Locker.ceiling) {
      throw const FormatException('Attachments are limited to 25 MB.');
    }
    await promote(peer);
    final id = token();
    final sealed = await Locker.store(id, bytes);
    await enqueue(
      Message(
        id: id,
        peer: peer,
        mine: true,
        kind: kind,
        text: caption.trim(),
        time: DateTime.now(),
        meta: {
          ...sealed,
          ...timed(peer),
          'name': name,
          'mime': mime ?? Locker.mime(name),
          'size': bytes.length,
          'width': width,
          'height': height,
          if (duration > 0) 'duration': duration,
          if (thumb != null && thumb.length <= Still.ceiling)
            'thumb': base64.encode(thumb),
        },
      ),
    );
    unawaited(flush(peer));
  }

  Future<void> share(String peer, Trustee card) async {
    if (self == null) return;
    await promote(peer);
    await enqueue(
      Message(
        id: token(),
        peer: peer,
        mine: true,
        kind: Kind.card,
        text: '',
        time: DateTime.now(),
        meta: {'address': card.address, 'name': card.label, ...timed(peer)},
      ),
    );
    unawaited(flush(peer));
  }

  Future<void> enqueue(Message message) async {
    insert(message);
    notifyListeners();
    await Ledger.record(message);
  }

  Future<void> promote(String peer) async {
    final known = roster[peer];
    if (known != null && known.stranger) await trust(peer, Trust.trustee);
  }

  List<Message> undelivered(String peer) {
    return (threads[peer] ?? const <Message>[])
        .where(
          (item) => item.mine && item.status.index < Status.delivered.index,
        )
        .toList();
  }

  Future<void> flush(String peer) async {
    if (!flushing.add(peer)) return;
    final epoch = generation;
    try {
      for (final message in undelivered(peer)) {
        if (epoch != generation) return;
        await hesitate();
        if (epoch != generation) return;
        final Channel channel;
        try {
          channel = await dial(peer);
        } catch (_) {
          // They are offline: trustees can carry it until they are back.
          await entrust(peer);
          rethrow;
        }
        final ack = Completer<void>();
        waiting[message.id] = ack;

        if (message.attachment) {
          final clear = await Locker.load(message);
          final key = Ratchet.random(32);
          final manifest = await whisper(
            peer,
            channel,
            utf8.encode(
              jsonEncode({
                'kind': message.kind.name,
                'text': message.text,
                'name': message.name,
                'mime': message.mime,
                'size': clear.length,
                'width': message.width,
                'height': message.height,
                'duration': message.duration.inMilliseconds,
                'thumb': ?message.meta['thumb'],
                'sha': hashing.sha256.convert(clear).toString(),
                'fuse': message.fuse,
                'key': base64.encode(key),
              }),
            ),
          );
          final opened = await channel.send(
            seal(
              Signal.file,
              peer,
              id: message.id,
              time: message.time,
              body: manifest,
            ),
          );
          if (!opened) throw const SocketException('Channel closed');

          var seq = 0;
          for (var offset = 0; offset < clear.length; offset += slice) {
            final end = min(offset + slice, clear.length);
            final written = await channel.send({
              'v': protocol,
              'kind': Signal.chunk.name,
              'id': message.id,
              'seq': seq,
              'data': base64.encode(
                await Ratchet.chunk(
                  key,
                  seq,
                  clear.sublist(offset, end),
                  width: slice,
                ),
              ),
            });
            if (!written) {
              throw const SocketException('Channel closed mid transfer');
            }
            seq += 1;
            progress[message.id] = end / clear.length;
            if (seq % 4 == 0 || end == clear.length) notifyListeners();
          }
        } else {
          final body = await whisper(
            peer,
            channel,
            utf8.encode(jsonEncode(envelope(message))),
          );
          final written = await channel.send(
            seal(
              Signal.message,
              peer,
              id: message.id,
              body: body,
              time: message.time,
            ),
          );
          if (!written) throw const SocketException('Channel closed');
        }
        await upgrade(peer, message.id, Status.sent);

        final patience = Duration(
          seconds: 30 + (message.attachment ? message.size ~/ 16384 : 0),
        );
        await ack.future.timeout(patience);
        progress.remove(message.id);
        await upgrade(peer, message.id, Status.delivered);
      }
    } catch (error) {
      developer.log(
        'Delivery to peer paused, will retry on the next heartbeat',
        name: 'Courier.flush',
        level: 800,
        error: error,
      );
    } finally {
      flushing.remove(peer);
    }
  }

  Future<int?> ping(String peer) async {
    final state = track(peer);
    state.probed = DateTime.now();
    final clock = Stopwatch()..start();
    final id = token();
    try {
      final channel = await dial(peer);
      final ack = Completer<void>();
      waiting[id] = ack;
      channel.send(seal(Signal.ping, peer, id: id));
      await ack.future.timeout(const Duration(seconds: 30));
      state.latency = clock.elapsedMilliseconds;
      state.seen = DateTime.now();
      notifyListeners();
      return state.latency;
    } catch (_) {
      waiting.remove(id);
      state.latency = null;
      notifyListeners();
      return null;
    }
  }

  void typing(String peer) {
    if (!prefs.typing || invisible || roster[peer]?.trusted != true) return;
    final channel = channels[peer];
    if (channel == null || !channel.alive || self == null) return;
    final last = hinted[peer];
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 3)) {
      return;
    }
    hinted[peer] = DateTime.now();
    channel.send(seal(Signal.typing, peer));
  }

  Future<void> seen(String peer) async {
    final fresh = (threads[peer] ?? const <Message>[])
        .where((item) => !item.mine && item.status != Status.read)
        .toList();
    if (fresh.isEmpty) return;
    for (final message in fresh) {
      message.status = Status.read;
    }
    notifyListeners();
    try {
      for (final message in fresh) {
        await Ledger.mark(message.id, Status.read);
      }
    } catch (error) {
      developer.log(
        'Failed to persist read state for conversation',
        name: 'Courier.seen',
        level: 900,
        error: error,
      );
      return;
    }
    if (!prefs.receipts || invisible || roster[peer]?.trusted != true) return;
    try {
      await hesitate();
      if (self == null) return;
      final channel = await dial(peer);
      channel.send(
        seal(Signal.read, peer, body: fresh.map((item) => item.id).join(',')),
      );
    } catch (_) {}
  }

  /// The banner frame body for this identity's profile.
  String cover() => jsonEncode({
    'banner': me.banner == null || me.banner!.length > banner
        ? ''
        : base64.encode(me.banner!),
  });

  Future<void> publish(Profile profile) async {
    profile.revision = DateTime.now().millisecondsSinceEpoch;
    me = profile;
    await Ledger.write('profile', profile.toJson());
    notifyListeners();
    final body = jsonEncode(profile.toJson(banner: false));
    final picture = cover();
    for (final entry in channels.entries.toList()) {
      if (!entry.value.alive || roster[entry.key]?.trusted != true) continue;
      entry.value.send(seal(Signal.profile, entry.key, body: body));
      entry.value.send(seal(Signal.banner, entry.key, body: picture));
    }
  }

  Future<void> configure(Preferences preferences) async {
    final relist = prefs.listed != preferences.listed;
    prefs = preferences;
    theme.value = preferences.theme;
    if (shielded.value != preferences.shield) {
      shielded.value = preferences.shield;
      unawaited(Shield.apply(preferences.shield));
    }
    await Ledger.write('preferences', preferences.toJson());
    notifyListeners();
    if (relist) unawaited(Catalog.instance.refresh());
  }

  Future<Trustee> add(String address, String nickname) async {
    final target = address.trim().toLowerCase();
    if (!Identity.valid(target)) {
      throw const FormatException('That is not a valid v3 onion address.');
    }
    if (target == self?.address) {
      throw const FormatException('That is your own discovery key.');
    }
    final trustee = roster[target] ?? Trustee(address: target);
    if (nickname.trim().isNotEmpty) trustee.nickname = nickname.trim();
    trustee
      ..trust = Trust.trustee
      ..archived = false;
    roster[target] = trustee;
    await Ledger.keep(trustee);
    notifyListeners();
    unawaited(ping(target));
    return trustee;
  }

  Future<void> trust(String peer, Trust level) async {
    final trustee = roster[peer];
    if (trustee == null) return;
    trustee.trust = level;
    await Ledger.keep(trustee);
    if (level == Trust.blocked) {
      final channel = channels.remove(peer);
      if (channel != null) drop(channel);
      presence.remove(peer);
    } else if (level == Trust.trustee) {
      final channel = channels[peer];
      if (channel != null && channel.alive) greet(peer, channel);
    }
    notifyListeners();
  }

  Future<void> amend(Trustee trustee) async {
    roster[trustee.address] = trustee;
    await Ledger.keep(trustee);
    notifyListeners();
  }

  Future<void> remove(String address) async {
    final history = threads.remove(address) ?? const <Message>[];
    roster.remove(address);
    presence.remove(address);
    final channel = channels.remove(address);
    if (channel != null) drop(channel);
    await Ledger.forget(address);
    for (final message in history.where((item) => item.attachment)) {
      await Locker.discard(message);
    }
    notifyListeners();
  }

  Future<void> clear(String address) async {
    final history = threads.remove(address) ?? const <Message>[];
    await Ledger.clear(address);
    for (final message in history.where((item) => item.attachment)) {
      await Locker.discard(message);
    }
    notifyListeners();
  }

  Future<void> erase(Message message) async {
    threads[message.peer]?.removeWhere((item) => item.id == message.id);
    await Ledger.erase(message.id);
    if (message.attachment) await Locker.discard(message);
    notifyListeners();
  }

  Message? last(String peer) {
    final list = threads[peer];
    return list == null || list.isEmpty ? null : list.last;
  }

  int unread(String peer) {
    return (threads[peer] ?? const <Message>[])
        .where((item) => !item.mine && item.status != Status.read)
        .length;
  }

  static String link(String address, String name) {
    return Uri(
      scheme: 'zephyron',
      host: 'trustee',
      path: '/$address',
      queryParameters: name.trim().isEmpty ? null : {'name': name.trim()},
    ).toString();
  }

  static ({String address, String name})? parse(String text) {
    final match = RegExp(r'[a-z2-7]{56}\.onion').firstMatch(text.toLowerCase());
    if (match == null) return null;
    var name = '';
    try {
      name = Uri.parse(text.trim()).queryParameters['name'] ?? '';
    } catch (_) {}
    return (address: match.group(0)!, name: name);
  }

  static List<String> safety(String alpha, String beta) {
    final keys = [Identity.key(alpha), Identity.key(beta)]
      ..sort((left, right) {
        for (var index = 0; index < left.length; index++) {
          final gap = left[index] - right[index];
          if (gap != 0) return gap;
        }
        return 0;
      });
    final digest = hashing.sha512.convert([
      ...utf8.encode('zephyron safety'),
      ...keys[0],
      ...keys[1],
    ]).bytes;
    return List.generate(6, (group) {
      var value = 0;
      for (var index = 0; index < 5; index++) {
        value = (value * 256 + digest[group * 5 + index]) % 100000;
      }
      return value.toString().padLeft(5, '0');
    });
  }

  static String token() {
    final random = Random.secure();
    return encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  static String encode(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List decode(String text) {
    if (text.length.isOdd) throw const FormatException('Odd length hex');
    final bytes = Uint8List(text.length ~/ 2);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = int.parse(
        text.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    return bytes;
  }
}
