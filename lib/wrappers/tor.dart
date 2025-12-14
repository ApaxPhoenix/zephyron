import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart' show sha512;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

final DynamicLibrary library = () {
  if (!Platform.isAndroid) throw UnsupportedError('Android');
  try {
    return DynamicLibrary.open('libtor.so');
  } catch (error) {
    developer.log(
      'Failed to load libtor dynamic library',
      name: 'library',
      level: 1000,
      error: error,
      stackTrace: StackTrace.current,
    );
    rethrow;
  }
}();

final DynamicLibrary system = () {
  try {
    return DynamicLibrary.open('libc.so');
  } catch (error) {
    developer.log(
      'Failed to load libc dynamic library',
      name: 'system',
      level: 1000,
      error: error,
      stackTrace: StackTrace.current,
    );
    rethrow;
  }
}();

final Pointer<Utf8> Function() release = library
    .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
  'tor_api_get_provider_version',
);

final Pointer<Void> Function() allocate = library
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
  'tor_main_configuration_new',
);

final int Function(Pointer<Void>, int, Pointer<Pointer<Utf8>>) configure =
library.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Pointer<Pointer<Utf8>>),
    int Function(Pointer<Void>, int, Pointer<Pointer<Utf8>>)
>('tor_main_configuration_set_command_line');

final int Function(Pointer<Void>) socket = library
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'tor_main_configuration_setup_control_socket',
);

final void Function(Pointer<Void>) free = library
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
  'tor_main_configuration_free',
);

final int Function(Pointer<Void>) launch = library
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'tor_run_main',
);

final int Function(int, int, int, int, int) restrict = system.lookupFunction<
    Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64),
    int Function(int, int, int, int, int)
>('prctl');

final int Function(Pointer<Utf8>, int) permit = system.lookupFunction<
    Int32 Function(Pointer<Utf8>, Uint32),
    int Function(Pointer<Utf8>, int)
>('chmod');

void grant(String path, int mode) {
  final pointer = path.toNativeUtf8();
  try {
    permit(pointer, mode);
  } catch (error) {
    developer.log(
      'Failed to execute system permission modification',
      name: 'grant',
      level: 1000,
      error: error,
      stackTrace: StackTrace.current,
    );
  } finally {
    calloc.free(pointer);
  }
}

class Tor {
  String? path;
  String? binary;
  String? bridge;
  String host;
  int port;
  List<String> flags;

  Pointer<Void> state = nullptr;
  Isolate? worker;

  Tor({
    this.path,
    this.binary,
    this.bridge,
    this.host = '127.0.0.1',
    this.port = 9050,
    this.flags = const [],
  });

  static String get version {
    try {
      final reference = release();
      if (reference != nullptr) return reference.toDartString();
    } catch (error) {
      developer.log(
        'Failed to query native Tor provider version string',
        name: 'Tor.version',
        level: 500,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
    return 'Unknown';
  }

  Future<void> boot() async {
    developer.log(
      'Starting Tor runtime initialization workflow',
      name: 'Tor.boot',
      level: 800,
    );

    path ??= '${(await getApplicationSupportDirectory()).path}/tor';

    final folder = Directory(path!);
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
      developer.log(
        'Created isolated data directory for process execution',
        name: 'Tor.boot',
        level: 800,
      );
    }

    if (binary == null) {
      try {
        final bundle = await const MethodChannel('zephyron/security')
            .invokeMethod<String>('packages');

        if (bundle != null && bundle.isNotEmpty) {
          final source = File('$bundle/libobfs4proxy.so');
          final target = File('$path/libobfs4proxy.so');

          if (source.existsSync()) {
            if (!target.existsSync() || target.lengthSync() != source.lengthSync()) {
              await source.copy(target.path);
              developer.log(
                'Copied transport proxy binary to local working directory',
                name: 'Tor.boot',
                level: 800,
              );
            }
            binary = target.path;
          }
        }
      } catch (error) {
        developer.log(
          'Failed to locate transport proxy binary from platform environment',
          name: 'Tor.boot',
          level: 500,
          error: error,
          stackTrace: StackTrace.current,
        );
      }
    }

    final receiver = ReceivePort();
    final signal = Completer<void>();

    receiver.listen((message) {
      if (message == 'ready') {
        developer.log(
          'Received completion signal from background proxy isolate',
          name: 'Tor.boot',
          level: 800,
        );
        if (!signal.isCompleted) signal.complete();
      } else if (message is String && message.startsWith('fail')) {
        final error = StateError('Isolate execution failed with code: $message');
        developer.log(
          'Background proxy isolate reported runtime failure',
          name: 'Tor.boot',
          level: 1000,
          error: error,
          stackTrace: StackTrace.current,
        );
        if (!signal.isCompleted) signal.completeError(error);
      }
    });

    final data = [
      receiver.sendPort,
      path!,
      binary ?? '',
      bridge ?? '',
      host,
      port,
      flags,
    ];

    worker = await Isolate.spawn(spawn, data);

    return signal.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        if (!signal.isCompleted) signal.complete();
      },
    );
  }

  static void spawn(List<dynamic> arguments) {
    final sender = arguments[0] as SendPort;
    final node = Tor(
      path: arguments[1] as String,
      binary: arguments[2] as String,
      bridge: arguments[3] as String,
      host: arguments[4] as String,
      port: arguments[5] as int,
      flags: arguments[6] as List<String>,
    );

    developer.log(
      'Executing native process sequence inside spawned isolate',
      name: 'Tor.spawn',
      level: 800,
    );

    sender.send('ready');
    final code = node.run();
    if (code != 0) {
      developer.log(
        'Native process exited with non-zero status code',
        name: 'Tor.spawn',
        level: 1000,
      );
      sender.send('fail:$code');
    }
  }

  int run() {
    developer.log(
      'Configuring security privileges and dynamic parameters',
      name: 'Tor.run',
      level: 800,
    );

    if (kReleaseMode && (Platform.isAndroid || Platform.isLinux)) {
      try {
        restrict(4, 0, 0, 0, 0);
        developer.log(
          'Applied process memory restriction rules',
          name: 'Tor.run',
          level: 800,
        );
      } catch (error) {
        developer.log(
          'Failed to apply security restriction policy to runtime process',
          name: 'Tor.run',
          level: 500,
          error: error,
          stackTrace: StackTrace.current,
        );
      }
    }

    if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
      grant(path!, 448);
    }

    try {
      state = allocate();
    } catch (error) {
      developer.log(
        'Failed to allocate configuration memory handle',
        name: 'Tor.run',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }

    bool proxy = false;
    if (binary != null && binary!.isNotEmpty && File(binary!).existsSync()) {
      if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
        grant(binary!, 448);
      }
      proxy = true;
    }

    final orders = <String>[
      'tor',
      '--DataDirectory', path!,
      '--SocksPort', '$host:$port',
      '--ControlPort', 'unix:$path/control.sock',
      '--ControlSocketsGroupWritable', '0',
      '--CookieAuthentication', '1',
      '--CookieAuthFile', '$path/cookie',
      '--AvoidDiskWrites', '1',
      '--SafeLogging', '1',
      '--HardwareAccel', '1',
      '--HiddenServiceStatistics', '0',
      if (proxy) ...['--ClientTransportPlugin', 'obfs4 exec $binary'],
      if (bridge != null && bridge!.isNotEmpty) ...['--UseBridges', '1', '--Bridge', bridge!],
      ...flags,
    ];

    final array = calloc<Pointer<Utf8>>(orders.length);
    final list = <Pointer<Utf8>>[];

    for (var index = 0; index < orders.length; index++) {
      final pointer = orders[index].toNativeUtf8();
      array[index] = pointer;
      list.add(pointer);
    }

    int code = -1;
    try {
      if (state != nullptr && configure(state, orders.length, array) == 0) {
        code = launch(state);
      } else {
        developer.log(
          'Native command line configuration rejected, refusing legacy fallback entrypoint',
          name: 'Tor.run',
          level: 1000,
          error: StateError('Embedded runtime configuration failed'),
          stackTrace: StackTrace.current,
        );
      }
      developer.log(
        'Native daemon execution loop finished',
        name: 'Tor.run',
        level: 800,
      );
    } catch (error) {
      developer.log(
        'Unhandled exception thrown during native daemon execution',
        name: 'Tor.run',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    } finally {
      for (final pointer in list) {
        calloc.free(pointer);
      }
      calloc.free(array);
    }

    return code;
  }

  int pipe() => state == nullptr ? -1 : socket(state);

  void dispose() {
    if (state != nullptr) {
      free(state);
      state = nullptr;
      developer.log(
        'Released native configuration memory handle',
        name: 'Tor.dispose',
        level: 500,
      );
    }

    if (worker != null) {
      worker!.kill(priority: Isolate.immediate);
      worker = null;
      developer.log(
        'Terminated background isolate hosting the embedded Tor daemon process',
        name: 'Tor.dispose',
        level: 500,
      );
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

class Sentinel {
  static Sentinel? keeper;

  Tor? circuit;
  Completer<void>? promise;
  Socket? link;
  StreamIterator<String>? flow;
  String? location;

  static Sentinel summon() {
    keeper ??= Sentinel();
    return keeper!;
  }

  Future<void> prepare(String target) {
    if (promise != null) return promise!.future;
    location = target;
    promise = Completer<void>();
    guard();
    return promise!.future;
  }

  Future<void> guard() async {
    developer.log(
      'Beginning shared Tor daemon boot and control channel negotiation',
      name: 'Sentinel.guard',
      level: 800,
    );

    try {
      await assemble().timeout(const Duration(minutes: 3));

      developer.log(
        'Shared Tor daemon reported full bootstrap completion',
        name: 'Sentinel.guard',
        level: 800,
      );

      promise!.complete();
    } catch (error) {
      developer.log(
        'Failed to boot shared Tor daemon or negotiate control channel',
        name: 'Sentinel.guard',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );

      link?.destroy();
      link = null;
      flow = null;
      circuit?.dispose();
      circuit = null;

      promise!.completeError(error);
      promise = null;
    }
  }

  Future<void> assemble() async {
    final folder = Directory(location!);
    if (!await folder.exists()) await folder.create(recursive: true);
    if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
      grant(location!, 448);
    }

    final file = File('$location/control.sock');

    if (circuit == null) {
      final residue = File('$location/state');
      if (await residue.exists()) await residue.delete();

      if (await file.exists()) await file.delete();

      circuit = Tor(path: location);
      unawaited(
        circuit!.boot().catchError((error) {
          developer.log(
            'Background boot of the shared Tor daemon reported failure',
            name: 'Sentinel.assemble',
            level: 1000,
            error: error,
            stackTrace: StackTrace.current,
          );
        }),
      );
    }

    if (!await file.exists()) {
      final horizon = folder.watch(events: FileSystemEvent.create);
      final arrival = horizon.firstWhere((event) => event.path == file.path);
      await arrival;
    }

    if (link == null) {
      var round = 0;
      while (link == null) {
        try {
          link = await Socket.connect(
            InternetAddress(file.path, type: InternetAddressType.unix),
            0,
          );
        } catch (error) {
          round += 1;
          if (round >= 10) rethrow;
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      final lines = link!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      flow = StreamIterator<String>(lines);

      final cookie = File('$location/cookie');
      if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
        grant(cookie.path, 384);
      }
      final bytes = await cookie.readAsBytes();
      final digest = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

      await order('AUTHENTICATE $digest');
      await order('SETEVENTS STATUS_CLIENT');
    }

    final phase = await order('GETINFO status/bootstrap-phase');
    if (!phase.contains('PROGRESS=100')) await listen();
  }

  Future<String> order(String demand) async {
    link?.write('$demand\r\n');
    await link?.flush();

    late String answer;
    while (true) {
      final buffer = StringBuffer();
      while (await flow!.moveNext()) {
        final line = flow!.current;
        buffer.writeln(line);
        if (line.length >= 4 && line[3] == ' ') break;
      }
      answer = buffer.toString();

      final code = answer.length >= 3 ? answer.substring(0, 3) : '';
      if (code == '650') {
        developer.log(
          'Discarded an asynchronous event notification received while awaiting a command reply',
          name: 'Sentinel.order',
          level: 500,
        );
        continue;
      }
      break;
    }

    if (!answer.trim().split('\n').last.startsWith('250')) {
      final command = demand.split(' ').first;
      final issue = StateError(
        'Control channel command rejected: $command -> ${answer.trim()}',
      );
      developer.log(
        'Control channel rejected an issued command during negotiation',
        name: 'Sentinel.order',
        level: 1000,
        error: issue,
        stackTrace: StackTrace.current,
      );
      throw issue;
    }
    return answer;
  }

  Future<void> listen() async {
    while (await flow!.moveNext()) {
      final line = flow!.current;
      if (line.contains('BOOTSTRAP') && line.contains('PROGRESS=100')) return;
    }
    final issue = StateError('Control channel closed before bootstrap completion');
    developer.log(
      'Control channel closed while awaiting bootstrap completion event',
      name: 'Sentinel.listen',
      level: 1000,
      error: issue,
      stackTrace: StackTrace.current,
    );
    throw issue;
  }

  Future<String> publish(String target, String secret) async {
    await prepare(target);
    final answer = await order(
      'ADD_ONION ED25519-V3:$secret Port=80,127.0.0.1:8080 Flags=Detach',
    );
    final match = RegExp(r'ServiceID=(\S+)').firstMatch(answer);
    if (match == null) {
      final issue = StateError('Service identifier missing from control channel answer');
      developer.log(
        'Onion service publication answer missing expected service identifier',
        name: 'Sentinel.publish',
        level: 1000,
        error: issue,
        stackTrace: StackTrace.current,
      );
      throw issue;
    }
    developer.log(
      'Successfully authenticated and published shared onion service endpoint',
      name: 'Sentinel.publish',
      level: 800,
    );
    return match.group(1)!;
  }
}

String blob(String text) {
  if (text.length < 128) throw ArgumentError('Input payload below key minimum length');

  final raw = Uint8List(64);
  for (var index = 0; index < 64; index++) {
    raw[index] = int.parse(text.substring(index * 2, index * 2 + 2), radix: 16);
  }

  final seed = raw.sublist(0, 32);
  final data = Uint8List.fromList(sha512.convert(seed).bytes);
  data[0] &= 248;
  data[31] &= 127;
  data[31] |= 64;

  final output = base64.encode(data);

  raw.fillRange(0, raw.length, 0);
  seed.fillRange(0, seed.length, 0);
  data.fillRange(0, data.length, 0);

  return output;
}