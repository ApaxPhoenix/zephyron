import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha512;
import 'package:ffi/ffi.dart';

final DynamicLibrary system = DynamicLibrary.open('libc.so');

final restrict = system.lookupFunction<
    Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64),
    int Function(int, int, int, int, int)>('prctl');

void harden() {
  try {
    restrict(4, 0, 0, 0, 0);
  } catch (error) {
    developer.log('Failed to execute process hardening', level: 500, error: error);
  }
}

final DynamicLibrary library = () {
  if (!Platform.isAndroid) throw UnsupportedError('Android');
  try {
    return DynamicLibrary.open('libtor.so');
  } catch (error) {
    developer.log(
      'Missing libtor.so binary library',
      level: 1000,
      error: error,
      stackTrace: StackTrace.current,
    );
    rethrow;
  }
}();

final Pointer<Utf8> Function() release =
library.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
  'tor_api_get_provider_version',
);

final Pointer<Void> Function() allocate =
library.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
  'tor_main_configuration_new',
);

final int Function(Pointer<Void>, int, Pointer<Pointer<Utf8>>) configure =
library.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Pointer<Pointer<Utf8>>),
    int Function(Pointer<Void>, int, Pointer<Pointer<Utf8>>)>(
  'tor_main_configuration_set_command_line',
);

final int Function(Pointer<Void>) socket = library.lookupFunction<
    Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('tor_main_configuration_setup_control_socket');

final void Function(Pointer<Void>) freeState =
library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
  'tor_main_configuration_free',
);

final int Function(Pointer<Void>) launch =
library.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'tor_run_main',
);

final int Function(int, Pointer<Pointer<Utf8>>) execute = library.lookupFunction<
    Int32 Function(Int32, Pointer<Pointer<Utf8>>),
    int Function(int, Pointer<Pointer<Utf8>>)>('tor_main');

class Tor {
  final String path;
  final String host;
  final int port;
  final String binary;
  final String bridge;
  final List<String> args;

  Pointer<Void> state = nullptr;

  Tor({
    required this.path,
    required this.binary,
    this.bridge = '',
    this.host = '127.0.0.1',
    this.port = 9050,
    this.args = const [],
  });

  static String get version {
    try {
      final reference = release();
      if (reference != nullptr) return reference.toDartString();
    } catch (error) {
      developer.log('Failed to read Tor provider version string', level: 500, error: error);
    }
    return 'Unknown';
  }

  int boot() {
    developer.log('Starting Tor boot sequence', level: 800);
    harden();

    try {
      state = allocate();
    } catch (error, stackTrace) {
      // This is where a missing/incompatible libtor.so, or running on a
      // non-Android platform, actually throws (UnsupportedError or the
      // DynamicLibrary.open failure from the `library` lazy initializer).
      // Previously this exception escaped boot() uncaught, so callers only
      // ever saw a generic 15s timeout instead of the real cause.
      developer.log(
        'Failed to allocate Tor configuration: native library unavailable',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    final flags = <List<int>>[
      utf8.encode('tor'),
      utf8.encode('--DataDirectory'),
      utf8.encode(path),
      utf8.encode('--SocksPort'),
      utf8.encode('$host:$port'),
      utf8.encode('--ControlPort'),
      utf8.encode('unix:$path/control.sock'),
      utf8.encode('--ControlSocketsGroupWritable'),
      utf8.encode('0'),
      utf8.encode('--CookieAuthentication'),
      utf8.encode('1'),
      utf8.encode('--CookieAuthFile'),
      utf8.encode('$path/cookie'),
      utf8.encode('--AvoidDiskWrites'),
      utf8.encode('1'),
      utf8.encode('--SafeLogging'),
      utf8.encode('1'),
      utf8.encode('--HardwareAccel'),
      utf8.encode('1'),
      utf8.encode('--FetchServerDescriptors'),
      utf8.encode('0'),
      utf8.encode('--HiddenServiceStatistics'),
      utf8.encode('0'),
      if (binary.isNotEmpty) ...[
        utf8.encode('--ClientTransportPlugin'),
        utf8.encode('obfs4 exec $binary'),
      ],
      if (bridge.isNotEmpty) ...[
        utf8.encode('--UseBridges'),
        utf8.encode('1'),
        utf8.encode('--Bridge'),
        utf8.encode(bridge),
      ],
      for (final arg in args) utf8.encode(arg),
    ];

    final array = calloc<Pointer<Utf8>>(flags.length);
    final references = <Pointer<Utf8>>[];
    final sizes = <int>[];

    for (int count = 0; count < flags.length; count++) {
      final bytes = flags[count];
      final node = calloc<Uint8>(bytes.length + 1);
      final list = node.asTypedList(bytes.length + 1);
      for (int step = 0; step < bytes.length; step++) {
        list[step] = bytes[step];
      }
      list[bytes.length] = 0;
      final text = node.cast<Utf8>();
      array[count] = text;
      references.add(text);
      sizes.add(bytes.length + 1);
    }

    int status = -1;
    try {
      if (state != nullptr) {
        if (configure(state, flags.length, array) == 0) {
          status = launch(state);
        }
      }
      if (status == -1) {
        status = execute(flags.length, array);
      }
    } catch (error) {
      developer.log(
        'Tor process execution failed',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    } finally {
      for (int count = 0; count < references.length; count++) {
        final reference = references[count];
        final size = sizes[count];
        reference.cast<Uint8>().asTypedList(size).fillRange(0, size, 0);
        calloc.free(reference);
      }
      calloc.free(array);
    }

    if (status != 0) {
      developer.log('Tor process exited with error status', level: 900);
    } else {
      developer.log('Tor boot completed', level: 800);
    }

    return status;
  }

  int pipe() {
    if (state == nullptr) return -1;
    return socket(state);
  }

  void dispose() {
    if (state != nullptr) {
      freeState(state);
      state = nullptr;
      developer.log('Disposed Tor state configuration', level: 500);
    }
  }

  T use<T>(T Function(Tor) action) {
    try {
      return action(this);
    } finally {
      dispose();
    }
  }
}

/// Expands a 32-byte Ed25519 seed into the 64-byte "expanded" secret key
/// format that Tor's `ADD_ONION ED25519-V3:` command expects: SHA-512 of
/// the seed, clamped, and used directly as `scalar (32 bytes) || signing
/// prefix (32 bytes)`. This is NOT the same as a libsodium-style secret
/// key (`seed || public key`) - handing Tor that instead makes it derive
/// a different keypair (and therefore a different onion address) than
/// whatever your app computed independently from the same seed.
Uint8List _expand(Uint8List seed) {
  assert(seed.length == 32, 'Ed25519 seed must be 32 bytes, got ${seed.length}');
  final hash = Uint8List.fromList(sha512.convert(seed).bytes);
  hash[0] &= 248;
  hash[31] &= 127;
  hash[31] |= 64;
  return hash; // bytes 0-31 = clamped scalar, bytes 32-63 = signing prefix
}

/// Builds the base64 blob for Tor's `ADD_ONION ED25519-V3:` command.
///
/// `text` is the 128-hex-char (64-byte) private key coming out of
/// Identity.fromInput. If that 64 bytes is `seed || public key` (the
/// common libsodium/bip39-Ed25519 convention), only the first 32 bytes
/// are the actual seed - the rest is the public key, which Tor doesn't
/// want here at all. We take that seed and expand it into Tor's format.
///
/// If Identity.fromInput already produces Tor's expanded format (i.e. it
/// isn't seed||pubkey), delete the `_expand(seed)` step below and go back
/// to base64-encoding `raw` directly - check that against how `.address`
/// is derived if the mismatch persists after this change.
String blob(String text) {
  final raw = Uint8List(64);
  for (var index = 0; index < 64; index++) {
    raw[index] = int.parse(text.substring(index * 2, index * 2 + 2), radix: 16);
  }

  final seed = raw.sublist(0, 32);
  final expanded = _expand(seed);
  final result = base64.encode(expanded);

  raw.fillRange(0, raw.length, 0);
  seed.fillRange(0, seed.length, 0);
  expanded.fillRange(0, expanded.length, 0);

  return result;
}

Future<String> publish(String path, String identifier) async {
  final directory = Directory(path);
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
    await Process.run('chmod', ['700', path]);
  }

  final control = File('$path/control.sock');
  final address = InternetAddress(control.path, type: InternetAddressType.unix);

  Socket? connection;
  try {
    connection = await Socket.connect(address, 0);
  } catch (error) {
    developer.log('Control socket unreadable, starting Tor daemon', level: 900, error: error);

    if (await control.exists()) await control.delete();

    // Capture what actually goes wrong in the daemon isolate instead of
    // just logging it and discarding it. `daemonError` is what was hiding
    // behind the old generic "Timed out waiting for control socket" /
    // "Failed to initialize network..." messages.
    Object? daemonError;
    StackTrace? daemonStack;

    unawaited(
      Isolate.run(() => Tor(path: path, binary: '').boot()).then((status) {
        if (status != 0) {
          daemonError = StateError('Tor daemon exited with status $status');
          daemonStack = StackTrace.current;
        }
      }).catchError((error, trace) {
        daemonError = error;
        daemonStack = trace;
        developer.log(
          'Background Tor daemon failed to start',
          level: 1000,
          error: error,
          stackTrace: trace,
        );
      }),
    );

    int counter = 0;
    while (!await control.exists() && counter < 30) {
      if (daemonError != null) {
        // Fail immediately with the real cause rather than waiting out
        // the full timeout window and reporting something generic.
        developer.log(
          'Control socket never appeared because the daemon failed',
          level: 1000,
          error: daemonError,
          stackTrace: daemonStack,
        );
        Error.throwWithStackTrace(
          StateError('Tor daemon failed to start: $daemonError'),
          daemonStack ?? StackTrace.current,
        );
      }
      await Future.delayed(const Duration(milliseconds: 500));
      counter++;
    }
    if (!await control.exists()) {
      final reason = daemonError != null ? ' Last known error: $daemonError' : '';
      developer.log(
        'Timed out waiting for control socket creation',
        level: 1000,
        stackTrace: StackTrace.current,
      );
      throw StateError('Timed out waiting for control socket.$reason');
    }

    int attempt = 0;
    while (connection == null) {
      try {
        connection = await Socket.connect(address, 0);
      } catch (error) {
        attempt++;
        if (attempt >= 10) {
          developer.log(
            'Failed to connect to control socket after max attempts',
            level: 1000,
            error: error,
            stackTrace: StackTrace.current,
          );
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  final cookie = File('$path/cookie');
  if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
    await Process.run('chmod', ['600', cookie.path]);
  }

  final lines = connection
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final reader = StreamIterator<String>(lines);

  Future<String> send(String command) async {
    connection?.write('$command\r\n');
    await connection?.flush();
    final buffer = StringBuffer();
    while (await reader.moveNext()) {
      final line = reader.current;
      buffer.writeln(line);
      if (line.length >= 4 && line[3] == ' ') break;
    }
    final result = buffer.toString();
    if (!result.trim().split('\n').last.startsWith('250')) {
      developer.log(
        'Tor control command error response received',
        level: 1000,
        stackTrace: StackTrace.current,
      );
      throw StateError('Tor control command failed: $result');
    }
    return result;
  }

  final secret = await cookie.readAsBytes();
  final hexCookie = secret
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  await send('AUTHENTICATE $hexCookie');

  final result = await send(
    'ADD_ONION ED25519-V3:$identifier Port=80,127.0.0.1:8080 Flags=Detach',
  );

  await reader.cancel();
  await connection.close();

  final match = RegExp(r'ServiceID=(\S+)').firstMatch(result);
  if (match == null) {
    developer.log(
      'Missing service address in ADD_ONION response',
      level: 1000,
      stackTrace: StackTrace.current,
    );
    throw StateError('Missing service address in ADD_ONION response.');
  }

  developer.log('Published onion service successfully', level: 800);
  return match.group(1)!;
}