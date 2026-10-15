import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'dart:typed_data';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/wrappers/tor.dart';

void main() {
  final alice = Identity.fromInput('alice test seed phrase');
  final bob = Identity.fromInput('bob test seed phrase');

  void become(Identity identity) {
    Courier.instance.self = identity;
    Courier.instance.secret = ed25519.PrivateKey(
      Courier.decode(identity.private),
    );
  }

  group('Identity', () {
    test('derived addresses validate', () {
      expect(Identity.valid(alice.address), isTrue);
      expect(Identity.valid(alice.address.toUpperCase()), isTrue);
    });

    test('corrupted addresses are rejected', () {
      final flipped =
          '${alice.address[0] == 'a' ? 'b' : 'a'}${alice.address.substring(1)}';
      expect(Identity.valid(flipped), isFalse);
      expect(Identity.valid('short.onion'), isFalse);
      expect(Identity.valid(alice.address.replaceAll('.onion', '')), isFalse);
    });
  });

  group('Courier frames', () {
    test('a sealed frame verifies for its recipient', () {
      become(alice);
      final frame = Courier.instance.seal(
        Signal.message,
        bob.address,
        body: 'hi',
      );
      become(bob);
      expect(Courier.instance.authentic(frame), isTrue);
    });

    test('tampering, misdirection and impersonation fail', () {
      become(alice);
      final frame = Courier.instance.seal(
        Signal.message,
        bob.address,
        body: 'hi',
      );

      become(bob);
      expect(
        Courier.instance.authentic({...frame, 'body': 'changed'}),
        isFalse,
      );
      expect(
        Courier.instance.authentic({...frame, 'from': bob.address}),
        isFalse,
      );
      expect(
        Courier.instance.authentic({...frame, 'key': bob.public}),
        isFalse,
      );

      become(alice);
      expect(Courier.instance.authentic(frame), isFalse);
    });
  });

  group('Sharing and verification', () {
    test('discovery key round trips through the onion address', () {
      expect(Courier.encode(Identity.key(alice.address)), alice.public);
    });

    test('safety code is identical from both sides', () {
      final mine = Courier.safety(alice.address, bob.address);
      final theirs = Courier.safety(bob.address, alice.address);
      expect(mine, theirs);
      expect(mine, hasLength(6));
      expect(mine.every((group) => RegExp(r'^\d{5}$').hasMatch(group)), isTrue);
      final other = Identity.fromInput('carol test seed phrase');
      expect(Courier.safety(alice.address, other.address), isNot(mine));
    });

    test('share links carry the key and name', () {
      final link = Courier.link(bob.address, 'Bob Stone');
      final parsed = Courier.parse(link);
      expect(parsed?.address, bob.address);
      expect(parsed?.name, 'Bob Stone');
      expect(
        Courier.parse('hey add ${bob.address} please')?.address,
        bob.address,
      );
      expect(Courier.parse('nothing here'), isNull);
    });
  });

  group('Storage models', () {
    test('trustee rows survive a round trip', () {
      final trustee = Trustee(
        address: bob.address,
        nickname: 'Bobby',
        trust: Trust.stranger,
        alias: 'Bob',
        mood: 'shipping',
        availability: Availability.busy,
        avatar: Uint8List.fromList([1, 2, 3]),
        revision: 7,
      );
      final copy = Trustee.fromRow(trustee.toRow());
      expect(copy.label, 'Bobby');
      expect(copy.trust, Trust.stranger);
      expect(copy.availability, Availability.busy);
      expect(copy.avatar, [1, 2, 3]);
      expect(copy.revision, 7);
    });

    test('profiles clip oversized fields', () {
      final profile = Profile.fromJson({
        'name': 'x' * 100,
        'bio': 'y' * 400,
        'availability': 'invisible',
      });
      expect(profile.name.length, Profile.names);
      expect(profile.bio.length, Profile.bios);
      expect(profile.availability, Availability.invisible);
    });

    test('attachments seal and open with AES-256-GCM', () async {
      final clear = Uint8List.fromList(List.generate(70000, (i) => i % 251));
      final key = Locker.random(32);
      final nonce = Locker.random(12);
      final sealed = await Locker.encrypt(clear, key, nonce);
      expect(sealed.length, clear.length + 16);
      expect(await Locker.decrypt(sealed, key, nonce), clear);

      sealed[10] ^= 0xFF;
      expect(() => Locker.decrypt(sealed, key, nonce), throwsA(anything));
    });
  });

  group('Tor.connect', () {
    ServerSocket? proxy;

    setUp(() async {
      try {
        proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 9050);
      } on SocketException {
        proxy = null;
      }
    });

    tearDown(() async => proxy?.close());

    test('negotiates SOCKS5 and keeps the stream usable', () async {
      if (proxy == null) {
        markTestSkipped('Port 9050 is busy on this machine');
        return;
      }

      final requested = Completer<String>();
      proxy!.listen((client) async {
        var stage = 0;
        client.listen((data) async {
          if (stage == 0) {
            stage = 1;
            client.add([0x05, 0x00]);
          } else if (stage == 1) {
            stage = 2;
            final length = data[4];
            requested.complete(utf8.decode(data.sublist(5, 5 + length)));
            client.add([0x05, 0x00, 0x00]);
            await client.flush();
            await Future<void>.delayed(const Duration(milliseconds: 20));
            client.add([0x01, 127, 0, 0, 1, 0, 80, ...utf8.encode('hello\n')]);
          } else {
            client.add(data);
          }
        });
      });

      final tunnel = await Tor.connect(bob.address, 80);
      expect(await requested.future, bob.address);

      final received = <int>[];
      final echoed = Completer<void>();
      tunnel.stream.listen((chunk) {
        received.addAll(chunk);
        if (utf8.decode(received).contains('world')) echoed.complete();
      });
      tunnel.socket.write('world\n');
      await echoed.future.timeout(const Duration(seconds: 5));

      expect(utf8.decode(received), 'hello\nworld\n');
      tunnel.socket.destroy();
    });
  });
}
