import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/models/message.dart';

class Locker {
  static const int ceiling = 25 * 1024 * 1024;
  static const int budget = 48 * 1024 * 1024;

  static final LinkedHashMap<String, Uint8List> cache = LinkedHashMap();
  static int cached = 0;

  static Future<Directory> folder() async {
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/vault');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static Future<Directory> outbox() async {
    final base = await getTemporaryDirectory();
    final directory = Directory('${base.path}/outbox');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static String slot(String id) =>
      '${hashing.sha256.convert(utf8.encode(id))}.bin';

  static Uint8List random(int length) {
    final source = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => source.nextInt(256)),
    );
  }

  static Future<Uint8List> encrypt(
    Uint8List clear,
    Uint8List key,
    Uint8List nonce,
  ) async {
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Uint8List> decrypt(
    Uint8List sealed,
    Uint8List key,
    Uint8List nonce,
  ) async {
    final split = sealed.length - 16;
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(
        sealed.sublist(0, split),
        nonce: nonce,
        mac: Mac(sealed.sublist(split)),
      ),
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList(clear);
  }

  static Future<Map<String, dynamic>> store(String id, Uint8List clear) async {
    final key = random(32);
    final nonce = random(12);
    final sealed = await Isolate.run(() => encrypt(clear, key, nonce));
    final directory = await folder();
    await File(
      '${directory.path}/${slot(id)}',
    ).writeAsBytes(sealed, flush: true);
    remember(id, clear);
    return {
      'key': base64.encode(key),
      'nonce': base64.encode(nonce),
      'sha': hashing.sha256.convert(clear).toString(),
    };
  }

  static Future<Uint8List> load(Message message) =>
      read(message.id, message.meta);

  /// Opens what [store] sealed under [id], with the keys it handed back.
  static Future<Uint8List> read(String id, Map<String, dynamic> meta) async {
    final hit = cache.remove(id);
    if (hit != null) {
      cache[id] = hit;
      return hit;
    }
    final key = base64.decode(meta['key'] as String);
    final nonce = base64.decode(meta['nonce'] as String);
    final directory = await folder();
    final sealed = await File('${directory.path}/${slot(id)}').readAsBytes();
    final clear = await Isolate.run(() => decrypt(sealed, key, nonce));
    remember(id, clear);
    return clear;
  }

  /// Writes [clear] somewhere other apps cannot see, for a player to open.
  static Future<File> stage(String id, String name, Uint8List clear) async {
    final directory = await outbox();
    final safe = name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    final file = File('${directory.path}/$id-$safe');
    if (!await file.exists()) await file.writeAsBytes(clear, flush: true);
    return file;
  }

  static void remember(String id, Uint8List clear) {
    if (clear.length > budget ~/ 4) return;
    cache[id] = clear;
    cached += clear.length;
    while (cached > budget && cache.isNotEmpty) {
      final oldest = cache.keys.first;
      cached -= cache.remove(oldest)!.length;
    }
  }

  static Future<void> discard(Message message) async {
    final hit = cache.remove(message.id);
    if (hit != null) cached -= hit.length;
    try {
      final directory = await folder();
      final file = File('${directory.path}/${slot(message.id)}');
      if (await file.exists()) await file.delete();
    } catch (error) {
      developer.log(
        'Failed to delete encrypted attachment from disk',
        name: 'Locker.discard',
        level: 900,
        error: error,
      );
    }
  }

  static Future<File> export(Message message) async {
    final clear = await load(message);
    final directory = await outbox();
    final safe = message.name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    final file = File('${directory.path}/$safe');
    await file.writeAsBytes(clear, flush: true);
    return file;
  }

  /// Deletes every sealed attachment that is not one of [ids].
  static Future<void> prune(Set<String> ids) async {
    final keep = ids.map(slot).toSet();
    final directory = await folder();
    await for (final entry in directory.list()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File && !keep.contains(name)) await entry.delete();
    }
    cache.clear();
    cached = 0;
  }

  static Future<void> sweep() async {
    cache.clear();
    cached = 0;
    try {
      final directory = await outbox();
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  static String mime(String name) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'pdf' => 'application/pdf',
      'zip' => 'application/zip',
      'txt' || 'md' => 'text/plain',
      'mp3' => 'audio/mpeg',
      'm4a' || 'aac' => 'audio/mp4',
      'ogg' || 'opus' => 'audio/ogg',
      'wav' => 'audio/wav',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      '3gp' => 'video/3gpp',
      'doc' || 'docx' => 'application/msword',
      _ => 'application/octet-stream',
    };
  }
}
