import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha512;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

final int Function(int, int, int, int, int) restrict = system
    .lookupFunction<
      Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64),
      int Function(int, int, int, int, int)
    >('prctl');

final int Function(Pointer<Utf8>, int) permit = system
    .lookupFunction<
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

  static const int tunnel = 9080;

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

  static Future<Tunnel> connect(String target, [int port = 80]) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        '127.0.0.1',
        9050,
        timeout: const Duration(seconds: 10),
      );

      final inbox = StreamController<Uint8List>();
      final buffer = BytesBuilder(copy: false);
      final greeted = Completer<void>();
      final opened = Completer<void>();
      var stage = 0;

      void fail(Object error) {
        if (!greeted.isCompleted) greeted.completeError(error);
        if (!opened.isCompleted) opened.completeError(error);
      }

      final sub = socket.listen(
        (chunk) {
          if (stage == 2) {
            inbox.add(chunk);
            return;
          }
          buffer.add(chunk);
          var bytes = buffer.takeBytes();

          if (stage == 0) {
            if (bytes.length < 2) {
              buffer.add(bytes);
              return;
            }
            if (bytes[1] != 0x00) {
              fail(StateError('Proxy authentication rejected'));
              return;
            }
            stage = 1;
            greeted.complete();
            bytes = bytes.sublist(2);
          }

          if (stage == 1) {
            if (bytes.length < 5) {
              buffer.add(bytes);
              return;
            }
            // Status code 0x00 indicates successful circuit setup
            if (bytes[1] != 0x00) {
              fail(StateError('Proxy connection failed with code ${bytes[1]}'));
              return;
            }
            final size = switch (bytes[3]) {
              0x04 => 22, // IPv6 bound address reply
              0x03 => 7 + bytes[4], // Domain bound address reply
              _ => 10, // IPv4 bound address reply
            };
            if (bytes.length < size) {
              buffer.add(bytes);
              return;
            }
            stage = 2;
            opened.complete();
            if (bytes.length > size) inbox.add(bytes.sublist(size));
          }
        },
        onError: (Object error) {
          fail(error);
          if (stage == 2) inbox.addError(error);
        },
        onDone: () {
          fail(const SocketException('Proxy closed the connection'));
          inbox.close();
        },
        cancelOnError: false,
      );
      inbox.onCancel = sub.cancel;

      socket.add([
        0x05, // SOCKS version 5 protocol identifier
        0x01, // Number of authentication methods supported
        0x00, // Unauthenticated method identifier
      ]);
      await greeted.future.timeout(const Duration(seconds: 10));

      final bytes = utf8.encode(target);

      final request = <int>[
        0x05, // SOCKS version 5 protocol identifier
        0x01, // Established TCP stream CONNECT command
        0x00, // Reserved protocol byte
        0x03, // Address type domain name specification
        bytes.length, // Byte length of domain string
        ...bytes, // Raw bytes of target onion domain string
        (port >> 8) & 0xFF, // High order destination port byte
        port & 0xFF, // Low order destination port byte
      ];
      socket.add(request);

      await opened.future.timeout(const Duration(seconds: 60));
      return Tunnel(socket, inbox.stream);
    } catch (error) {
      socket?.destroy();
      developer.log(
        'Failed to connect to peer through SOCKS5 proxy',
        name: 'Tor.connect',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
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
        final bundle = await const MethodChannel(
          'zephyron/security',
        ).invokeMethod<String>('packages');

        if (bundle != null && bundle.isNotEmpty) {
          final source = File('$bundle/libobfs4proxy.so');
          final target = File('$path/libobfs4proxy.so');

          if (source.existsSync()) {
            if (!target.existsSync() ||
                target.lengthSync() != source.lengthSync()) {
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
        final error = StateError(
          'Isolate execution failed with code: $message',
        );
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
      '--DataDirectory',
      path!,
      '--SocksPort',
      '$host:$port',
      '--HTTPTunnelPort',
      '$host:$tunnel',
      '--ControlPort',
      'unix:$path/control.sock',
      '--ControlSocketsGroupWritable',
      '0',
      '--CookieAuthentication',
      '1',
      '--CookieAuthFile',
      '$path/cookie',
      '--AvoidDiskWrites',
      '1',
      '--SafeLogging',
      '1',
      '--HardwareAccel',
      '1',
      '--HiddenServiceStatistics',
      '0',
      if (proxy) ...['--ClientTransportPlugin', 'obfs4 exec $binary'],
      if (bridge != null && bridge!.isNotEmpty) ...[
        '--UseBridges',
        '1',
        '--Bridge',
        bridge!,
      ],
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

class Tunnel {
  final Socket socket;
  final Stream<Uint8List> stream;

  Tunnel(this.socket, this.stream);
}

class Relay {
  final String fingerprint;
  String nickname;
  String address;
  String country;
  List<String> flags;

  Relay({
    required this.fingerprint,
    this.nickname = '',
    this.address = '',
    this.country = '',
    this.flags = const [],
  });
}

class Circuit {
  final String id;
  final String status;
  final String purpose;
  final String target;
  final DateTime? created;
  final List<Relay> path;

  Circuit({
    required this.id,
    required this.status,
    required this.purpose,
    required this.target,
    required this.created,
    required this.path,
  });

  factory Circuit.parse(String line) {
    final tokens = line.trim().split(RegExp(r'\s+'));
    final fields = <String, String>{};
    final path = <Relay>[];
    for (final token in tokens.skip(2)) {
      if (token.startsWith(r'$')) {
        for (final hop in token.split(',')) {
          final parts = hop.substring(1).split(RegExp('[~=]'));
          path.add(
            Relay(
              fingerprint: parts.first.toUpperCase(),
              nickname: parts.length > 1 ? parts[1] : '',
            ),
          );
        }
      } else if (token.contains('=')) {
        final index = token.indexOf('=');
        fields[token.substring(0, index)] = token.substring(index + 1);
      }
    }
    return Circuit(
      id: tokens.isNotEmpty ? tokens[0] : '',
      status: tokens.length > 1 ? tokens[1] : '',
      purpose: fields['PURPOSE'] ?? 'GENERAL',
      target: fields['REND_QUERY'] ?? '',
      created: DateTime.tryParse(fields['TIME_CREATED'] ?? ''),
      path: path,
    );
  }
}

class Sentinel {
  static Sentinel? keeper;
  static const FlutterSecureStorage vault = FlutterSecureStorage();

  final ValueNotifier<int> progress = ValueNotifier<int>(0);
  final Map<String, Relay> relays = {};

  Tor? circuit;
  Completer<void>? promise;
  Socket? link;
  StreamIterator<String>? flow;
  String? location;
  Future<void> gate = Future.value();

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

      progress.value = 100;
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

      progress.value = -1;
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

      final saved = await bridges();
      circuit = Tor(
        path: location,
        flags: [
          if (saved.enabled && saved.lines.isNotEmpty) ...[
            '--UseBridges',
            '1',
            for (final line in saved.lines) ...['--Bridge', line],
          ],
        ],
      );
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
      final digest = bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();

      await order('AUTHENTICATE $digest');
      await order('SETEVENTS STATUS_CLIENT');
    }

    final phase = await order('GETINFO status/bootstrap-phase');
    gauge(phase);
    if (!phase.contains('PROGRESS=100')) await listen();
  }

  void gauge(String line) {
    final match = RegExp(r'PROGRESS=(\d+)').firstMatch(line);
    if (match != null) progress.value = int.parse(match.group(1)!);
  }

  Future<void> retract(String address) async {
    if (link == null) return;
    final service = address.replaceAll('.onion', '');
    try {
      await order('DEL_ONION $service');
      developer.log(
        'Withdrew onion service endpoint from the network',
        name: 'Sentinel.retract',
        level: 800,
      );
    } catch (error) {
      developer.log(
        'Failed to withdraw onion service endpoint from the network',
        name: 'Sentinel.retract',
        level: 900,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  Future<({bool enabled, List<String> lines})> bridges() async {
    try {
      final raw = await vault.read(key: 'bridges');
      if (raw == null) return (enabled: false, lines: <String>[]);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return (
        enabled: data['enabled'] == true,
        lines: List<String>.from(data['lines'] as List? ?? const []),
      );
    } catch (error) {
      developer.log(
        'Failed to read saved bridge configuration',
        name: 'Sentinel.bridges',
        level: 900,
        error: error,
      );
      return (enabled: false, lines: <String>[]);
    }
  }

  Future<bool> bridge(bool enabled, List<String> lines) async {
    await vault.write(
      key: 'bridges',
      value: jsonEncode({'enabled': enabled, 'lines': lines}),
    );
    if (link == null || progress.value != 100) return false;
    if (enabled && lines.isNotEmpty) {
      await order(
        'SETCONF UseBridges=1 ${lines.map((line) => 'Bridge="$line"').join(' ')}',
      );
    } else {
      await order('SETCONF UseBridges=0');
      await order('RESETCONF Bridge');
    }
    return true;
  }

  static String? sanitize(String line) {
    var text = line.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.toLowerCase().startsWith('bridge ')) text = text.substring(7);
    final valid = RegExp(
      r'^(obfs4 )?(\d{1,3}(\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]):\d{1,5} [0-9A-Fa-f]{40}( \S+)*$',
    ).hasMatch(text);
    return valid ? text : null;
  }

  Future<({String version, int read, int written})> vitals() async {
    final reply = await order('GETINFO version traffic/read traffic/written');
    String value(String key) =>
        RegExp('$key=(\\S+)').firstMatch(reply)?.group(1) ?? '';
    return (
      version: value('version'),
      read: int.tryParse(value('traffic/read')) ?? 0,
      written: int.tryParse(value('traffic/written')) ?? 0,
    );
  }

  Future<List<Circuit>> circuits() async {
    final reply = await order('GETINFO circuit-status');
    final built = reply
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) => line.isNotEmpty && line != '.' && !line.startsWith('250'),
        )
        .map(Circuit.parse)
        .where((item) => item.status == 'BUILT' && item.path.isNotEmpty)
        .toList();

    for (final relay in built.expand((item) => item.path)) {
      final known = relays[relay.fingerprint];
      if (known != null) {
        relay
          ..nickname = relay.nickname.isEmpty ? known.nickname : relay.nickname
          ..address = known.address
          ..country = known.country
          ..flags = known.flags;
        continue;
      }
      try {
        final status = await order('GETINFO ns/id/${relay.fingerprint}');
        for (final row in status.split('\n')) {
          final parts = row.trim().split(' ');
          if (parts.first == 'r') {
            final at = parts.indexWhere(
              (part) => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(part),
            );
            if (relay.nickname.isEmpty && parts.length > 1) {
              relay.nickname = parts[1];
            }
            if (at > 0 && at + 1 < parts.length) {
              relay.address = '${parts[at]}:${parts[at + 1]}';
            }
          }
          if (parts.first == 's') relay.flags = parts.skip(1).toList();
        }
        if (relay.address.isNotEmpty) {
          final located = await order(
            'GETINFO ip-to-country/${relay.address.split(':').first}',
          );
          final code = RegExp(r'=([a-z?]{2})').firstMatch(located)?.group(1);
          if (code != null && code != '??') relay.country = code;
        }
      } catch (_) {}
      relays[relay.fingerprint] = relay;
    }
    return built;
  }

  Future<String> order(String demand) {
    final reply = gate.then((_) async {
      if (link == null || flow == null) {
        throw StateError('Tor control channel is not connected');
      }
      link!.write('$demand\r\n');
      await link!.flush();

      late String answer;
      while (true) {
        final buffer = StringBuffer();
        var data = false;
        while (await flow!.moveNext()) {
          final line = flow!.current;
          buffer.writeln(line);
          if (data) {
            if (line == '.') data = false;
            continue;
          }
          if (line.length >= 4 && line[3] == '+') {
            data = true;
            continue;
          }
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
    });
    gate = reply.then<void>((_) {}, onError: (_) {});
    return reply;
  }

  Future<void> listen() async {
    while (await flow!.moveNext()) {
      final line = flow!.current;
      if (line.contains('BOOTSTRAP')) gauge(line);
      if (line.contains('BOOTSTRAP') && line.contains('PROGRESS=100')) return;
    }
    final issue = StateError(
      'Control channel closed before bootstrap completion',
    );
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
      final issue = StateError(
        'Service identifier missing from control channel answer',
      );
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
  if (text.length < 128) {
    throw ArgumentError('Input payload below key minimum length');
  }

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
