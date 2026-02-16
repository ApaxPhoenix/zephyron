import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;
import 'package:zephyron/models/identity.dart';

class Database {
  static cipher.Database? databaseInstance;

  /// Secure storage that never leaves this phone: the Android Keystore, or
  /// the iOS Keychain with no iCloud sync and no backups.
  static const FlutterSecureStorage keychain = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static String hash(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  static String slot(String name) => 'anchor:${hash(name)}';

  /// Mixes this phone's anchor into the passphrase. A store copied to another
  /// machine cannot be brute forced there, because the anchor never leaves
  /// the hardware-backed keychain.
  static String bind(String passphrase, List<int> anchor) =>
      Hmac(sha256, anchor).convert(utf8.encode(passphrase)).toString();

  static Future<({Uint8List value, bool bound})?> anchor(String name) async {
    final raw = await keychain.read(key: slot(name));
    if (raw == null || raw.isEmpty) return null;
    final data = Map<String, dynamic>.from(json.decode(raw) as Map);
    return (
      value: base64.decode(data['value'] as String),
      bound: data['bound'] as bool? ?? false,
    );
  }

  static Future<Uint8List> forge(String name, {required bool bound}) async {
    final random = Random.secure();
    final value = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await keychain.write(
      key: slot(name),
      value: json.encode({'value': base64.encode(value), 'bound': bound}),
    );
    return value;
  }

  static Future<void> settle(String name, Uint8List value) => keychain.write(
    key: slot(name),
    value: json.encode({'value': base64.encode(value), 'bound': true}),
  );

  static Future<Uint8List> salt(String path) async {
    try {
      final file = File('$path.salt');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      final random = Random.secure();
      final bytes = Uint8List.fromList(
        List<int>.generate(16, (_) => random.nextInt(256)),
      );
      await file.writeAsBytes(bytes, flush: true);
      return bytes;
    } catch (error) {
      developer.log(
        'Failed to read or generate encryption salt file at path: $path.salt',
        name: 'Database.salt',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<String> key(String passphrase, Uint8List bytes) async {
    try {
      final hasher = Argon2id(
        parallelism: 2,
        memory: 32768,
        iterations: 3,
        hashLength: 32,
      );

      final secret = await hasher.deriveKeyFromPassword(
        password: passphrase,
        nonce: bytes,
      );

      final array = Uint8List.fromList(await secret.extractBytes());
      final hexadecimal = array
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();

      array.fillRange(0, array.length, 0);

      return "x'$hexadecimal'";
    } catch (error) {
      developer.log(
        'Failed to derive database encryption key via Argon2id',
        name: 'Database.key',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<void> discard(String route) async {
    try {
      final database = File(route);
      if (await database.exists()) {
        await database.delete();
      }
      final companion = File('$route.salt');
      if (await companion.exists()) {
        await companion.delete();
      }
      developer.log(
        'Discarded stale database and salt files at route: $route',
        name: 'Database.discard',
        level: 500,
      );
    } catch (error) {
      developer.log(
        'Failed to discard stale database and salt files at route: $route',
        name: 'Database.discard',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  static Future<void> wipe(String name) async {
    try {
      await dispose();
      final folder = await cipher.getDatabasesPath();
      final digest = hash(name);
      final route = join(folder, '$digest.db');
      await discard(route);
      // Without its anchor the store is unreadable even if a copy survives.
      await keychain.delete(key: slot(name));
      developer.log(
        'Deleted local encrypted database for profile: $name',
        name: 'Database.wipe',
        level: 900,
      );
    } catch (error) {
      developer.log(
        'Failed to delete local encrypted database for profile: $name',
        name: 'Database.wipe',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<cipher.Database> open(String name, String passphrase) async {
    try {
      if (databaseInstance != null && databaseInstance!.isOpen) {
        await dispose();
      }

      final folder = await cipher.getDatabasesPath();
      await Directory(folder).create(recursive: true);

      final digest = hash(name);
      final route = join(folder, '$digest.db');
      final established = await File(route).exists();

      Future<void> onCreate(cipher.Database instance, int version) async {
        await instance.execute('''
          CREATE TABLE identity (
            identifier INTEGER PRIMARY KEY AUTOINCREMENT,
            address TEXT NOT NULL,
            seed TEXT NOT NULL,
            private TEXT NOT NULL,
            created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
        await instance.execute('''
          CREATE TABLE messages (
            identifier INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            text TEXT NOT NULL,
            time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      }

      Future<cipher.Database> unseal(String secret) async {
        final bytes = await salt(route);
        return cipher.openDatabase(
          route,
          password: await key(secret, bytes),
          version: 1,
          onCreate: onCreate,
        );
      }

      final held = await anchor(name);

      if (!established) {
        try {
          final fresh = await forge(name, bound: true);
          databaseInstance = await unseal(bind(passphrase, fresh));
        } catch (error) {
          developer.log(
            'Initial provisioning attempt failed for brand-new identity store, discarding partial artifacts and retrying once for profile: $name',
            name: 'Database.open',
            level: 900,
            error: error,
            stackTrace: StackTrace.current,
          );
          await discard(route);
          final fresh = await forge(name, bound: true);
          databaseInstance = await unseal(bind(passphrase, fresh));
        }
      } else if (held != null && held.bound) {
        databaseInstance = await unseal(bind(passphrase, held.value));
      } else {
        // A store from before device binding, or one whose migration was
        // interrupted. A pending anchor may already be in use, so it is
        // tried first; otherwise the legacy key opens it and the store is
        // rekeyed to one that needs this phone's anchor.
        if (held != null) {
          try {
            databaseInstance = await unseal(bind(passphrase, held.value));
            await settle(name, held.value);
          } catch (_) {
            databaseInstance = null;
          }
        }
        if (databaseInstance == null) {
          final legacy = await unseal(passphrase);
          final value = held?.value ?? (await forge(name, bound: false));
          final bytes = await salt(route);
          final bound = await key(bind(passphrase, value), bytes);
          await legacy.execute('PRAGMA rekey = "$bound"');
          await settle(name, value);
          databaseInstance = legacy;
          developer.log(
            'Rekeyed legacy identity store to a device-bound key for profile: $name',
            name: 'Database.open',
            level: 800,
          );
        }
      }

      developer.log(
        'SQLCipher database instance opened successfully for target profile: $name',
        name: 'Database.open',
        level: 800,
      );
      return databaseInstance!;
    } catch (error) {
      developer.log(
        'Failed to open or initialize SQLCipher encrypted database for profile: $name',
        name: 'Database.open',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<void> save(
    cipher.Database instance,
    Identity identity,
    String seed,
  ) async {
    try {
      await instance.insert('identity', {
        'address': identity.address,
        'seed': seed,
        'private': identity.private,
      }, conflictAlgorithm: cipher.ConflictAlgorithm.replace);
      developer.log(
        'Successfully persisted identity record into local database table',
        name: 'Database.save',
        level: 800,
      );
    } catch (error) {
      developer.log(
        'Failed to insert identity record into database table',
        name: 'Database.save',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> fetch(cipher.Database instance) async {
    try {
      final rows = await instance.query('identity', limit: 1);
      if (rows.isNotEmpty) return rows.first;
      return null;
    } catch (error) {
      developer.log(
        'Failed to execute fetch query for identity record from database',
        name: 'Database.fetch',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<void> dispose() async {
    try {
      if (databaseInstance != null) {
        await databaseInstance!.close();
        databaseInstance = null;
        developer.log(
          'Closed and cleared active SQLCipher database instance',
          name: 'Database.dispose',
          level: 500,
        );
      }
    } catch (error) {
      developer.log(
        'Failed to cleanly close SQLCipher database connection during dispose',
        name: 'Database.dispose',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }
}
