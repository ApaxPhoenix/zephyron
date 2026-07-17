import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/services/sound.dart';

/// Someone in a voice room, as this phone last heard from them.
class Seat {
  DateTime seen;
  bool muted;
  double level = 0;

  Seat({required this.seen, this.muted = false});
}

/// A call ringing on this phone that nobody has answered yet.
class Ring {
  final String from;
  final String id;

  /// The key of a direct call, sent inside the end-to-end session.
  final Uint8List? secret;

  /// The group, for a group call.
  final String? community;
  final DateTime time;

  Ring({
    required this.from,
    required this.id,
    this.secret,
    this.community,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  bool get direct => community == null;
}

/// Live voice over Tor: rooms in communities, calls in groups, and direct
/// calls between two trustees.
///
/// Speech is captured at 8 kHz and compressed with µ-law, the telephone
/// network's codec, to about 8 KB a second. Every 200 ms of it is sealed
/// with a key derived from the community key and the room, or for a direct
/// call from a key sent inside the end-to-end session, signed like any
/// frame, and sent straight to everyone else on the call. Each speaker gets
/// a short buffer to smooth over Tor's jitter before the voices are mixed.
class Stage extends ChangeNotifier {
  static final Stage instance = Stage._();

  Stage._();

  static const int rate = 8000;

  /// Samples in one packet: 200 ms.
  static const int frame = 1600;

  /// Most people in one room, so Tor can carry everyone to everyone.
  static const int seats = 6;

  /// Packets buffered for a speaker before their voice starts playing.
  static const int cushion = 2;

  /// Most packets kept per speaker; older ones are dropped to stay current.
  static const int backlog = 8;

  /// Someone not heard from for this long has left.
  static const Duration linger = Duration(seconds: 30);

  /// How long a call rings before it counts as missed.
  static Duration patience = const Duration(seconds: 45);

  /// Who is in each room this phone knows about, by room id.
  final Map<String, Map<String, Seat>> rooms = {};

  String? community;
  String? room;
  bool muted = false;
  double level = 0;
  int sequence = 0;

  /// The trustee on the other end of a direct call; null in a room.
  String? peer;

  /// The key of the direct call under way.
  Uint8List? secret;

  /// Whether this phone placed the direct call under way.
  bool outgoing = false;

  /// When the direct call was placed or started ringing here.
  DateTime? began;

  /// When the other side picked up; null while it is still ringing.
  DateTime? connected;

  /// Why the last direct call ended, for the call screen.
  String? ended;

  /// A call ringing here that nobody has answered yet.
  Ring? ringing;
  Timer? bell;
  Timer? wait;

  AudioRecorder? recorder;
  StreamSubscription<Uint8List>? capture;
  final BytesBuilder pending = BytesBuilder(copy: false);
  final Map<String, Queue<Int16List>> buffers = {};
  final Set<String> started = {};
  Timer? pulse;
  Timer? speaker;
  bool sounding = false;

  Mesh get mesh => Mesh.instance;
  Courier get courier => Courier.instance;

  bool get joined => room != null;

  /// Whether the call under way is a direct one with [peer].
  bool get direct => peer != null;

  Map<String, Seat> seated(String id) => rooms.putIfAbsent(id, () => {});

  /// Everyone else on the call this phone has joined.
  List<String> get others {
    if (direct) return connected == null ? const [] : [peer!];
    final self = courier.self?.address;
    return [
      for (final entry in seated(room ?? '').entries)
        if (entry.key != self) entry.key,
    ];
  }

  // µ-law, as in ITU-T G.711.

  static int squeeze(int sample) {
    const bias = 0x84;
    const clip = 32635;
    var sign = 0;
    var value = sample;
    if (value < 0) {
      sign = 0x80;
      value = -value;
    }
    if (value > clip) value = clip;
    value += bias;
    var exponent = 7;
    for (var mask = 0x4000; (value & mask) == 0 && exponent > 0; mask >>= 1) {
      exponent -= 1;
    }
    final mantissa = (value >> (exponent + 3)) & 0x0F;
    return ~(sign | (exponent << 4) | mantissa) & 0xFF;
  }

  static int stretch(int byte) {
    final value = ~byte & 0xFF;
    final sign = value & 0x80;
    final exponent = (value >> 4) & 0x07;
    final mantissa = value & 0x0F;
    final magnitude = (((mantissa << 3) + 0x84) << exponent) - 0x84;
    return sign != 0 ? -magnitude : magnitude;
  }

  static Uint8List compress(Int16List pcm) =>
      Uint8List.fromList([for (final sample in pcm) squeeze(sample)]);

  static Int16List expand(Uint8List law) =>
      Int16List.fromList([for (final byte in law) stretch(byte)]);

  /// Loudness from 0 to 1, for the speaking ring.
  static double loudness(Int16List pcm) {
    if (pcm.isEmpty) return 0;
    var sum = 0.0;
    for (final sample in pcm) {
      sum += sample * sample;
    }
    final rms = sqrt(sum / pcm.length) / 32768;
    return (rms * 6).clamp(0.0, 1.0);
  }

  static Future<Uint8List> key(Community community, String room) =>
      Ratchet.derive(community.key, info: 'zephyron/voice:$room');

  /// The packet key of a direct call.
  static Future<Uint8List> line(Uint8List secret, String call) =>
      Ratchet.derive(secret, info: 'zephyron/call:$call');

  static List<int> label(String community, String room, String from, int seq) =>
      utf8.encode('voice:$community:$room:$from:$seq');

  /// Seals one packet of speech for everyone in [room].
  static Future<Map<String, dynamic>> pack(
    Community community,
    String room,
    String from,
    int seq,
    Int16List pcm,
  ) async => {
    ...await seal(
      await key(community, room),
      community.id,
      room,
      from,
      seq,
      pcm,
    ),
    'c': community.id,
  };

  static Future<Int16List?> unpack(
    Community community,
    String from,
    Map<String, dynamic> data,
  ) async {
    final room = data['r'];
    if (room is! String) return null;
    return unseal(await key(community, room), community.id, from, data);
  }

  /// Seals 200 ms of speech with [secret], bound to where it is said, who
  /// says it and its place in the stream.
  static Future<Map<String, dynamic>> seal(
    Uint8List secret,
    String scope,
    String room,
    String from,
    int seq,
    Int16List pcm,
  ) async {
    final nonce = Ratchet.random(12);
    final box = await AesGcm.with256bits().encrypt(
      compress(pcm),
      secretKey: SecretKey(secret),
      nonce: nonce,
      aad: label(scope, room, from, seq),
    );
    return {
      'op': 'voice',
      'r': room,
      'q': seq,
      'n': base64.encode(nonce),
      'd': base64.encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  static Future<Int16List?> unseal(
    Uint8List secret,
    String scope,
    String from,
    Map<String, dynamic> data,
  ) async {
    try {
      final room = data['r'] as String;
      final seq = data['q'] as int;
      final sealed = base64.decode(data['d'] as String);
      if (sealed.length < 16 || sealed.length > frame + 16) return null;
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          sealed.sublist(0, sealed.length - 16),
          nonce: base64.decode(data['n'] as String),
          mac: Mac(sealed.sublist(sealed.length - 16)),
        ),
        secretKey: SecretKey(secret),
        aad: label(scope, room, from, seq),
      );
      return expand(Uint8List.fromList(clear));
    } catch (_) {
      return null;
    }
  }

  // Joining and leaving.

  void announce(String state, {String? only}) {
    if (direct) {
      if (connected != null) {
        tell(peer!, {'op': 'here', 'r': room, 'muted': muted});
      }
      return;
    }
    final group = mesh.communities[community];
    final here = room;
    if (group == null || here == null) return;
    final self = courier.self?.address;
    final targets = only != null
        ? [only]
        : state == 'here'
        ? others
        : mesh
              .members(group.id)
              .map((item) => item.address)
              .where((address) => address != self)
              .where((address) => courier.roster[address]?.blocked != true)
              .take(24)
              .toList();
    for (final peer in targets) {
      unawaited(() async {
        try {
          final channel = await courier.dial(peer);
          mesh.send(channel, peer, {
            'op': 'room',
            'c': group.id,
            'r': here,
            'state': state,
            'muted': muted,
          });
        } catch (_) {}
      }());
    }
  }

  /// Takes a seat in [id] and starts talking and listening.
  Future<bool> join(Community group, String id) async {
    if (room == id) return true;
    if (joined) await leave();
    if (ringing?.id == id) silence();
    final self = courier.self?.address;
    final taken = seated(id).keys.where((address) => address != self).length;
    if (taken >= seats - 1) return false;

    community = group.id;
    room = id;
    muted = false;
    sequence = 0;
    if (self != null) seated(id)[self] = Seat(seen: DateTime.now());
    announce('join');
    pulse = Timer.periodic(const Duration(seconds: 10), (_) => tick());
    notifyListeners();
    await open();
    return true;
  }

  Future<void> leave() async {
    if (!joined) return;
    if (direct) return finish('ended');
    announce('leave');
    pulse?.cancel();
    pulse = null;
    await close();
    final self = courier.self?.address;
    if (self != null) rooms[room]?.remove(self);
    community = null;
    room = null;
    level = 0;
    buffers.clear();
    started.clear();
    notifyListeners();
  }

  void mute(bool value) {
    muted = value;
    final self = courier.self?.address;
    if (self != null) seated(room ?? '')[self]?.muted = value;
    announce('here');
    notifyListeners();
  }

  /// Keeps seats fresh and forgets people who went quiet.
  void tick() {
    final now = DateTime.now();
    final self = courier.self?.address;
    if (direct) {
      final other = seated(room!)[peer];
      if (connected != null &&
          other != null &&
          now.difference(other.seen) > linger) {
        unawaited(finish('dropped', quiet: true));
        return;
      }
      seated(room!)[self ?? '']?.seen = now;
      announce('here');
      notifyListeners();
      return;
    }
    for (final chairs in rooms.values) {
      chairs.removeWhere(
        (address, seat) =>
            address != self && now.difference(seat.seen) > linger,
      );
    }
    final mine = self == null ? null : seated(room ?? '')[self];
    mine?.seen = now;
    announce('here');
    notifyListeners();
  }

  // Direct calls.

  /// Sends [body] to [to] as part of a direct call, dialing if needed.
  void tell(String to, Map<String, dynamic> body) {
    void write(Channel channel) =>
        channel.send(courier.seal(Signal.call, to, body: jsonEncode(body)));
    final open = courier.channels[to];
    if (open != null && open.alive) {
      write(open);
      return;
    }
    unawaited(courier.dial(to).then(write).catchError((_) {}));
  }

  /// Rings [to], a trustee. The call key goes inside the end-to-end
  /// session, so only they can listen in.
  Future<bool> dial(String to) async {
    final self = courier.self?.address;
    if (self == null || courier.roster[to]?.trusted != true) return false;
    if (joined) await leave();
    final id = Courier.token();
    final key = Ratchet.random(32);
    community = null;
    room = id;
    peer = to;
    secret = key;
    outgoing = true;
    began = DateTime.now();
    connected = null;
    ended = null;
    muted = false;
    sequence = 0;
    seated(id)[self] = Seat(seen: DateTime.now());
    notifyListeners();
    try {
      final channel = await courier.dial(to);
      final sealed = await courier.whisper(
        to,
        channel,
        utf8.encode(jsonEncode({'call': id, 'key': base64.encode(key)})),
      );
      if (room != id) return false;
      channel.send(
        courier.seal(
          Signal.call,
          to,
          body: jsonEncode({'op': 'ring', 'r': id, 'k': sealed}),
        ),
      );
    } catch (error) {
      developer.log(
        'Could not ring a trustee',
        name: 'Stage.dial',
        level: 800,
        error: error,
      );
      if (room == id) await finish('unreachable', quiet: true);
      return false;
    }
    wait = Timer(patience, () {
      if (room == id && connected == null) unawaited(finish('unanswered'));
    });
    pulse = Timer.periodic(const Duration(seconds: 10), (_) => tick());
    return true;
  }

  /// Answers the call ringing here.
  Future<bool> pickUp() async {
    final call = ringing;
    if (call == null) return false;
    silence();
    if (!call.direct) {
      final group = mesh.communities[call.community];
      notifyListeners();
      return group != null && await join(group, call.id);
    }
    if (joined) await leave();
    final now = DateTime.now();
    final self = courier.self?.address;
    community = null;
    room = call.id;
    peer = call.from;
    secret = call.secret;
    outgoing = false;
    began = call.time;
    connected = now;
    ended = null;
    muted = false;
    sequence = 0;
    if (self != null) seated(call.id)[self] = Seat(seen: now);
    seated(call.id)[call.from] = Seat(seen: now);
    tell(call.from, {'op': 'answer', 'r': call.id});
    pulse = Timer.periodic(const Duration(seconds: 10), (_) => tick());
    notifyListeners();
    await open();
    return true;
  }

  /// Turns down the call ringing here.
  Future<void> decline() async {
    final call = ringing;
    if (call == null) return;
    silence();
    if (call.direct) {
      tell(call.from, {'op': 'hangup', 'r': call.id});
      await record(call.from, mine: false, at: call.time, missed: true);
    }
    notifyListeners();
  }

  /// Stops the ringing without answering.
  void silence() {
    ringing = null;
    bell?.cancel();
    bell = null;
  }

  /// Ends the direct call under way and notes it in the chat. [quiet] when
  /// the other side already knows.
  Future<void> finish(String reason, {bool quiet = false}) async {
    final to = peer;
    final id = room;
    if (to == null || id == null) return;
    if (!quiet) tell(to, {'op': 'hangup', 'r': id});
    wait?.cancel();
    wait = null;
    pulse?.cancel();
    pulse = null;
    final talked = connected == null
        ? null
        : DateTime.now().difference(connected!);
    final mine = outgoing;
    final at = began ?? DateTime.now();
    community = null;
    room = null;
    peer = null;
    secret = null;
    connected = null;
    began = null;
    outgoing = false;
    ended = reason;
    rooms.remove(id);
    level = 0;
    buffers.clear();
    started.clear();
    notifyListeners();
    await close();
    await record(
      to,
      mine: mine,
      at: at,
      talked: talked,
      missed: talked == null,
    );
  }

  /// Notes a call in the chat with [peer]. It stays on this phone.
  Future<void> record(
    String peer, {
    required bool mine,
    required DateTime at,
    Duration? talked,
    bool missed = false,
  }) async {
    try {
      await courier.enqueue(
        Message(
          id: Courier.token(),
          peer: peer,
          mine: mine,
          kind: Kind.call,
          text: '',
          time: at,
          // Never sent anywhere; a missed call waits to be seen.
          status: !mine && missed ? Status.delivered : Status.read,
          meta: {
            'duration': talked?.inMilliseconds ?? 0,
            if (missed) 'missed': true,
          },
        ),
      );
    } catch (error) {
      developer.log(
        'Could not note a call in the chat',
        name: 'Stage.record',
        level: 800,
        error: error,
      );
    }
  }

  // Audio.

  Future<void> open() async {
    try {
      sounding = await Sound.open(rate);
      speaker?.cancel();
      // Mix and hand over one packet every 200 ms; the platform buffer
      // smooths out small timing slips.
      speaker = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => feed(),
      );
    } catch (error) {
      developer.log(
        'Voice playback is unavailable on this device',
        name: 'Stage.open',
        level: 900,
        error: error,
      );
    }
    try {
      final made = AudioRecorder();
      if (!await made.hasPermission()) {
        await made.dispose();
        muted = true;
        notifyListeners();
        return;
      }
      final stream = await made.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: rate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
      );
      recorder = made;
      capture = stream.listen(spoken);
    } catch (error) {
      developer.log(
        'Voice capture is unavailable on this device',
        name: 'Stage.open',
        level: 900,
        error: error,
      );
      muted = true;
      notifyListeners();
    }
  }

  Future<void> close() async {
    await capture?.cancel();
    capture = null;
    try {
      await recorder?.stop();
      await recorder?.dispose();
    } catch (_) {}
    recorder = null;
    pending.clear();
    speaker?.cancel();
    speaker = null;
    if (sounding) {
      sounding = false;
      await Sound.close();
    }
  }

  /// Cuts captured audio into packets and sends them to the room.
  void spoken(Uint8List chunk) {
    pending.add(chunk);
    while (pending.length >= frame * 2) {
      final bytes = pending.takeBytes();
      final packet = Int16List.view(
        Uint8List.fromList(bytes.sublist(0, frame * 2)).buffer,
      );
      if (bytes.length > frame * 2) pending.add(bytes.sublist(frame * 2));
      level = loudness(packet);
      final self = courier.self?.address;
      if (self != null) seated(room ?? '')[self]?.level = muted ? 0 : level;
      if (!muted) unawaited(broadcast(packet));
    }
    notifyListeners();
  }

  Future<void> broadcast(Int16List packet) async {
    final here = room;
    final self = courier.self?.address;
    if (here == null || self == null) return;
    if (direct) {
      final to = peer!;
      final key = secret!;
      if (connected == null) return;
      final data = await seal(
        await line(key, here),
        'direct',
        here,
        self,
        sequence++,
        packet,
      );
      if (peer == to) tell(to, data);
      return;
    }
    final group = mesh.communities[community];
    if (group == null) return;
    final data = await pack(group, here, self, sequence++, packet);
    for (final peer in others.take(seats - 1)) {
      final channel = courier.channels[peer];
      if (channel != null && channel.alive) {
        mesh.send(channel, peer, data);
      } else {
        unawaited(
          courier
              .dial(peer)
              .then((open) => mesh.send(open, peer, data))
              .catchError((_) {}),
        );
      }
    }
  }

  /// Queues a packet of [from]'s speech in [id].
  void hear(String from, String id, Int16List pcm) {
    final now = DateTime.now();
    final seat = seated(id)[from] ??= Seat(seen: now);
    seat
      ..seen = now
      ..level = loudness(pcm);
    final queue = buffers.putIfAbsent(from, Queue.new);
    queue.add(pcm);
    while (queue.length > backlog) {
      queue.removeFirst();
    }
    notifyListeners();
  }

  /// Mixes one packet from every speaker who has enough buffered.
  Int16List mix() {
    final out = Int32List(frame);
    for (final entry in buffers.entries) {
      final queue = entry.value;
      if (!started.contains(entry.key)) {
        if (queue.length < cushion) continue;
        started.add(entry.key);
      }
      if (queue.isEmpty) {
        started.remove(entry.key);
        continue;
      }
      final packet = queue.removeFirst();
      for (var index = 0; index < frame && index < packet.length; index++) {
        out[index] += packet[index];
      }
    }
    return Int16List.fromList([
      for (final sample in out) sample.clamp(-32768, 32767),
    ]);
  }

  void feed() {
    if (!sounding) return;
    Sound.feed(mix());
  }

  // Network.

  /// Whether calls may ring this phone right now.
  bool get reachable => switch (courier.me.availability) {
    Availability.busy || Availability.invisible => false,
    _ => true,
  };

  Future<void> receive(
    String from,
    Channel channel,
    Community group,
    Map<String, dynamic> data,
  ) async {
    final id = data['r'];
    if (id is! String || !mesh.member(group.id, from)) return;
    final now = DateTime.now();
    final self = courier.self?.address;
    switch (data['op']) {
      case 'room':
        final state = data['state'];
        final chairs = seated(id);
        if (state == 'leave') {
          chairs.remove(from);
          buffers.remove(from);
          if (ringing?.id == id &&
              !chairs.keys.any((address) => address != self)) {
            silence();
          }
        } else {
          // The first person in a group's call rings everyone else.
          final first = !chairs.keys.any(
            (address) => address != self && address != from,
          );
          final seat = chairs[from] ??= Seat(seen: now);
          seat
            ..seen = now
            ..muted = data['muted'] == true;
          if (state == 'join' && room == id) announce('here', only: from);
          if (state == 'join' &&
              first &&
              group.group &&
              !group.muted &&
              id == group.general &&
              room != id &&
              ringing == null &&
              reachable) {
            ringing = Ring(from: from, id: id, community: group.id);
            bell?.cancel();
            bell = Timer(patience, () {
              if (ringing?.id != id) return;
              silence();
              notifyListeners();
            });
          }
        }
        notifyListeners();
      case 'voice':
        if (room != id || group.id != community) return;
        final pcm = await unpack(group, from, data);
        if (pcm == null) return;
        hear(from, id, pcm);
    }
  }

  /// Handles the frames of a direct call from [from].
  Future<void> call(String from, Channel channel, String body) async {
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) return;
    final id = data['r'];
    if (id is! String) return;
    final now = DateTime.now();
    switch (data['op']) {
      case 'ring':
        if (courier.roster[from]?.trusted != true) return;
        final sealed = data['k'];
        if (sealed is! String) return;
        final inner = await courier.reveal(from, channel, sealed);
        if (inner == null) return;
        final given = jsonDecode(inner) as Map;
        final key = base64.decode(given['key'] as String);
        if (key.length != 32 || given['call'] != id) return;
        if (joined || ringing != null || !reachable) {
          // Someone appearing offline does not give that away by replying.
          if (courier.me.availability != Availability.invisible) {
            channel.send(
              courier.seal(
                Signal.call,
                from,
                body: jsonEncode({'op': 'busy', 'r': id}),
              ),
            );
          }
          await record(from, mine: false, at: now, missed: true);
          return;
        }
        ringing = Ring(from: from, id: id, secret: key, time: now);
        bell?.cancel();
        bell = Timer(patience, () {
          if (ringing?.id != id) return;
          silence();
          unawaited(record(from, mine: false, at: now, missed: true));
          notifyListeners();
        });
        notifyListeners();
      case 'answer':
        if (from != peer || id != room || connected != null) return;
        wait?.cancel();
        wait = null;
        connected = now;
        seated(id)[from] = Seat(seen: now);
        notifyListeners();
        await open();
      case 'here':
        if (from != peer || id != room) return;
        final seat = seated(id)[from] ??= Seat(seen: now);
        seat
          ..seen = now
          ..muted = data['muted'] == true;
        notifyListeners();
      case 'busy':
        if (from == peer && id == room && connected == null) {
          await finish('busy', quiet: true);
        }
      case 'hangup':
        final call = ringing;
        if (call != null && call.id == id && call.from == from) {
          silence();
          await record(from, mine: false, at: call.time, missed: true);
          notifyListeners();
        } else if (from == peer && id == room) {
          await finish(connected == null ? 'declined' : 'ended', quiet: true);
        }
      case 'voice':
        final key = secret;
        if (from != peer || id != room || connected == null || key == null) {
          return;
        }
        final pcm = await unseal(await line(key, id), 'direct', from, data);
        if (pcm == null) return;
        hear(from, id, pcm);
    }
  }

  void reset() {
    pulse?.cancel();
    pulse = null;
    wait?.cancel();
    wait = null;
    silence();
    unawaited(close());
    rooms.clear();
    buffers.clear();
    started.clear();
    community = null;
    room = null;
    peer = null;
    secret = null;
    connected = null;
    began = null;
    ended = null;
    outgoing = false;
  }
}
