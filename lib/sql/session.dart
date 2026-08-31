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
        'Failed to read active session entries from secure storage',
        name: 'Session.sessions',
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
        'Failed to record session entry in secure storage for profile: $name',
        name: 'Session.record',
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
        'Failed to erase session entry from secure storage for profile: $name',
        name: 'Session.erase',
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
        final exception = Exception('Database record missing.');
        developer.log(
          'Target session database record missing or null for profile: $name',
          name: 'Session.open',
          level: 900,
          error: exception,
          stackTrace: StackTrace.current,
        );
        throw exception;
      }

      user = Identity.fromInput(data['seed'] as String);
      await record(name);
      touch();
      developer.log(
        'User session opened and identity loaded successfully for profile: $name',
        name: 'Session.open',
        level: 800,
      );
      return user!;
    } catch (error) {
      developer.log(
        'Failed to open and authenticate user session for profile: $name',
        name: 'Session.open',
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
      developer.log(
        'New user session composed and persisted successfully for profile: $name',
        name: 'Session.compose',
        level: 800,
      );
      return user!;
    } catch (error) {
      developer.log(
        'Failed to compose new user session and database for profile: $name',
        name: 'Session.compose',
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
    try {
      timer?.cancel();
      timer = null;
      user = null;
      await Database.dispose();
      developer.log(
        'Disposed active session and wiped user identity credentials from memory',
        name: 'Session.dispose',
        level: 500,
      );
    } catch (error) {
      developer.log(
        'Failed to cleanly dispose user session context',
        name: 'Session.dispose',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }
}
