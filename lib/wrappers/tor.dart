import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha512;
import 'package:ffi/ffi.dart';

final DynamicLibrary library = () {
  if (!Platform.isAndroid) throw UnsupportedError('Android');
  try {
    return DynamicLibrary.open('libtor.so');
  } catch (fail) {
    developer.log(
      'Missing libtor.so library',
      level: 1000,
      error: fail,
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

final int Function(int, Pointer<Pointer<Utf8>>) execute = library
    .lookupFunction<
    Int32 Function(Int32, Pointer<Pointer<Utf8>>),
    int Function(int, Pointer<Pointer<Utf8>>)
>('tor_main');

class Tor {
  final String path;
  final String host;
  final int port;
  final String binary;
  final String bridge;
  final List<String> arguments;

  Pointer<Void> state = nullptr;

  Tor({
    required this.path,
    required this.binary,
    this.bridge = '',
    this.host = '127.0.0.1',
    this.port = 9050,
    this.arguments = const [],
  });

  static String get version {
    try {
      final ref = release();
      if (ref != nullptr) return ref.toDartString();
    } catch (fail) {
      developer.log('Failed reading Tor version', level: 500, error: fail);
    }
    return 'Unknown';
  }

  int boot() {
    developer.log('Starting Tor boot sequence', level: 800);

    if (Platform.isAndroid || Platform.isLinux) {
      try {
        final system = DynamicLibrary.open('libc.so');
        final restrict = system.lookupFunction<
            Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64),
            int Function(int, int, int, int, int)
        >('prctl');
        restrict(4, 0, 0, 0, 0);
      } catch (fail) {
        developer.log('Failed process hardening', level: 500, error: fail);
      }
    }

    bool native = true;
    try {
      state = allocate();
    } catch (fail, trace) {
      native = false;
      developer.log(
        'Tor library unavailable',
        level: 1000,
        error: fail,
        stackTrace: trace,
      );
    }

    bool proxy = true;
    if (binary.isNotEmpty) {
      try {
        final target = File(binary);
        if (!target.existsSync() || target.lengthSync() == 0) {
          proxy = false;
        }
      } catch (fail) {
        proxy = false;
      }
    }

    if (!native && !proxy) {
      throw StateError('Installation is wrong');
    } else if (!native || (!proxy && binary.isNotEmpty)) {
      throw StateError(
        'Installation correct, but binary is missing or invalid',
      );
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
      for (final item in arguments) utf8.encode(item),
    ];

    final array = calloc<Pointer<Utf8>>(flags.length);
    final items = <Pointer<Utf8>>[];
    final sizes = <int>[];

    for (int index = 0; index < flags.length; index++) {
      final bytes = flags[index];
      final item = calloc<Uint8>(bytes.length + 1);
      final list = item.asTypedList(bytes.length + 1);
      list.setRange(0, bytes.length, bytes);
      list[bytes.length] = 0;

      final text = item.cast<Utf8>();
      array[index] = text;
      items.add(text);
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
    } catch (fail) {
      developer.log(
        'Tor execution failed',
        level: 1000,
        error: fail,
        stackTrace: StackTrace.current,
      );
    } finally {
      for (int index = 0; index < items.length; index++) {
        final item = items[index];
        final size = sizes[index];
        item.cast<Uint8>().asTypedList(size).fillRange(0, size, 0);
        calloc.free(item);
      }
      calloc.free(array);
    }

    return status;
  }

  int pipe() {
    if (state == nullptr) return -1;
    return socket(state);
  }

  void dispose() {
    if (state != nullptr) {
      free(state);
      state = nullptr;
    }
  }

  T use<T>(T Function(Tor) act) {
    try {
      return act(this);
    } finally {
      dispose();
    }
  }
}

String blob(String text) {
  if (text.length < 128) {
    throw ArgumentError('Hex key string must be at least 128 characters');
  }

  final raw = Uint8List(64);
  for (var index = 0; index < 64; index++) {
    raw[index] = int.parse(text.substring(index * 2, index * 2 + 2), radix: 16);
  }

  final seed = raw.sublist(0, 32);
  final expanded = Uint8List.fromList(sha512.convert(seed).bytes);
  expanded[0] &= 248;
  expanded[31] &= 127;
  expanded[31] |= 64;

  final out = base64.encode(expanded);

  raw.fillRange(0, raw.length, 0);
  seed.fillRange(0, seed.length, 0);
  expanded.fillRange(0, expanded.length, 0);

  return out;
}

Future<String> publish(
    String path,
    String identifier, {
      String binary = '',
      List<String> arguments = const [],
    }) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
    await Process.run('chmod', ['700', path]);
  }

  final control = File('$path/control.sock');
  final address = InternetAddress(control.path, type: InternetAddressType.unix);

  Socket? link;
  try {
    link = await Socket.connect(address, 0);
  } catch (fail) {
    if (await control.exists()) await control.delete();

    Object? cause;

    unawaited(
      Isolate.run(
            () => Tor(path: path, binary: binary, arguments: arguments).boot(),
      )
          .then((code) {
        if (code != 0) cause = 'Tor daemon exited with status $code';
      })
          .catchError((err, stack) {
        cause = err;
      }),
    );

    int count = 0;
    while (!await control.exists() && count < 30) {
      if (cause != null) {
        throw StateError('Tor daemon failed to start: $cause');
      }
      await Future.delayed(const Duration(milliseconds: 500));
      count++;
    }

    if (!await control.exists()) {
      throw StateError('Timed out waiting for control socket');
    }

    int retry = 0;
    while (link == null) {
      try {
        link = await Socket.connect(address, 0);
      } catch (fail) {
        retry++;
        if (retry >= 10) rethrow;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  final cookie = File('$path/cookie');
  if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
    await Process.run('chmod', ['600', cookie.path]);
  }

  final lines = link
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final iter = StreamIterator<String>(lines);

  Future<String> send(String cmd) async {
    link?.write('$cmd\r\n');
    await link?.flush();
    final buf = StringBuffer();
    while (await iter.moveNext()) {
      final line = iter.current;
      buf.writeln(line);
      if (line.length >= 4 && line[3] == ' ') break;
    }
    final res = buf.toString();
    if (!res.trim().split('\n').last.startsWith('250')) {
      throw StateError('Tor control command failed: $res');
    }
    return res;
  }

  final key = await cookie.readAsBytes();
  final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  await send('AUTHENTICATE $hex');

  final res = await send(
    'ADD_ONION ED25519-V3:$identifier Port=80,127.0.0.1:8080 Flags=Detach',
  );

  await iter.cancel();
  await link.close();

  final match = RegExp(r'ServiceID=(\S+)').firstMatch(res);
  if (match == null) {
    throw StateError('Missing ServiceID in response');
  }

  return match.group(1)!;
}