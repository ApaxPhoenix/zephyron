import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

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
  if (Platform.isIOS) throw UnsupportedError('iOS is not supported.');
  if (Platform.isMacOS) throw UnsupportedError('macOS is not supported.');
  if (Platform.isLinux) throw UnsupportedError('Linux is not supported.');
  if (Platform.isWindows) throw UnsupportedError('Windows is not supported.');
  if (Platform.isFuchsia) throw UnsupportedError('Fuchsia is not supported.');

  if (Platform.isAndroid) {
    try {
      return DynamicLibrary.open('libtor.so');
    } catch (_) {
      throw StateError('libtor.so not found in jniLibs.');
    }
  }

  throw UnsupportedError('Only Android is supported.');
}();

class Tor {
  final String path;
  final String host;
  final int socks;
  final int control;
  final List<String> arguments;

  Pointer<Void> configuration = nullptr;

  Tor({
    required this.path,
    this.host = '127.0.0.1',
    this.socks = 9050,
    this.control = 9051,
    this.arguments = const [],
  });

  static String get version {
    try {
      final pointer = release();
      if (pointer != nullptr) return pointer.toDartString();
    } catch (_) {}
    return 'Unknown';
  }

  static int run(List<String> arguments) {
    final options = ['tor', ...arguments];
    return using((arena) {
      final vector = arena<Pointer<Utf8>>(options.length);
      for (int index = 0; index < options.length; index++) {
        vector[index] = options[index].toNativeUtf8(allocator: arena);
      }

      try {
        final configuration = allocate();
        if (configuration != nullptr) {
          if (configure(configuration, options.length, vector) == 0) {
            final result = launch(configuration);
            clean(configuration);
            return result;
          }
          clean(configuration);
        }
      } catch (_) {}

      return execute(options.length, vector);
    });
  }

  int boot() {
    configuration = allocate();

    final options = [
      'tor',
      '--DataDirectory',
      path,
      '--SocksPort',
      '$host:$socks',
      '--ControlPort',
      '$host:$control',
      '--HiddenserviceStatisticsChecking',
      '0',
      ...arguments,
    ];

    return using((arena) {
      final vector = arena<Pointer<Utf8>>(options.length);
      for (int index = 0; index < options.length; index++) {
        vector[index] = options[index].toNativeUtf8(allocator: arena);
      }

      if (configuration != nullptr) {
        if (configure(configuration, options.length, vector) == 0) {
          return launch(configuration);
        }
      }

      return execute(options.length, vector);
    });
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