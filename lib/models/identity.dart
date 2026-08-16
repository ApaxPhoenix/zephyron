import 'dart:convert';
import 'dart:typed_data';
import 'package:base32/base32.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;

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

  factory Identity.fromInput(String input, {String name = 'Default'}) {
    var seed = bip39.validateMnemonic(input.trim())
        ? Uint8List.fromList(bip39.mnemonicToSeed(input.trim()).sublist(0, 32))
        : Uint8List.fromList(sha256.convert(utf8.encode(input.trim())).bytes);

    var key = ed25519.newKeyFromSeed(seed);
    var pub = Uint8List.fromList(ed25519.public(key).bytes);
    var hash = sha256
        .convert(
          Uint8List.fromList([...utf8.encode('.onion checksum'), ...pub, 3]),
        )
        .bytes;

    return Identity(
      address:
          '${base32.encode(Uint8List.fromList([...pub, ...hash.sublist(0, 2), 3])).toLowerCase()}.onion',
      public: pub.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      private: Uint8List.fromList(
        key.bytes,
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      name: name,
      date: DateTime.now(),
    );
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

  Identity copyWith({
    String? address,
    String? public,
    String? private,
    String? name,
    DateTime? date,
  }) {
    return Identity(
      address: address ?? this.address,
      public: public ?? this.public,
      private: private ?? this.private,
      name: name ?? this.name,
      date: date ?? this.date,
    );
  }
}
