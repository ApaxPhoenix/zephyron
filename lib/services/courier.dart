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
  static const String protocol = 'zephyron/1';
  static const Duration horizon = Duration(seconds: 90);

  final ValueNotifier<Reach> reach = ValueNotifier<Reach>(Reach.offline);
  final ValueNotifier<ThemeMode> theme = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );
  final StreamController<Message> arrivals =
      StreamController<Message>.broadcast();

  Identity? self;
  ed25519.PrivateKey? secret;
  ServerSocket? server;
  Timer? pulse;
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

      roster
        ..clear()
        ..addEntries(people.map((item) => MapEntry(item.address, item)));
      threads.clear();
      for (final message in history) {
        threads.putIfAbsent(message.peer, () => []).add(message);
      }
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
  }

  Future<void> stop() async {
    generation += 1;
    pulse?.cancel();
    pulse = null;

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
    for (final pending in waiting.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Courier stopped'));
      }
    }
    waiting.clear();
    roster.clear();
    threads.clear();
    presence.clear();
    reach.value = Reach.offline;
    theme.value = ThemeMode.system;
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
    channel.send(
      seal(Signal.hello, peer, body: jsonEncode({'revision': me.revision})),
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
        transfer.buffer.add(base64.decode(data));
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
            'name': transfer.name,
            'mime': transfer.mime,
            'size': transfer.size,
            'width': transfer.width,
            'height': transfer.height,
          },
        );
        if (!await Ledger.record(message)) return;
        deliver(message);
        channel.send(seal(Signal.receipt, transfer.peer, id: transfer.id));
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

      final id = decoded['id'] as String;
      final body = decoded['body'] as String;
      final stamp = DateTime.fromMillisecondsSinceEpoch(decoded['time'] as int);
      final signal = Signal.values.where(
        (item) => item.name == decoded['kind'],
      );
      if (signal.isEmpty) return;

      switch (signal.first) {
        case Signal.hello:
          final revision = (jsonDecode(body) as Map)['revision'];
          final known = roster[from];
          if (known != null && known.revision != revision) {
            channel.send(seal(Signal.whois, from));
          }
        case Signal.whois:
          if (roster[from]?.trusted == true) {
            channel.send(
              seal(Signal.profile, from, body: jsonEncode(me.toJson())),
            );
          }
        case Signal.profile:
          final known = roster[from];
          if (known == null || known.blocked) break;
          final profile = Profile.fromJson(
            Map<String, dynamic>.from(jsonDecode(body) as Map),
          );
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
          var kind = Kind.text;
          var words = body;
          var meta = <String, dynamic>{};
          try {
            final envelope = jsonDecode(body);
            if (envelope is Map<String, dynamic>) {
              kind = Kind.values.firstWhere(
                (item) => item.name == envelope['kind'],
                orElse: () => Kind.text,
              );
              words = envelope['text'] as String? ?? '';
              final extra = envelope['meta'];
              if (extra is Map<String, dynamic>) meta = extra;
            }
          } catch (_) {}

          if (kind == Kind.card) {
            final address = '${meta['address'] ?? ''}'.toLowerCase();
            if (!Identity.valid(address)) break;
            meta = {'address': address, 'name': Profile.clip(meta['name'], 64)};
            words = '';
          } else if (kind != Kind.text || words.trim().isEmpty) {
            break;
          } else {
            meta = {};
          }
          if (words.length > limit || !await admit(from)) break;

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
            if (!await Ledger.record(message) || epoch != generation) break;
            deliver(message);
          }
          channel.send(seal(Signal.receipt, from, id: id));
        case Signal.file:
          final data = Map<String, dynamic>.from(jsonDecode(body) as Map);
          final kind = Kind.values.firstWhere(
            (item) => item.name == data['kind'],
            orElse: () => Kind.text,
          );
          if (kind != Kind.image && kind != Kind.gif && kind != Kind.file) {
            break;
          }
          final size = data['size'];
          final sha = '${data['sha'] ?? ''}';
          if (size is! int || size <= 0 || size > Locker.ceiling) break;
          if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) break;
          if (!await admit(from)) break;

          if (await Ledger.exists(id)) {
            channel.send(seal(Signal.receipt, from, id: id));
            break;
          }
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
          'name': name,
          'mime': mime ?? Locker.mime(name),
          'size': bytes.length,
          'width': width,
          'height': height,
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
        meta: {'address': card.address, 'name': card.label},
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
        final channel = await dial(peer);
        final ack = Completer<void>();
        waiting[message.id] = ack;

        if (message.attachment) {
          final clear = await Locker.load(message);
          final opened = await channel.send(
            seal(
              Signal.file,
              peer,
              id: message.id,
              time: message.time,
              body: jsonEncode({
                'kind': message.kind.name,
                'text': message.text,
                'name': message.name,
                'mime': message.mime,
                'size': clear.length,
                'width': message.width,
                'height': message.height,
                'sha': hashing.sha256.convert(clear).toString(),
              }),
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
              'data': base64.encode(clear.sublist(offset, end)),
            });
            if (!written) {
              throw const SocketException('Channel closed mid transfer');
            }
            seq += 1;
            progress[message.id] = end / clear.length;
            if (seq % 4 == 0 || end == clear.length) notifyListeners();
          }
        } else {
          final written = await channel.send(
            seal(
              Signal.message,
              peer,
              id: message.id,
              body: jsonEncode({
                'kind': message.kind.name,
                'text': message.text,
                'meta': message.meta,
              }),
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
      final channel = await dial(peer);
      channel.send(
        seal(Signal.read, peer, body: fresh.map((item) => item.id).join(',')),
      );
    } catch (_) {}
  }

  Future<void> publish(Profile profile) async {
    profile.revision = DateTime.now().millisecondsSinceEpoch;
    me = profile;
    await Ledger.write('profile', profile.toJson());
    notifyListeners();
    final body = jsonEncode(profile.toJson());
    for (final entry in channels.entries.toList()) {
      if (!entry.value.alive || roster[entry.key]?.trusted != true) continue;
      entry.value.send(seal(Signal.profile, entry.key, body: body));
    }
  }

  Future<void> configure(Preferences preferences) async {
    prefs = preferences;
    theme.value = preferences.theme;
    await Ledger.write('preferences', preferences.toJson());
    notifyListeners();
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
