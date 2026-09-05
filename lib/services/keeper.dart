import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/sql/ledger.dart';

/// Keeps what arrives while the vault is locked.
///
/// The phone stays reachable after it locks, but the keys to read messages
/// are locked away. So each frame that arrives is sealed to a holding key
/// whose secret half lives inside the locked store, written to a file, and
/// opened at the next unlock. Until then nobody, this phone included, can
/// read who wrote or what they said.
class Keeper {
  static final Keeper instance = Keeper._();

  Keeper._();

  /// Most frames held at once, from any one sender, and the largest one.
  static const int limit = 500;
  static const int share = 100;
  static const int largest = 64 * 1024;

  /// The public half of the holding key, remembered while locked.
  SimplePublicKey? lock;

  /// Messages held since the vault locked, for the notification.
  int messages = 0;

  /// Whether this identity wanted notifications when it locked; its
  /// preferences are locked away with everything else.
  bool alerts = true;
  int count = 0;
  final Set<String> seen = {};
  final Map<String, int> senders = {};

  static Future<Directory> folder() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/held');
  }

  static Future<File> file(String address) async {
    final directory = await folder();
    final name = hashing.sha256.convert(utf8.encode(address)).toString();
    return File('${directory.path}/$name.held');
  }

  /// Makes sure the unlocked identity has a holding key, kept inside its
  /// encrypted store, and remembers the public half for when it locks.
  Future<void> prepare() async {
    var stored = await Ledger.read('holding');
    if (stored == null) {
      final pair = await X25519().newKeyPair();
      final public = await pair.extractPublicKey();
      stored = {
        'secret': base64.encode(await pair.extractPrivateKeyBytes()),
        'public': base64.encode(public.bytes),
      };
      await Ledger.write('holding', stored);
    }
    lock = SimplePublicKey(
      base64.decode(stored['public'] as String),
      type: KeyPairType.x25519,
    );
  }

  /// Starts counting afresh for a new locked stretch.
  void begin() {
    seen.clear();
    senders.clear();
    count = 0;
    messages = 0;
  }

  /// Seals [frame] for [address] to read later. Returns true once it is
  /// stored, null when it already was, and false when it is too large or
  /// there is no room left.
  Future<bool?> hold(String address, Map<String, dynamic> frame) async {
    final key = lock;
    final id = frame['id'];
    final from = frame['from'];
    if (key == null || id is! String || from is! String) return false;
    if (seen.contains(id)) return null;
    final text = jsonEncode(frame);
    if (text.length > largest) return false;
    if (count >= limit || (senders[from] ?? 0) >= share) return false;
    final sealed = await seal(key, utf8.encode(text));
    final target = await file(address);
    await target.parent.create(recursive: true);
    await target.writeAsString('$sealed\n', mode: FileMode.append, flush: true);
    seen.add(id);
    senders[from] = (senders[from] ?? 0) + 1;
    count += 1;
    if (frame['kind'] == 'message') messages += 1;
    return true;
  }

  static Future<String> seal(SimplePublicKey key, List<int> clear) async {
    final ephemeral = await X25519().newKeyPair();
    final public = await ephemeral.extractPublicKey();
    final shared = await X25519().sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: key,
    );
    final secret = await Ratchet.derive(
      await shared.extractBytes(),
      salt: public.bytes,
      info: 'zephyron/held',
    );
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: SecretKey(secret),
    );
    return jsonEncode({
      'e': base64.encode(public.bytes),
      'n': base64.encode(box.nonce),
      'd': base64.encode([...box.cipherText, ...box.mac.bytes]),
    });
  }

  static Future<List<int>?> open(SimpleKeyPair pair, String sealed) async {
    try {
      final data = jsonDecode(sealed) as Map;
      final ephemeral = SimplePublicKey(
        base64.decode(data['e'] as String),
        type: KeyPairType.x25519,
      );
      final shared = await X25519().sharedSecretKey(
        keyPair: pair,
        remotePublicKey: ephemeral,
      );
      final secret = await Ratchet.derive(
        await shared.extractBytes(),
        salt: ephemeral.bytes,
        info: 'zephyron/held',
      );
      final bytes = base64.decode(data['d'] as String);
      return await AesGcm.with256bits().decrypt(
        SecretBox(
          bytes.sublist(0, bytes.length - 16),
          nonce: base64.decode(data['n'] as String),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: SecretKey(secret),
      );
    } catch (_) {
      return null;
    }
  }

  /// Opens and removes everything held for [address]. Needs its store
  /// unlocked, since that is where the holding secret is.
  Future<List<Map<String, dynamic>>> release(String address) async {
    final target = await file(address);
    if (!await target.exists()) return const [];
    final stored = await Ledger.read('holding');
    final frames = <Map<String, dynamic>>[];
    if (stored != null) {
      final public = SimplePublicKey(
        base64.decode(stored['public'] as String),
        type: KeyPairType.x25519,
      );
      final pair = SimpleKeyPairData(
        base64.decode(stored['secret'] as String),
        publicKey: public,
        type: KeyPairType.x25519,
      );
      for (final line in await target.readAsLines()) {
        if (line.trim().isEmpty) continue;
        final clear = await open(pair, line);
        if (clear == null) continue;
        try {
          final frame = jsonDecode(utf8.decode(clear));
          if (frame is Map<String, dynamic>) frames.add(frame);
        } catch (_) {}
      }
    }
    await target.delete();
    return frames;
  }

  /// Removes everything held for every identity.
  static Future<void> wipe() async {
    final directory = await folder();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
