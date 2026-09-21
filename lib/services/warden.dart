import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What the warden decided after a failed unlock.
enum Verdict {
  /// Keep going; only the per-identity rules apply.
  allow,

  /// Every identity on this device is locked for a while.
  lockout,

  /// The pattern looks like an attack: erase every identity.
  purge,
}

/// One failed unlock, as remembered across restarts.
class Strike {
  final DateTime at;

  /// A short hash of the identity name, never the name itself.
  final String who;

  /// How suspicious this attempt looked.
  final int weight;

  const Strike({required this.at, required this.who, required this.weight});

  factory Strike.fromJson(Map<String, dynamic> input) {
    return Strike(
      at: DateTime.parse(input['at'] as String),
      who: input['who'] as String? ?? '',
      weight: input['weight'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'who': who,
    'weight': weight,
  };
}

/// Device-wide guard over every identity's unlock screen.
///
/// The per-identity ledger in Session stops someone hammering one account.
/// The warden watches all of them together, so rotating between accounts,
/// trying one passphrase against several, scripting attempts, or winding the
/// clock back to escape a lockout all raise suspicion. Past a limit every
/// identity on the phone is erased.
///
/// Guesses are fingerprinted with a key that lives only in memory, so nothing
/// derived from a wrong passphrase ever reaches disk. A guess that shares most
/// of its characters with the previous one looks like a typo being fixed; a
/// completely different guess looks like a dictionary.
class Warden {
  static FlutterSecureStorage storage = const FlutterSecureStorage();
  static const key = 'warden';

  /// Failures across all identities inside [burst] that lock the device.
  static const int lockout = 6;
  static const Duration burst = Duration(minutes: 15);
  static const Duration baseLockout = Duration(minutes: 1);
  static const Duration maximumLockout = Duration(hours: 2);

  /// Weighted suspicion inside [window] that erases every identity.
  static const int purge = 24;
  static const Duration window = Duration(hours: 6);

  /// Rotation only counts when the previous failure was this recent.
  static const Duration rotation = Duration(minutes: 10);

  /// Nobody types a passphrase and waits for Argon2id faster than this.
  static const Duration reflex = Duration(seconds: 2);

  /// Guesses that share less than this much look unrelated.
  static const double kinship = 0.4;

  /// A clock this far behind the last attempt has been wound back.
  static const Duration drift = Duration(minutes: 2);

  static DateTime Function() clock = DateTime.now;

  static Uint8List pepper = fresh();
  static Set<String>? previous;
  static final Map<String, Set<String>> sprayed = {};

  static Uint8List fresh() {
    final source = math.Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => source.nextInt(256)),
    );
  }

  static String tag(String name) =>
      sha256.convert(utf8.encode('warden:$name')).toString().substring(0, 16);

  /// Keyed hash of a whole guess, used to spot one passphrase tried on many
  /// identities.
  static String stamp(String guess) =>
      Hmac(sha256, pepper).convert(utf8.encode(guess)).toString();

  /// Keyed hashes of every pair of neighbouring characters in a guess.
  static Set<String> shingles(String guess) {
    final mac = Hmac(sha256, pepper);
    final text = guess.trim();
    if (text.length < 2) return {mac.convert(utf8.encode(text)).toString()};
    return {
      for (var index = 0; index < text.length - 1; index++)
        mac.convert(utf8.encode(text.substring(index, index + 2))).toString(),
    };
  }

  /// Share of character pairs two guesses have in common, from 0 to 1.
  static double likeness(Set<String> alpha, Set<String> beta) {
    final union = alpha.union(beta).length;
    if (union == 0) return 1;
    return alpha.intersection(beta).length / union;
  }

  static Future<Map<String, dynamic>> load() async {
    try {
      final raw = await storage.read(key: key);
      if (raw == null || raw.isEmpty) return {};
      return json.decode(raw) as Map<String, dynamic>;
    } catch (error) {
      developer.log(
        'Failed to read device-wide unlock ledger from secure storage',
        name: 'Warden.load',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      return {};
    }
  }

  static Future<void> save(Map<String, dynamic> state) async {
    try {
      await storage.write(key: key, value: json.encode(state));
    } catch (error) {
      developer.log(
        'Failed to persist device-wide unlock ledger to secure storage',
        name: 'Warden.save',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  static List<Strike> strikes(Map<String, dynamic> state) {
    return (state['strikes'] as List<dynamic>? ?? const [])
        .map((entry) => Strike.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  /// How long every identity stays locked, or null when the device is open.
  static Future<Duration?> remaining() async {
    final state = await load();
    final until = state['until'] as String?;
    if (until == null) return null;
    final left = DateTime.parse(until).difference(clock());
    return left.isNegative ? null : left;
  }

  /// Weighted suspicion currently held against this device.
  static Future<int> suspicion() async {
    final now = clock();
    return strikes(await load())
        .where((strike) => now.difference(strike.at) <= window)
        .fold<int>(0, (total, strike) => total + strike.weight);
  }

  /// Records a failed unlock for [name] with the passphrase that was tried.
  static Future<Verdict> record(String name, String guess) async {
    final now = clock();
    final state = await load();
    final history = strikes(state);
    final who = tag(name);
    final latest = state['latest'] != null
        ? DateTime.parse(state['latest'] as String)
        : null;
    final last = history.isNotEmpty ? history.last : null;

    final signals = <String>[];
    var weight = 1;

    final shape = shingles(guess);
    if (previous != null && likeness(previous!, shape) < kinship) {
      weight += 1;
      signals.add('unrelated guess');
    } else if (previous == null &&
        last != null &&
        now.difference(last.at).abs() <= rotation) {
      // Memory is empty but a failure just happened: the app was restarted
      // between attempts, which is how you would dodge the checks above.
      weight += 1;
      signals.add('restarted between attempts');
    }
    previous = shape;

    final fingerprint = stamp(guess);
    final targets = sprayed.putIfAbsent(fingerprint, () => {});
    if (targets.isNotEmpty && !targets.contains(who)) {
      weight += 3;
      signals.add('same passphrase on another identity');
    }
    targets.add(who);

    if (last != null &&
        last.who != who &&
        now.difference(last.at).abs() <= rotation) {
      weight += 1;
      signals.add('switched identity');
    }

    if (last != null &&
        now.difference(last.at) < reflex &&
        !now.isBefore(last.at)) {
      weight += 2;
      signals.add('faster than a person');
    }

    if (latest != null && now.isBefore(latest.subtract(drift))) {
      weight += 8;
      signals.add('clock wound back');
    }

    history.add(Strike(at: now, who: who, weight: weight));
    final kept = history
        .where((strike) => now.difference(strike.at).abs() <= window)
        .toList();
    final score = kept.fold<int>(0, (total, strike) => total + strike.weight);

    state['strikes'] = kept.map((strike) => strike.toJson()).toList();
    state['latest'] = (latest != null && latest.isAfter(now) ? latest : now)
        .toIso8601String();

    developer.log(
      'Failed unlock weighed $weight (${signals.isEmpty ? 'no signals' : signals.join(', ')}); device suspicion now $score of $purge',
      name: 'Warden.record',
      level: 900,
    );

    if (score >= purge) {
      await save(state);
      return Verdict.purge;
    }

    final recent = kept
        .where((strike) => now.difference(strike.at).abs() <= burst)
        .length;
    if (recent >= lockout) {
      final count = (state['lockouts'] as int? ?? 0) + 1;
      var duration = baseLockout * math.pow(2, count - 1).toInt();
      if (duration > maximumLockout) duration = maximumLockout;
      state['lockouts'] = count;
      state['until'] = now.add(duration).toIso8601String();
      await save(state);
      developer.log(
        'Locked every identity on this device for ${duration.inSeconds} seconds after $recent failures across identities',
        name: 'Warden.record',
        level: 1000,
      );
      return Verdict.lockout;
    }

    await save(state);
    return Verdict.allow;
  }

  /// A correct passphrase for [name] clears that identity's strikes, but not
  /// the ones against other identities, so knowing one account's passphrase
  /// never helps attack the rest.
  static Future<void> absolve(String name) async {
    final state = await load();
    final who = tag(name);
    final kept = strikes(state).where((strike) => strike.who != who).toList();
    state['strikes'] = kept.map((strike) => strike.toJson()).toList();
    if (kept.isEmpty) {
      state.remove('lockouts');
      state.remove('until');
    }
    previous = null;
    for (final targets in sprayed.values) {
      targets.remove(who);
    }
    sprayed.removeWhere((_, targets) => targets.isEmpty);
    await save(state);
  }

  static void forget() {
    previous = null;
    sprayed.clear();
    pepper = fresh();
  }
}
