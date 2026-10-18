import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:zephyron/models/community.dart';
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

/// Live voice rooms over Tor.
///
/// Speech is captured at 8 kHz and compressed with µ-law, the telephone
/// network's codec, to about 8 KB a second. Every 200 ms of it is sealed
/// with a key derived from the community key and the room, signed like any
/// frame, and sent straight to everyone else in the room. Each speaker gets
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

  /// Who is in each room this phone knows about, by room id.
  final Map<String, Map<String, Seat>> rooms = {};

  String? community;
  String? room;
  bool muted = false;
  double level = 0;
  int sequence = 0;

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

  Map<String, Seat> seated(String id) => rooms.putIfAbsent(id, () => {});

  /// Everyone else in the room this phone has joined.
  List<String> get others {
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

  static List<int> label(String community, String room, String from, int seq) =>
      utf8.encode('voice:$community:$room:$from:$seq');

  /// Seals one packet of speech for everyone in [room].
  static Future<Map<String, dynamic>> pack(
    Community community,
    String room,
    String from,
    int seq,
    Int16List pcm,
  ) async {
    final nonce = Ratchet.random(12);
    final box = await AesGcm.with256bits().encrypt(
      compress(pcm),
      secretKey: SecretKey(await key(community, room)),
      nonce: nonce,
      aad: label(community.id, room, from, seq),
    );
    return {
      'op': 'voice',
      'c': community.id,
      'r': room,
      'q': seq,
      'n': base64.encode(nonce),
      'd': base64.encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  static Future<Int16List?> unpack(
    Community community,
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
        secretKey: SecretKey(await key(community, room)),
        aad: label(community.id, room, from, seq),
      );
      return expand(Uint8List.fromList(clear));
    } catch (_) {
      return null;
    }
  }

  // Joining and leaving.

  void announce(String state, {String? only}) {
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
    final group = mesh.communities[community];
    final here = room;
    final self = courier.self?.address;
    if (group == null || here == null || self == null) return;
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

  Future<void> receive(
    String from,
    Channel channel,
    Community group,
    Map<String, dynamic> data,
  ) async {
    final id = data['r'];
    if (id is! String || !mesh.member(group.id, from)) return;
    final now = DateTime.now();
    switch (data['op']) {
      case 'room':
        final state = data['state'];
        final chairs = seated(id);
        if (state == 'leave') {
          chairs.remove(from);
          buffers.remove(from);
        } else {
          final seat = chairs[from] ??= Seat(seen: now);
          seat
            ..seen = now
            ..muted = data['muted'] == true;
          if (state == 'join' && room == id) announce('here', only: from);
        }
        notifyListeners();
      case 'voice':
        if (room != id || group.id != community) return;
        final pcm = await unpack(group, from, data);
        if (pcm == null) return;
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
  }

  void reset() {
    pulse?.cancel();
    pulse = null;
    unawaited(close());
    rooms.clear();
    buffers.clear();
    started.clear();
    community = null;
    room = null;
  }
}
