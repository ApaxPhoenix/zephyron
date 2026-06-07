import 'dart:developer' as developer;
import 'dart:io';
import 'package:freerasp/freerasp.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/sql/session.dart';

/// What the app does when freeRASP reports a threat.
enum Response {
  /// Someone is instrumenting or has copied this app: erase everything.
  purge,

  /// The environment is unsafe: close the vault and quit.
  lock,
}

/// Turns freeRASP threat reports into a response proportional to the risk.
///
/// Hooking frameworks, a tampered build or the app's data turning up on
/// another device mean an active attack, so every identity is erased. A
/// debugger, root, an emulator, a spoofed clock, automation tooling or
/// malware only make the phone untrustworthy, so the vault is locked.
/// Either way the process then exits.
class Tripwire {
  static Future<void> Function() erase = () async {
    await Courier.instance.stop();
    await Session.purge();
  };
  static Future<void> Function() lock = () async {
    await Courier.instance.stop();
    await Session.dispose();
  };
  static void Function() halt = () => exit(0);

  static bool tripped = false;

  static Future<void> trip(String risk, Response response) async {
    if (tripped) return;
    tripped = true;
    developer.log(
      'Runtime protection detected: $risk. Responding with ${response.name}.',
      name: 'Tripwire.trip',
      level: 1200,
    );
    try {
      await (response == Response.purge ? erase() : lock());
    } catch (error) {
      developer.log(
        'Failed to finish the threat response before exiting',
        name: 'Tripwire.trip',
        level: 1200,
        error: error,
      );
    } finally {
      halt();
    }
  }

  static ThreatCallback callback() {
    void on(String risk, Response response) => trip(risk, response);
    return ThreatCallback(
      onHooks: () => on('Hooking framework active', Response.purge),
      onAppIntegrity: () => on('App integrity tampered', Response.purge),
      onDeviceBinding: () =>
          on('App data moved to another device', Response.purge),
      onDebug: () => on('Debugger attached', Response.lock),
      onPrivilegedAccess: () => on('Root or jailbreak detected', Response.lock),
      onSimulator: () => on('Emulator detected', Response.lock),
      onTimeSpoofing: () => on('Device clock spoofed', Response.lock),
      onAutomation: () => on('Automation tooling detected', Response.lock),
      onMalware: (_) => on('Malware detected', Response.lock),
    );
  }
}
