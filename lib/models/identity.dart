import 'dart:convert';
import 'dart:typed_data';
import 'package:base32/base32.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:zephyron/services/keccak.dart';

class Identity {
  String address;
  String public;
  String private;
  String name;
  DateTime date;

  Identity({
    required this.address,
    required this.public,
    required this.private,
    required this.name,
    required this.date,
  });

  factory Identity.parse(String input, {String name = 'Default'}) {
    var seed = bip39.validateMnemonic(input.trim())
        ? Uint8List.fromList(bip39.mnemonicToSeed(input.trim()).sublist(0, 32))
        : Uint8List.fromList(sha256.convert(utf8.encode(input.trim())).bytes);

    var key = ed25519.newKeyFromSeed(seed);
    var pub = Uint8List.fromList(ed25519.public(key).bytes);

    return Identity(
      address: onion(pub),
      public: pub.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      private: Uint8List.fromList(
        key.bytes,
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      name: name,
      date: DateTime.now(),
    );
  }

  /// The v3 onion address of an Ed25519 public key, with the checksum Tor
  /// expects: the first two bytes of SHA3-256 over ".onion checksum", the
  /// key and the version.
  static String onion(List<int> pub) => encode(pub, Keccak.digest);

  /// The address older builds made, whose checksum used SHA-256 by mistake.
  /// Tor refuses those, so they are only recognised to be mended.
  static String legacy(List<int> pub) =>
      encode(pub, (data) => sha256.convert(data).bytes);

  static String encode(List<int> pub, List<int> Function(List<int>) hash) {
    final sum = hash([...utf8.encode('.onion checksum'), ...pub, 3]);
    return '${base32.encode(Uint8List.fromList([...pub, ...sum.sublist(0, 2), 3])).toLowerCase()}.onion';
  }

  static Uint8List key(String address) {
    final text = address.trim().toLowerCase().replaceAll('.onion', '');
    return Uint8List.fromList(base32.decode(text.toUpperCase()).sublist(0, 32));
  }

  /// The key inside a well-formed address, whatever its checksum.
  static List<int>? unpack(String address) {
    final text = address.trim().toLowerCase();
    if (!RegExp(r'^[a-z2-7]{56}\.onion$').hasMatch(text)) return null;
    try {
      final bytes = base32.decode(text.substring(0, 56).toUpperCase());
      if (bytes.length != 35 || bytes[34] != 3) return null;
      return bytes.sublist(0, 32);
    } catch (_) {
      return null;
    }
  }

  static bool valid(String address) {
    final pub = unpack(address);
    return pub != null && onion(pub) == address.trim().toLowerCase();
  }

  /// [address] with Tor's checksum, when it came from an older build;
  /// anything else is returned unchanged.
  static String mend(String address) {
    final text = address.trim().toLowerCase();
    final pub = unpack(text);
    if (pub == null || legacy(pub) != text) return address;
    return onion(pub);
  }

  factory Identity.fromJson(Map<String, dynamic> json) {
    return Identity(
      address: json['address'] as String? ?? '',
      public: json['public'] as String? ?? '',
      private: json['private'] as String? ?? '',
      name: json['name'] as String? ?? '',
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'public': public,
      'private': private,
      'name': name,
      'date': date.toIso8601String(),
    };
  }
}
