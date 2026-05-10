import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zephyron/sql/database.dart';
import 'package:zephyron/models/identity.dart';

class IdentityQuarantinedException implements Exception {
  final Duration remaining;

  IdentityQuarantinedException(this.remaining);

  @override
  String toString() =>
      'This identity is temporarily quarantined for ${remaining.inSeconds} more seconds after repeated failed unlock attempts.';
}

class IdentityAnnihilatedException implements Exception {
  final String name;

  IdentityAnnihilatedException(this.name);

  @override
  String toString() =>
      'Identity "$name" exceeded the maximum permitted unlock attempts and has been permanently erased from this device.';
}

class AttemptLedger {
  int strikes;
  List<DateTime> recentFailures;
  int quarantineCount;
  DateTime? quarantinedUntil;

  AttemptLedger({
    this.strikes = 0,
    List<DateTime>? recentFailures,
    this.quarantineCount = 0,
    this.quarantinedUntil,
  }) : recentFailures = recentFailures ?? <DateTime>[];

  factory AttemptLedger.fromJson(Map<String, dynamic> input) {
    return AttemptLedger(
      strikes: input['strikes'] as int? ?? 0,
      recentFailures: (input['recentFailures'] as List<dynamic>? ?? const [])
          .map((entry) => DateTime.parse(entry as String))
          .toList(),
      quarantineCount: input['quarantineCount'] as int? ?? 0,
      quarantinedUntil: input['quarantinedUntil'] != null
          ? DateTime.parse(input['quarantinedUntil'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'strikes': strikes,
      'recentFailures':
      recentFailures.map((moment) => moment.toIso8601String()).toList(),
      'quarantineCount': quarantineCount,
      'quarantinedUntil': quarantinedUntil?.toIso8601String(),
    };
  }
}

class Session {
  static const storage = FlutterSecureStorage();
  static const key = 'sessions';

  static const int throttleThreshold = 5;
  static const Duration throttleWindow = Duration(minutes: 15);
  static const int annihilationThreshold = 10;
  static const Duration baseQuarantineDuration = Duration(minutes: 1);
  static const Duration maximumQuarantineDuration = Duration(minutes: 60);

  static Identity? user;
  static Timer? timer;

  static bool get active => user != null;

  static String ledgerKey(String name) => 'ledger:${Database.hash(name)}';

  static Future<List<String>> sessions() async {
    try {
      final raw = await storage.read(key: key);
      if (raw == null || raw.isEmpty) return [];
      return List<String>.from(json.decode(raw) as List);
    } catch (error) {
      developer.log(
        'Failed to read enrolled identity roster from secure storage',
        name: 'Session.sessions',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      return [];
    }
  }

  static Future<void> enroll(String name) async {
    try {
      final items = await sessions();
      if (!items.contains(name)) {
        items.add(name);
        await storage.write(key: key, value: json.encode(items));
      }
    } catch (error) {
      developer.log(
        'Failed to enroll identity into roster in secure storage for profile: $name',
        name: 'Session.enroll',
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
      await storage.write(key: key, value: json.encode(items));
    } catch (error) {
      developer.log(
        'Failed to erase identity entry from roster in secure storage for profile: $name',
        name: 'Session.erase',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  static Future<AttemptLedger> ledger(String name) async {
    try {
      final raw = await storage.read(key: ledgerKey(name));
      if (raw == null || raw.isEmpty) return AttemptLedger();
      return AttemptLedger.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (error) {
      developer.log(
        'Failed to read failed-attempt ledger from secure storage for profile: $name',
        name: 'Session.ledger',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      return AttemptLedger();
    }
  }

  static Future<void> persist(String name, AttemptLedger record) async {
    try {
      await storage.write(
        key: ledgerKey(name),
        value: json.encode(record.toJson()),
      );
    } catch (error) {
      developer.log(
        'Failed to persist failed-attempt ledger to secure storage for profile: $name',
        name: 'Session.persist',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  static Future<void> forgive(String name) async {
    try {
      await storage.delete(key: ledgerKey(name));
      developer.log(
        'Cleared failed-attempt ledger after successful unlock for profile: $name',
        name: 'Session.forgive',
        level: 500,
      );
    } catch (error) {
      developer.log(
        'Failed to clear failed-attempt ledger for profile: $name',
        name: 'Session.forgive',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  static Future<Duration?> quarantineRemaining(String name) async {
    final record = await ledger(name);
    if (record.quarantinedUntil == null) return null;
    final remaining = record.quarantinedUntil!.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  static Future<int> remainingAttempts(String name) async {
    final record = await ledger(name);
    final remaining = annihilationThreshold - record.strikes;
    return remaining < 0 ? 0 : remaining;
  }

  static Future<void> annihilate(String name) async {
    try {
      await Database.wipe(name);
      await erase(name);
      await storage.delete(key: ledgerKey(name));
      developer.log(
        'Permanently annihilated identity and associated failed-attempt ledger for profile: $name',
        name: 'Session.annihilate',
        level: 1200,
      );
    } catch (error) {
      developer.log(
        'Failed to fully annihilate identity and ledger for profile: $name',
        name: 'Session.annihilate',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<Identity> open(String name, String pass) async {
    final record = await ledger(name);
    final now = DateTime.now();

    if (record.quarantinedUntil != null &&
        now.isBefore(record.quarantinedUntil!)) {
      final remaining = record.quarantinedUntil!.difference(now);
      developer.log(
        'Refused unlock attempt for profile: $name because it remains quarantined for ${remaining.inSeconds} more seconds',
        name: 'Session.open',
        level: 900,
      );
      throw IdentityQuarantinedException(remaining);
    }

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
      await forgive(name);
      await enroll(name);
      touch();
      developer.log(
        'User session opened and identity loaded successfully for profile: $name',
        name: 'Session.open',
        level: 800,
      );
      return user!;
    } catch (error) {
      if (error is IdentityQuarantinedException ||
          error is IdentityAnnihilatedException) {
        rethrow;
      }

      await Database.dispose();

      record.strikes += 1;
      record.recentFailures = [
        ...record.recentFailures.where(
              (moment) => now.difference(moment) <= throttleWindow,
        ),
        now,
      ];

      developer.log(
        'Failed to open and authenticate user session for profile: $name (strike ${record.strikes} of $annihilationThreshold)',
        name: 'Session.open',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );

      if (record.strikes >= annihilationThreshold) {
        developer.log(
          'Exceeded maximum lifetime unlock attempts for profile: $name, initiating permanent identity annihilation',
          name: 'Session.open',
          level: 1200,
          error: error,
          stackTrace: StackTrace.current,
        );
        await annihilate(name);
        throw IdentityAnnihilatedException(name);
      }

      if (record.recentFailures.length >= throttleThreshold) {
        record.quarantineCount += 1;
        final multiplier = math.pow(2, record.quarantineCount - 1).toInt();
        var duration = baseQuarantineDuration * multiplier;
        if (duration > maximumQuarantineDuration) {
          duration = maximumQuarantineDuration;
        }
        record.quarantinedUntil = now.add(duration);
        record.recentFailures = [];

        await persist(name, record);

        developer.log(
          'Too many failed unlock attempts within the throttle window for profile: $name, enforcing quarantine of ${duration.inSeconds} seconds',
          name: 'Session.open',
          level: 1000,
        );

        throw IdentityQuarantinedException(duration);
      }

      await persist(name, record);
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
      await enroll(name);
      await forgive(name);
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