import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef Pairing = Int32 Function(Pointer<Uint8>, Pointer<Uint8>);
typedef Paired = int Function(Pointer<Uint8>, Pointer<Uint8>);
typedef Sealing =
    Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef Sealed = int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

/// ML-KEM-768, the post-quantum key exchange NIST standardised in FIPS 203,
/// from the bundled liboqs (built from the official Open Quantum Safe
/// source, ML-KEM-768 only, no OpenSSL), the same way libtor is bundled.
///
/// Where the library is missing, such as on iOS until it is built there,
/// [available] is false and sessions fall back to classical X25519 alone.
class Kem {
  static const int publics = 1184;
  static const int secrets = 2400;
  static const int ciphers = 1088;
  static const int shared = 32;

  /// A different file to load, for tests on a desktop.
  static String? path = Platform.environment['ZEPHYRON_OQS'];

  static DynamicLibrary? loaded;
  static bool tried = false;

  static DynamicLibrary? get library {
    if (tried) return loaded;
    tried = true;
    final name =
        path ??
        (Platform.isWindows
            ? 'liboqs.dll'
            : Platform.isMacOS || Platform.isIOS
            ? 'liboqs.dylib'
            : 'liboqs.so');
    try {
      loaded = DynamicLibrary.open(name);
    } catch (error) {
      developer.log(
        'liboqs is not available here; sessions stay classical',
        name: 'Kem.library',
        level: 800,
        error: error,
      );
    }
    return loaded;
  }

  static bool get available => library != null;

  static Paired get keypair =>
      library!.lookupFunction<Pairing, Paired>('OQS_KEM_ml_kem_768_keypair');

  static Sealed get encaps =>
      library!.lookupFunction<Sealing, Sealed>('OQS_KEM_ml_kem_768_encaps');

  static Sealed get decaps =>
      library!.lookupFunction<Sealing, Sealed>('OQS_KEM_ml_kem_768_decaps');

  /// Copies [count] bytes out of native memory, then wipes and frees it.
  static Uint8List take(Pointer<Uint8> memory, int count) {
    final copy = Uint8List.fromList(memory.asTypedList(count));
    memory.asTypedList(count).fillRange(0, count, 0);
    calloc.free(memory);
    return copy;
  }

  static Pointer<Uint8> give(Uint8List bytes) {
    final memory = calloc<Uint8>(bytes.length);
    memory.asTypedList(bytes.length).setAll(0, bytes);
    return memory;
  }

  /// A fresh key pair.
  static ({Uint8List public, Uint8List secret}) pair() {
    final public = calloc<Uint8>(publics);
    final secret = calloc<Uint8>(secrets);
    final status = keypair(public, secret);
    final result = (
      public: take(public, publics),
      secret: take(secret, secrets),
    );
    if (status != 0) throw StateError('ML-KEM key generation failed');
    return result;
  }

  /// A shared secret for whoever holds the secret half of [public], and the
  /// ciphertext that lets them recover it.
  static ({Uint8List cipher, Uint8List secret}) seal(Uint8List public) {
    if (public.length != publics) throw ArgumentError('Wrong ML-KEM key size');
    final key = give(public);
    final cipher = calloc<Uint8>(ciphers);
    final secret = calloc<Uint8>(shared);
    final status = encaps(cipher, secret, key);
    calloc.free(key);
    final result = (
      cipher: take(cipher, ciphers),
      secret: take(secret, shared),
    );
    if (status != 0) throw StateError('ML-KEM encapsulation failed');
    return result;
  }

  /// Recovers the shared secret from [cipher] with [secret], the private
  /// half of the key it was sealed to.
  static Uint8List open(Uint8List cipher, Uint8List secret) {
    if (cipher.length != ciphers || secret.length != secrets) {
      throw ArgumentError('Wrong ML-KEM sizes');
    }
    final sealed = give(cipher);
    final key = give(secret);
    final out = calloc<Uint8>(shared);
    final status = decaps(out, sealed, key);
    calloc.free(sealed);
    key.asTypedList(secrets).fillRange(0, secrets, 0);
    calloc.free(key);
    final result = take(out, shared);
    if (status != 0) throw StateError('ML-KEM decapsulation failed');
    return result;
  }
}
