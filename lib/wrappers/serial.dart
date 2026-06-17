import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

@Native<Int32 Function(Pointer<Pointer<Void>>, Pointer<Utf8>)>(
  symbol: 'sp_get_port_by_name',
)
external int resolve(Pointer<Pointer<Void>> port, Pointer<Utf8> name);

@Native<Int32 Function(Pointer<Void>, Int32)>(symbol: 'sp_open')
external int launch(Pointer<Void> port, int mode);

@Native<Void Function(Pointer<Void>)>(symbol: 'sp_close')
external void close(Pointer<Void> port);

@Native<Void Function(Pointer<Void>)>(symbol: 'sp_free_port')
external void free(Pointer<Void> port);

@Native<Int32 Function(Pointer<Pointer<Pointer<Void>>>)>(
  symbol: 'sp_list_ports',
)
external int enumerate(Pointer<Pointer<Pointer<Void>>> ports);

@Native<Void Function(Pointer<Pointer<Void>>)>(symbol: 'sp_free_port_list')
external void sweep(Pointer<Pointer<Void>> ports);

@Native<Pointer<Utf8> Function(Pointer<Void>)>(symbol: 'sp_get_port_name')
external Pointer<Utf8> label(Pointer<Void> port);

@Native<Pointer<Utf8> Function(Pointer<Void>)>(
  symbol: 'sp_get_port_description',
)
external Pointer<Utf8> describe(Pointer<Void> port);

@Native<Int32 Function(Pointer<Pointer<Void>>)>(symbol: 'sp_new_config')
external int allocate(Pointer<Pointer<Void>> output);

@Native<Void Function(Pointer<Void>)>(symbol: 'sp_free_config')
external void clean(Pointer<Void> config);

@Native<Int32 Function(Pointer<Void>, Pointer<Void>)>(symbol: 'sp_set_config')
external int apply(Pointer<Void> port, Pointer<Void> config);

@Native<Int32 Function(Pointer<Void>, Int32)>(symbol: 'sp_set_config_baudrate')
external int baud(Pointer<Void> config, int rate);

@Native<Int32 Function(Pointer<Void>, Int32)>(symbol: 'sp_set_config_bits')
external int bits(Pointer<Void> config, int count);

@Native<Int32 Function(Pointer<Void>, Int32)>(symbol: 'sp_set_config_stopbits')
external int stop(Pointer<Void> config, int count);

@Native<Int32 Function(Pointer<Void>, Int32)>(symbol: 'sp_set_config_parity')
external int parity(Pointer<Void> config, int mode);

@Native<Int32 Function(Pointer<Void>, Pointer<Void>, Size, Uint32)>(
  symbol: 'sp_blocking_read',
)
external int recv(
  Pointer<Void> port,
  Pointer<Void> buffer,
  int length,
  int timeout,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Void>, Size, Uint32)>(
  symbol: 'sp_blocking_write',
)
external int send(
  Pointer<Void> port,
  Pointer<Void> buffer,
  int length,
  int timeout,
);

@Native<Pointer<Utf8> Function()>(symbol: 'sp_last_error_message')
external Pointer<Utf8> error();

final DynamicLibrary library = () {
  if (Platform.isIOS) throw UnsupportedError('iOS blocks raw serial access.');
  if (Platform.isFuchsia) {
    throw UnsupportedError('Fuchsia is not supported yet.');
  }

  return [
        if (Platform.isWindows) ...['libserialport-0.dll', 'libserialport.dll'],
        if (Platform.isLinux || Platform.isAndroid) ...[
          'libserialport.so',
          'libserialport.so.0',
          '/usr/local/lib/libserialport.so',
          '/usr/lib/x86_64-linux-gnu/libserialport.so.0',
        ],
        if (Platform.isMacOS) ...[
          'libserialport.dylib',
          '/opt/homebrew/lib/libserialport.dylib',
          '/usr/local/lib/libserialport.dylib',
        ],
      ].fold<DynamicLibrary?>(null, (current, path) {
        if (current != null) return current;
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          return null;
        }
      }) ??
      (throw StateError(
        'libserialport not found on ${Platform.operatingSystem}.\n'
        '  Linux  : sudo apt install libserialport-dev\n'
        '  macOS  : brew install libserialport\n'
        '  Windows: https://sigrok.org/wiki/Libserialport',
      ));
}();

class Serial {
  final Pointer<Void> port;
  Pointer<Void> config = nullptr;

  Serial._(this.port);

  static List<Map<String, String>> list() {
    return using((arena) {
      final pointer = arena<Pointer<Pointer<Void>>>();
      if (enumerate(pointer) != 0) return [];

      final ports = <Map<String, String>>[];
      int index = 0;
      while (pointer.value[index] != nullptr) {
        ports.add({
          'name': label(pointer.value[index]).toDartString(),
          'description': describe(pointer.value[index]).toDartString(),
        });
        index++;
      }

      sweep(pointer.value);
      return ports;
    });
  }

  static Serial open(String path, {int rate = 9600}) {
    return using((arena) {
      final pointer = arena<Pointer<Void>>();
      if (resolve(pointer, path.toNativeUtf8(allocator: arena)) != 0) {
        throw StateError('Port $path not found: ${error().toDartString()}');
      }

      final port = pointer.value;
      if (launch(port, 3) != 0) {
        throw StateError('Open failed: ${error().toDartString()}');
      }

      final setup = arena<Pointer<Void>>();
      if (allocate(setup) != 0) {
        throw StateError('Config failed: ${error().toDartString()}');
      }

      baud(setup.value, rate);
      bits(setup.value, 8);
      stop(setup.value, 1);
      parity(setup.value, 0);

      if (apply(port, setup.value) != 0) {
        throw StateError('Apply failed: ${error().toDartString()}');
      }

      return Serial._(port)..config = setup.value;
    });
  }

  static Serial find(String name, {int rate = 9600}) {
    final matches = list()
        .where(
          (port) =>
              port['name']!.toLowerCase().contains(name.toLowerCase()) ||
              port['description']!.toLowerCase().contains(name.toLowerCase()),
        )
        .toList();

    if (matches.isEmpty) throw StateError('No port matching "$name" found.');
    if (matches.length > 1) {
      throw StateError(
        'Multiple ports match "$name": ${matches.map((port) => port['name']).join(', ')}. Be more specific.',
      );
    }

    return Serial.open(matches.first['name']!, rate: rate);
  }

  int push(List<int> bytes, {int timeout = 1000}) {
    return using((arena) {
      final buffer = arena<Uint8>(bytes.length);
      for (int index = 0; index < bytes.length; index++) {
        buffer[index] = bytes[index];
      }
      final sent = send(port, buffer.cast(), bytes.length, timeout);
      if (sent < 0) throw StateError('Write failed: ${error().toDartString()}');
      return sent;
    });
  }

  List<int> pull(int length, {int timeout = 1000}) {
    return using((arena) {
      final buffer = arena<Uint8>(length);
      final count = recv(port, buffer.cast(), length, timeout);
      if (count < 0) throw StateError('Read failed: ${error().toDartString()}');
      return List<int>.from(buffer.asTypedList(count));
    });
  }

  void dispose() {
    if (port != nullptr) {
      close(port);
      free(port);
    }
    if (config != nullptr) clean(config);
    config = nullptr;
  }

  T use<T>(T Function(Serial serial) callback) {
    try {
      return callback(this);
    } finally {
      dispose();
    }
  }
}
