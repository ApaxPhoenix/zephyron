import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zephyron/sql/database.dart';
import 'package:zephyron/models/identity.dart';

class Session {
  static const storage = FlutterSecureStorage();
  static const label = 'sessions';

  static Identity? user;
  static Timer? timer;

  static bool get active => user != null;

  static Future<List<String>> sessions() async {
    try {
      final raw = await storage.read(key: label);
      if (raw == null || raw.isEmpty) return [];
      return List<String>.from(json.decode(raw) as List);
    } catch (error) {
      developer.log(
        'Failed to read sessions from secure storage',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      return [];
    }
  }

  static Future<void> record(String name) async {
    try {
      final items = await sessions();
      if (!items.contains(name)) {
        items.add(name);
        await storage.write(key: label, value: json.encode(items));
      }
    } catch (error) {
      developer.log(
        'Failed to record session in secure storage',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  static Future<void> erase(String name) async {
    try {
      final items = await sessions();
      items.remove(name);
      await storage.write(key: label, value: json.encode(items));
    } catch (error) {
      developer.log(
        'Failed to erase session from secure storage',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  static Future<Identity> open(String name, String pass) async {
    try {
      final base = await Database.open(name, pass);
      final data = await Database.fetch(base);

      if (data == null) {
        await Database.dispose();
        developer.log(
          'Database record missing during session open',
          level: 900,
        );
        throw Exception('Database record missing.');
      }

      user = Identity.fromInput(data['seed'] as String);
      await record(name);
      touch();
      developer.log('Session opened successfully', level: 800);
      return user!;
    } catch (error) {
      developer.log(
        'Failed to open session',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<Identity> compose(
      String name,
      String pass,
      Identity identity,
      String seed,
      ) async {
    try {
      final base = await Database.open(name, pass);
      await Database.save(base, identity, seed);
      await record(name);
      user = identity;
      touch();
      developer.log('Session composed successfully', level: 800);
      return user!;
    } catch (error) {
      developer.log(
        'Failed to compose session',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static void touch() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), () => dispose());
  }

  static Future<void> dispose() async {
    timer?.cancel();
    timer = null;
    user = null;
    await Database.dispose();
    developer.log('Disposed session instance', level: 500);
  }
}