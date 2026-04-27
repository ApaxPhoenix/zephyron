import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlite;
import 'package:zephyron/models/identity.dart';

class Database {
  static sqlite.Database? instance;

  static String hash(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  static Future<Uint8List> salt(String path) async {
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
  }

  static Future<String> key(String pass, Uint8List bytes) async {
    final hasher = Argon2id(
      parallelism: 2,
      memory: 32768,
      iterations: 3,
      hashLength: 32,
    );

    final secret = await hasher.deriveKeyFromPassword(
      password: pass,
      nonce: bytes,
    );

    final array = Uint8List.fromList(await secret.extractBytes());
    final hex = array.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    array.fillRange(0, array.length, 0);

    return "x'$hex'";
  }

  static Future<sqlite.Database> open(String name, String pass) async {
    try {
      if (instance != null && instance!.isOpen) {
        await dispose();
      }

      final folder = await sqlite.getDatabasesPath();
      final digest = hash(name);
      final route = join(folder, '$digest.db');

      final bytes = await salt(route);
      final raw = await key(pass, bytes);

      instance = await sqlite.openDatabase(
        route,
        password: raw,
        version: 1,
        onOpen: (base) async {
          await base.execute('PRAGMA cipher_memory_security = ON;');
        },
        onCreate: (base, version) async {
          await base.execute('''
            CREATE TABLE identity (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              address TEXT NOT NULL,
              seed TEXT NOT NULL,
              private TEXT NOT NULL,
              created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
          ''');
          await base.execute('''
            CREATE TABLE messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sender TEXT NOT NULL,
              text TEXT NOT NULL,
              time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        },
      );

      developer.log('Database opened successfully', level: 800);
      return instance!;
    } catch (error) {
      developer.log(
        'Failed to open database',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<void> save(
      sqlite.Database base,
      Identity identity,
      String seed,
      ) async {
    try {
      await base.insert('identity', {
        'address': identity.address,
        'seed': seed,
        'private': identity.private,
      }, conflictAlgorithm: sqlite.ConflictAlgorithm.replace);
      developer.log('Saved identity record to database', level: 800);
    } catch (error) {
      developer.log(
        'Failed to save identity record to database',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> fetch(sqlite.Database base) async {
    try {
      final rows = await base.query('identity', limit: 1);
      if (rows.isNotEmpty) return rows.first;
      return null;
    } catch (error) {
      developer.log(
        'Failed to fetch identity record from database',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<void> dispose() async {
    if (instance != null) {
      await instance!.close();
      instance = null;
      developer.log('Disposed database instance', level: 500);
    }
  }
}