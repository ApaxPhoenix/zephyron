import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/wrappers/oqs.dart';
import 'support.dart';

/// Runs against the bundled ML-KEM-768 from liboqs when ZEPHYRON_OQS points
/// at a desktop build of it; otherwise the post-quantum cases are skipped.
void main() {
  setUpAll(unlock);

  final skip = Kem.available
      ? false
      : 'Set ZEPHYRON_OQS to a desktop liboqs build to run these';

  test('key, ciphertext and secret sizes match FIPS 203', () {
    final pair = Kem.pair();
    expect(pair.public, hasLength(Kem.publics));
    expect(pair.secret, hasLength(Kem.secrets));
    final sealed = Kem.seal(pair.public);
    expect(sealed.cipher, hasLength(Kem.ciphers));
    expect(sealed.secret, hasLength(Kem.shared));
  }, skip: skip);

  test('both sides reach the same secret, a tampered ciphertext does not', () {
    final pair = Kem.pair();
    final sealed = Kem.seal(pair.public);
    expect(Kem.open(sealed.cipher, pair.secret), sealed.secret);
    final bent = sealed.cipher.sublist(0)..[100] ^= 1;
    expect(Kem.open(bent, pair.secret), isNot(sealed.secret));
    expect(Kem.seal(pair.public).secret, isNot(sealed.secret));
  }, skip: skip);

  group('sessions', () {
    late Identity lead;
    late Identity follower;

    setUp(() {
      final pair = [
        Identity.fromInput('pq lead ${DateTime.now().microsecondsSinceEpoch}'),
        Identity.fromInput('pq other ${DateTime.now().microsecondsSinceEpoch}'),
      ]..sort((alpha, beta) => alpha.address.compareTo(beta.address));
      lead = pair.first;
      follower = pair.last;
    });

    test('a session is post-quantum when both sides can do it', () async {
      final bundle = await Ratchet.bundle(follower);
      expect((bundle['pq'] as String?)?.length, isNotNull);
      await Ratchet.learn(follower.address, bundle);
      await Ratchet.learn(lead.address, await Ratchet.bundle(lead));

      final first = await Ratchet.seal(
        lead,
        follower.address,
        utf8.encode('hi'),
      );
      expect((first['h'] as Map)['x3dh']['kem'], isA<String>());
      expect(
        utf8.decode(await Ratchet.open(follower, lead.address, first)),
        'hi',
      );
      expect((await Ratchet.session(lead, follower.address))!.quantum, isTrue);
      expect((await Ratchet.session(follower, lead.address))!.quantum, isTrue);

      final back = await Ratchet.seal(
        follower,
        lead.address,
        utf8.encode('hey'),
      );
      expect(
        utf8.decode(await Ratchet.open(lead, follower.address, back)),
        'hey',
      );
    }, skip: skip);

    test('without a post-quantum key the session stays classical', () async {
      final bundle = Map<String, dynamic>.from(await Ratchet.bundle(follower))
        ..remove('pq');
      await Ratchet.learn(follower.address, bundle);
      final first = await Ratchet.seal(
        lead,
        follower.address,
        utf8.encode('hi'),
      );
      expect((first['h'] as Map)['x3dh']['kem'], isNull);
      expect(
        utf8.decode(await Ratchet.open(follower, lead.address, first)),
        'hi',
      );
      expect((await Ratchet.session(lead, follower.address))!.quantum, isFalse);
    });
  });
}
