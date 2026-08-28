import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary system = DynamicLibrary.open('libc.so');

final restrict = system.lookupFunction<
    Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64),
    int Function(int, int, int, int, int)
>('prctl');

void harden() {
  try {
    restrict(4, 0, 0, 0, 0);
  } catch (_) {}
}

final DynamicLibrary library = () {
  if (!Platform.isAndroid) throw UnsupportedError('Android');
  try {
    return DynamicLibrary.open('libtor.so');
  } catch (error) {
    throw StateError('Missing libtor.so: $error');
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
    .lookupFunction<
    Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)
>('tor_main_configuration_setup_control_socket');

final void Function(Pointer<Void>) freeState = library
    .lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
>('tor_main_configuration_free');

final int Function(Pointer<Void>) launch = library
    .lookupFunction<
    Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)
>('tor_run_main');

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
    } catch (_) {}
    return 'Unknown';
  }

  int boot() {
    harden();

    state = allocate();

    final flags = <List<int>>[
      'tor'.codeUnits,
      '--DataDirectory'.codeUnits,
      path.codeUnits,
      '--SocksPort'.codeUnits,
      '$host:$port'.codeUnits,
      '--ControlPort'.codeUnits,
      'unix:$path/control.sock'.codeUnits,
      '--ControlSocketsGroupWritable'.codeUnits,
      '0'.codeUnits,
      '--CookieAuthentication'.codeUnits,
      '1'.codeUnits,
      '--CookieAuthFile'.codeUnits,
      '$path/cookie'.codeUnits,
      '--AvoidDiskWrites'.codeUnits,
      '1'.codeUnits,
      '--SafeLogging'.codeUnits,
      '1'.codeUnits,
      '--HardwareAcc'.codeUnits,
      '1'.codeUnits,
      '--FetchServerDescriptors'.codeUnits,
      '0'.codeUnits,
      '--HiddenserviceStatisticsChecking'.codeUnits,
      '0'.codeUnits,
      if (binary.isNotEmpty) ...[
        '--ClientTransportPlugin'.codeUnits,
        'obfs4 exec $binary'.codeUnits,
      ],
      if (bridge.isNotEmpty) ...[
        '--UseBridges'.codeUnits,
        '1'.codeUnits,
        '--Bridge'.codeUnits,
        bridge.codeUnits,
      ],
      for (final arg in args) arg.codeUnits,
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
    } finally {
      for (int count = 0; count < references.length; count++) {
        final reference = references[count];
        final size = sizes[count];
        reference.cast<Uint8>().asTypedList(size).fillRange(0, size, 0);
        calloc.free(reference);
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
      freeState(state);
      state = nullptr;
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