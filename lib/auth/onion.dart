import 'dart:async';
import 'dart:developer' as developer;
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/sql/session.dart';
import 'package:zephyron/wrappers/tor.dart';

/// Publishes the unlocked identity as an onion service without holding up the
/// screen that unlocked it. Tor can take minutes to bootstrap, and an identity
/// must never be lost or locked behind that wait, so this retries quietly in
/// the background and stops once the identity is locked again.
Future<void> announce(Identity identity, {int attempts = 6}) async {
  for (var round = 1; round <= attempts; round++) {
    if (Session.user?.address != identity.address) return;

    try {
      final folder = await getApplicationSupportDirectory();
      final host = await Sentinel.summon().publish(
        '${folder.path}/tor',
        blob(identity.private),
      );

      final network = host.replaceAll('.onion', '');
      final base = identity.address.replaceAll('.onion', '');
      if (network.length >= 50 &&
          base.length >= 50 &&
          network.substring(0, 50) != base.substring(0, 50)) {
        developer.log(
          'Published onion address does not match the identity address',
          name: 'announce',
          level: 1200,
          error: StateError('network=$host expected=${identity.address}'),
          stackTrace: StackTrace.current,
        );
        return;
      }

      developer.log(
        'Identity onion service is published',
        name: 'announce',
        level: 800,
      );
      return;
    } catch (error) {
      if (error.toString().contains('collision')) {
        developer.log(
          'Identity onion service was already published',
          name: 'announce',
          level: 800,
        );
        return;
      }

      developer.log(
        'Attempt $round of $attempts to publish the identity onion service failed',
        name: 'announce',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      if (round < attempts) {
        await Future.delayed(Duration(seconds: round * 10));
      }
    }
  }
}
