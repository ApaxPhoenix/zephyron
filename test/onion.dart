import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/wrappers/tor.dart';

/// Runs on a phone or a simulator, where Tor really runs: it boots Tor,
/// publishes an onion service and reaches it through Tor, the way one
/// trustee's phone reaches another's.
///
/// The name has no `_test` so `flutter test` leaves it alone on the computer.
/// Run it on a device with:
/// `flutter drive --driver test/driver.dart --target test/onion.dart -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Tor boots and carries bytes to an onion service',
    (tester) async {
      final folder = await getApplicationSupportDirectory();
      final sentinel = Sentinel.summon();
      await sentinel.prepare('${folder.path}/tor');
      expect(sentinel.progress.value, 100);

      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        8080,
      );
      server.listen((socket) => socket.listen(socket.add));

      final reply = await sentinel.order(
        'ADD_ONION NEW:ED25519-V3 Port=80,127.0.0.1:8080 Flags=DiscardPK',
      );
      final service = RegExp(r'ServiceID=(\S+)').firstMatch(reply)!.group(1)!;

      // A new onion service takes a while to publish where others find it.
      Tunnel? tunnel;
      for (var round = 0; tunnel == null && round < 6; round++) {
        try {
          tunnel = await Tor.connect('$service.onion', 80);
        } catch (_) {
          await Future.delayed(const Duration(seconds: 10));
        }
      }
      expect(tunnel, isNotNull, reason: 'Tor never reached $service.onion');

      tunnel!.socket.add(utf8.encode('zephyron'));
      final echo = await tunnel.stream.first.timeout(
        const Duration(minutes: 1),
      );
      expect(utf8.decode(echo), 'zephyron');

      tunnel.socket.destroy();
      await server.close();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
