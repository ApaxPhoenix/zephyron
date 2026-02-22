import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/sql/database.dart';

/// A decoy identity and the passphrase that opens it under coercion.
///
/// Typing the duress passphrase on the unlock screen erases every other
/// identity and opens the decoy as if nothing happened. The decoy's own
/// passphrase is kept sealed under the duress passphrase, so the record is
/// useless without it.
class Duress {
  static FlutterSecureStorage storage = Database.keychain;
  static const key = 'duress';

  static Future<Uint8List> stretch(String passphrase, List<int> salt) async {
    final secret = await Argon2id(
      parallelism: 2,
      memory: 32768,
      iterations: 3,
      hashLength: 32,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
    return Uint8List.fromList(await secret.extractBytes());
  }

  static Future<bool> armed() async =>
      (await storage.read(key: key))?.isNotEmpty ?? false;

  /// Which identity the duress passphrase opens, or null when it is off.
  static Future<String?> decoy() async {
    try {
      final raw = await storage.read(key: key);
      if (raw == null || raw.isEmpty) return null;
      return (json.decode(raw) as Map)['decoy'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Makes [duress] open [name], whose own passphrase is [passphrase].
  static Future<void> arm(String name, String passphrase, String duress) async {
    final salt = Locker.random(16);
    final nonce = Locker.random(12);
    final sealed = await Locker.encrypt(
      Uint8List.fromList(utf8.encode(passphrase)),
      await stretch(duress, salt),
      nonce,
    );
    await storage.write(
      key: key,
      value: json.encode({
        'decoy': name,
        'salt': base64.encode(salt),
        'nonce': base64.encode(nonce),
        'sealed': base64.encode(sealed),
      }),
    );
    developer.log(
      'Armed a duress passphrase for a decoy identity',
      name: 'Duress.arm',
      level: 800,
    );
  }

  static Future<void> disarm() => storage.delete(key: key);

  /// The decoy and its passphrase when [guess] is the duress passphrase.
  ///
  /// The stretch runs even when no duress passphrase is set, so how long an
  /// unlock takes never reveals whether one exists.
  static Future<({String name, String passphrase})?> match(String guess) async {
    Map<String, dynamic>? record;
    try {
      final raw = await storage.read(key: key);
      if (raw != null && raw.isNotEmpty) {
        record = Map<String, dynamic>.from(json.decode(raw) as Map);
      }
    } catch (_) {}

    final salt = record == null
        ? Locker.random(16)
        : base64.decode(record['salt'] as String);
    final stretched = await stretch(guess, salt);
    if (record == null) return null;

    try {
      final clear = await Locker.decrypt(
        base64.decode(record['sealed'] as String),
        stretched,
        base64.decode(record['nonce'] as String),
      );
      return (name: record['decoy'] as String, passphrase: utf8.decode(clear));
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}
