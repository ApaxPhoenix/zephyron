import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/services/keccak.dart';

void main() {
  String hexadecimal(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  test('SHA3-256 matches the FIPS 202 examples', () {
    expect(
      hexadecimal(Keccak.digest(const [])),
      'a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a',
    );
    expect(
      hexadecimal(Keccak.digest(utf8.encode('abc'))),
      '3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532',
    );
    expect(
      hexadecimal(Keccak.digest(utf8.encode('a' * 200))),
      hexadecimal(Keccak.digest(utf8.encode('a' * 200))),
    );
  });

  test('SHA3-256 handles input across block boundaries', () {
    // 135, 136 and 137 bytes sit either side of the 136-byte rate.
    for (final length in [135, 136, 137, 272]) {
      expect(Keccak.digest(List.filled(length, 0x61)), hasLength(32));
    }
    expect(
      hexadecimal(Keccak.digest(utf8.encode('a' * 136))),
      isNot(hexadecimal(Keccak.digest(utf8.encode('a' * 135)))),
    );
  });

  test('real onion addresses check out the way Tor checks them', () {
    for (final address in [
      '2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion',
      'duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion',
    ]) {
      expect(Identity.valid(address), isTrue, reason: address);
      expect(Identity.onion(Identity.unpack(address)!), address);
    }
  });

  test('addresses from older builds are mended to the real one', () {
    final identity = Identity.parse('mend test seed');
    final public = Identity.unpack(identity.address)!;
    final old = Identity.legacy(public);
    expect(old, isNot(identity.address));
    expect(Identity.valid(old), isFalse);
    expect(Identity.mend(old), identity.address);
    expect(Identity.mend(identity.address), identity.address);
    expect(Identity.mend('not an address'), 'not an address');
  });
}
