import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary system = DynamicLibrary.open('libc.so');

final prctl = system.lookupFunction<
    Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64),
    int Function(int, int, int, int, int)
>('prctl');

void harden() {
  try {
    prctl(4, 0, 0, 0, 0);
  } catch (_) {}
}

@Native<Pointer<Utf8> Function()>(symbol: 'tor_api_get_provider_version')
external Pointer<Utf8> release();

@Native<Pointer<Void> Function()>(symbol: 'tor_main_configuration_new')
external Pointer<Void> allocate();

@Native<Int32 Function(Pointer<Void>, Int32, Pointer<Pointer<Utf8>>)>(
  symbol: 'tor_main_configuration_set_command_line',
)
external int configure(
    Pointer<Void> configuration,
    int count,
    Pointer<Pointer<Utf8>> vector,
    );

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'tor_main_configuration_setup_control_socket',
)
external int socket(Pointer<Void> configuration);

@Native<Void Function(Pointer<Void>)>(symbol: 'tor_main_configuration_free')
external void clean(Pointer<Void> configuration);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'tor_run_main')
external int launch(Pointer<Void> configuration);

@Native<Int32 Function(Int32, Pointer<Pointer<Utf8>>)>(symbol: 'tor_main')
external int execute(int count, Pointer<Pointer<Utf8>> vector);

final DynamicLibrary library = () {
  if (!Platform.isAndroid) throw UnsupportedError('Only Android is supported.');
  try {
    return DynamicLibrary.open('libtor.so');
  } catch (_) {
    throw StateError('libtor.so not found in jniLibs.');
  }
}();

class Tor {
  final String path;
  final String host;
  final int socks;
  final String binary;
  final String bridge;
  final List<String> arguments;

  Pointer<Void> configuration = nullptr;

  Tor({
    required this.path,
    required this.binary,
    this.bridge = '',
    this.host = '127.0.0.1',
    this.socks = 9050,
    this.arguments = const [],
  });

  static String get version {
    try {
      final pointer = release();
      if (pointer != nullptr) return pointer.toDartString();
    } catch (_) {}
    return 'Unknown';
  }

  int boot() {
    harden();

    configuration = allocate();

    final options = <List<int>>[
      'tor'.codeUnits,
      '--DataDirectory'.codeUnits,
      path.codeUnits,
      '--SocksPort'.codeUnits,
      '$host:$socks'.codeUnits,
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
      for (final argument in arguments) argument.codeUnits,
    ];

    final vector = calloc<Pointer<Utf8>>(options.length);
    final pointers = <Pointer<Utf8>>[];
    final lengths = <int>[];

    for (int index = 0; index < options.length; index++) {
      final bytes = options[index];
      final pointer = calloc<Uint8>(bytes.length + 1);
      final list = pointer.asTypedList(bytes.length + 1);
      for (int i = 0; i < bytes.length; i++) {
        list[i] = bytes[i];
      }
      list[bytes.length] = 0;
      final utf = pointer.cast<Utf8>();
      vector[index] = utf;
      pointers.add(utf);
      lengths.add(bytes.length + 1);
    }

    int result = -1;
    try {
      if (configuration != nullptr) {
        if (configure(configuration, options.length, vector) == 0) {
          result = launch(configuration);
        }
      }
      if (result == -1) {
        result = execute(options.length, vector);
      }
    } finally {
      for (int index = 0; index < pointers.length; index++) {
        final pointer = pointers[index];
        final length = lengths[index];
        pointer.cast<Uint8>().asTypedList(length).fillRange(0, length, 0);
        calloc.free(pointer);
      }
      calloc.free(vector);
    }

    return result;
  }

  int pipe() {
    if (configuration == nullptr) return -1;
    return socket(configuration);
  }

  void dispose() {
    if (configuration != nullptr) {
      clean(configuration);
      configuration = nullptr;
    }
  }

  T use<T>(T Function(Tor tor) callback) {
    try {
      return callback(this);
    } finally {
      dispose();
    }
  }
}