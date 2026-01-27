import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/wrappers/tor.dart';

void main() {
  group('Circuit.parse', () {
    test('reads a general circuit with nicknamed hops', () {
      final circuit = Circuit.parse(
        r'7 BUILT $AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111~GuardOne,$bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222~Middle,$CCCC3333CCCC3333CCCC3333CCCC3333CCCC3333~ExitNode BUILD_FLAGS=NEED_CAPACITY PURPOSE=GENERAL TIME_CREATED=2026-10-13T08:15:30.123456',
      );
      expect(circuit.id, '7');
      expect(circuit.status, 'BUILT');
      expect(circuit.purpose, 'GENERAL');
      expect(circuit.path.map((relay) => relay.nickname), [
        'GuardOne',
        'Middle',
        'ExitNode',
      ]);
      expect(
        circuit.path[1].fingerprint,
        'BBBB2222BBBB2222BBBB2222BBBB2222BBBB2222',
      );
      expect(circuit.created, DateTime.parse('2026-10-13T08:15:30.123456'));
    });

    test('reads onion service circuits and their target', () {
      final circuit = Circuit.parse(
        r'123 BUILT $AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111=Guard,$DDDD4444DDDD4444DDDD4444DDDD4444DDDD4444 PURPOSE=HS_CLIENT_REND HS_STATE=HSCR_JOINED REND_QUERY=exampleonionaddress',
      );
      expect(circuit.id, '123');
      expect(circuit.purpose, 'HS_CLIENT_REND');
      expect(circuit.target, 'exampleonionaddress');
      expect(circuit.path.first.nickname, 'Guard');
      expect(circuit.path.last.nickname, isEmpty);
    });

    test('tolerates circuits without a path yet', () {
      final circuit = Circuit.parse('9 LAUNCHED PURPOSE=GENERAL');
      expect(circuit.status, 'LAUNCHED');
      expect(circuit.path, isEmpty);
      expect(circuit.created, isNull);
    });
  });

  group('Sentinel.sanitize', () {
    const fingerprint = '0123456789ABCDEF0123456789ABCDEF01234567';

    test('accepts obfs4 and vanilla bridges', () {
      expect(
        Sentinel.sanitize(
          'obfs4 192.0.2.10:443 $fingerprint cert=abc+def/ghi iat-mode=0',
        ),
        'obfs4 192.0.2.10:443 $fingerprint cert=abc+def/ghi iat-mode=0',
      );
      expect(
        Sentinel.sanitize('198.51.100.7:9001 $fingerprint'),
        '198.51.100.7:9001 $fingerprint',
      );
      expect(
        Sentinel.sanitize('obfs4 [2001:db8::1]:443 $fingerprint cert=x'),
        isNotNull,
      );
    });

    test('normalises pasted torrc lines and whitespace', () {
      expect(
        Sentinel.sanitize('  Bridge   obfs4  192.0.2.10:443   $fingerprint  '),
        'obfs4 192.0.2.10:443 $fingerprint',
      );
    });

    test('rejects malformed lines', () {
      expect(Sentinel.sanitize('snowflake 192.0.2.3:80 $fingerprint'), isNull);
      expect(Sentinel.sanitize('obfs4 192.0.2.10 $fingerprint'), isNull);
      expect(Sentinel.sanitize('obfs4 192.0.2.10:443 nothex'), isNull);
      expect(Sentinel.sanitize(''), isNull);
    });
  });
}
