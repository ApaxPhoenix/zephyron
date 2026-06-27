import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hashing;
import 'package:flutter/foundation.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/sql/ledger.dart';

/// Podcast episodes for community channels.
///
/// An episode's post carries its title, length and the audio's hash; the
/// audio itself is too large for a post, so members fetch it in encrypted
/// pieces from anyone who already has it, starting with whoever published
/// it. Every member who downloads an episode can serve it to the next.
class Broadcast extends ChangeNotifier {
  static final Broadcast instance = Broadcast._();

  Broadcast._();

  /// Largest episode, about two hours of speech.
  static const int ceiling = 50 * 1024 * 1024;

  /// Bytes in one piece, matching chat attachments.
  static const int piece = 48 * 1024;

  /// Pieces requested at once from one member, to hide Tor's latency.
  static const int window = 4;

  /// Episodes being downloaded, with how far along each is.
  final Map<String, double> progress = {};
  final Map<String, Completer<Map<String, dynamic>>> awaiting = {};

  Mesh get mesh => Mesh.instance;
  Courier get courier => Courier.instance;

  List<Post> episodes(String community, String channel) => [
    for (final post in mesh.posts[community] ?? const <Post>[])
      if (post.note == Note.episode &&
          post.channel == channel &&
          courier.roster[post.author]?.blocked != true)
        post,
  ].reversed.toList();

  static String blob(Post post) => post.meta['blob'] as String? ?? '';

  Future<bool> held(String blob) async =>
      await Ledger.read('blob:$blob') != null;

  Future<Uint8List> audio(String blob) async {
    final sealed = await Ledger.read('blob:$blob');
    if (sealed == null) throw StateError('Episode is not on this phone');
    return Locker.read(blob, sealed);
  }

  static Future<Uint8List> key(Community community, String blob) =>
      Ratchet.derive(community.key, info: 'zephyron/blob:$blob');

  /// Publishes an episode in [channel] and keeps its audio to serve.
  Future<Post> publish(
    Community community,
    String channel, {
    required Uint8List bytes,
    required String title,
    String about = '',
    Duration duration = Duration.zero,
    String mime = 'audio/mp4',
  }) async {
    if (bytes.length > ceiling) {
      throw const FormatException('Episodes are limited to 50 MB.');
    }
    final id = Courier.token();
    final sealed = await Locker.store(id, bytes);
    await Ledger.write('blob:$id', sealed);
    return mesh.post(
      community,
      channel: channel,
      note: Note.episode,
      text: Profile.clip(title, 120),
      meta: {
        'blob': id,
        'size': bytes.length,
        'sha': sealed['sha'],
        'duration': duration.inMilliseconds,
        'mime': mime,
        'about': Profile.clip(about, 1000),
      },
    );
  }

  /// Fetches [post]'s audio from members, trying the author first.
  Future<void> download(Community community, Post post) async {
    final id = blob(post);
    final size = post.meta['size'];
    final sha = post.meta['sha'];
    if (id.isEmpty || size is! int || size <= 0 || size > ceiling) return;
    if (sha is! String || progress.containsKey(id) || await held(id)) return;

    final total = (size + piece - 1) ~/ piece;
    final parts = List<Uint8List?>.filled(total, null);
    progress[id] = 0;
    notifyListeners();
    final self = courier.self?.address;
    final sources = [
      post.author,
      ...(mesh.members(community.id).map((item) => item.address).toList()
        ..shuffle()),
    ].where((address) => address != self).toSet().toList();

    try {
      for (final source in sources) {
        try {
          final channel = await courier.dial(source);
          var next = parts.indexWhere((part) => part == null);
          while (next != -1) {
            final batch = <int>[
              for (var seq = next; seq < total && seq < next + window; seq++)
                if (parts[seq] == null) seq,
            ];
            final replies = await Future.wait(
              batch.map((seq) => ask(community, channel, source, id, seq)),
            );
            final secret = await key(community, id);
            for (var index = 0; index < batch.length; index++) {
              final reply = replies[index];
              if (reply['missing'] == true) throw StateError('missing');
              final data = reply['d'];
              if (data is! String) throw StateError('malformed');
              parts[batch[index]] = await Ratchet.unchunk(
                secret,
                batch[index],
                base64.decode(data),
              );
            }
            progress[id] = parts.where((part) => part != null).length / total;
            notifyListeners();
            next = parts.indexWhere((part) => part == null);
          }
          break;
        } catch (error) {
          developer.log(
            'A member could not serve an episode piece, trying the next one',
            name: 'Broadcast.download',
            level: 800,
            error: error,
          );
        }
      }

      if (parts.any((part) => part == null)) return;
      final builder = BytesBuilder(copy: false);
      for (final part in parts) {
        builder.add(part!);
      }
      final bytes = builder.takeBytes();
      if (bytes.length != size ||
          hashing.sha256.convert(bytes).toString() != sha) {
        return;
      }
      final sealed = await Locker.store(id, bytes);
      await Ledger.write('blob:$id', sealed);
    } finally {
      progress.remove(id);
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> ask(
    Community community,
    Channel channel,
    String peer,
    String blob,
    int seq,
  ) {
    final slot = '$peer:$blob:$seq';
    final waiter = awaiting[slot] ??= Completer<Map<String, dynamic>>();
    mesh.send(channel, peer, {
      'op': 'fetch',
      'c': community.id,
      'b': blob,
      's': seq,
    });
    return waiter.future
        .timeout(const Duration(seconds: 45))
        .whenComplete(() => awaiting.remove(slot));
  }

  /// Answers mesh frames about episode audio.
  Future<void> receive(
    String from,
    Channel channel,
    Community community,
    Map<String, dynamic> data,
  ) async {
    final id = data['b'];
    final seq = data['s'];
    if (id is! String || seq is! int || seq < 0) return;
    switch (data['op']) {
      case 'fetch':
        if (!mesh.member(community.id, from)) return;
        final reply = <String, dynamic>{
          'op': 'piece',
          'c': community.id,
          'b': id,
          's': seq,
        };
        try {
          final bytes = await audio(id);
          final start = seq * piece;
          if (start >= bytes.length) throw RangeError('past the end');
          final slice = bytes.sublist(start, min(start + piece, bytes.length));
          reply['d'] = base64.encode(
            await Ratchet.chunk(
              await key(community, id),
              seq,
              slice,
              width: piece,
            ),
          );
        } catch (_) {
          reply['missing'] = true;
        }
        mesh.send(channel, from, reply);
      case 'piece':
        final waiter = awaiting.remove('$from:$id:$seq');
        if (waiter != null && !waiter.isCompleted) waiter.complete(data);
    }
  }
}
