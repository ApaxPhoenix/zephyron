import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:zephyron/models/device.dart';

@Native<Int32 Function(Pointer<Pointer<Void>>)>(symbol: 'libusb_init')
external int initialize(Pointer<Pointer<Void>> context);

@Native<Void Function(Pointer<Void>)>(symbol: 'libusb_exit')
external void terminate(Pointer<Void> context);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Pointer<Void>>>)>(
  symbol: 'libusb_get_device_list',
)
external int enumerate(
  Pointer<Void> context,
  Pointer<Pointer<Pointer<Void>>> devices,
);

@Native<Void Function(Pointer<Pointer<Void>>, Int32)>(
  symbol: 'libusb_free_device_list',
)
external void release(Pointer<Pointer<Void>> devices, int unref);

@Native<Pointer<Void> Function(Pointer<Void>, Uint16, Uint16)>(
  symbol: 'libusb_open_device_with_vid_pid',
)
external Pointer<Void> connect(Pointer<Void> context, int vid, int pid);

@Native<Void Function(Pointer<Void>)>(symbol: 'libusb_close')
external void disconnect(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>)>(
  symbol: 'libusb_get_device_descriptor',
)
external int describe(Pointer<Void> device, Pointer<Uint8> output);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Void>,
    Uint8,
    Uint16,
    Pointer<Uint8>,
    Int32,
  )
>(symbol: 'libusb_get_string_descriptor_ascii')
external int label(
  Pointer<Void> context,
  Pointer<Void> handle,
  int index,
  int lang,
  Pointer<Uint8> buffer,
  int length,
);

@Native<Uint8 Function(Pointer<Void>)>(symbol: 'libusb_get_bus_number')
external int bus(Pointer<Void> device);

@Native<Uint8 Function(Pointer<Void>)>(symbol: 'libusb_get_device_address')
external int address(Pointer<Void> device);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'libusb_get_device_speed')
external int speed(Pointer<Void> device);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>)>(
  symbol: 'libusb_open',
)
external int attach(Pointer<Void> device, Pointer<Pointer<Void>> output);

@Native<
  Int32 Function(
    Pointer<Void>,
    Uint8,
    Pointer<Uint8>,
    Int32,
    Pointer<Int32>,
    Uint32,
  )
>(symbol: 'libusb_bulk_transfer')
external int transfer(
  Pointer<Void> handle,
  int endpoint,
  Pointer<Uint8> buffer,
  int length,
  Pointer<Int32> sent,
  int timeout,
);

final DynamicLibrary library = () {
  if (Platform.isIOS) throw UnsupportedError('iOS blocks raw USB access.');
  if (Platform.isFuchsia)
    throw UnsupportedError('Fuchsia is not supported yet.');

  return [
        if (Platform.isWindows) ...['libusb-1.0.dll', 'libusb-1.0-0.dll'],
        if (Platform.isLinux || Platform.isAndroid) ...[
          'libusb-1.0.so',
          'libusb-1.0.so.0',
          '/usr/lib/x86_64-linux-gnu/libusb-1.0.so.0',
          '/usr/lib/aarch64-linux-gnu/libusb-1.0.so.0',
          '/usr/local/lib/libusb-1.0.so',
        ],
        if (Platform.isMacOS) ...[
          'libusb-1.0.dylib',
          '/opt/homebrew/lib/libusb-1.0.dylib',
          '/usr/local/lib/libusb-1.0.dylib',
          '/usr/local/opt/libusb/lib/libusb-1.0.dylib',
        ],
      ].fold<DynamicLibrary?>(null, (current, path) {
        if (current != null) return current;
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          return null;
        }
      }) ??
      (throw StateError('libusb not found on ${Platform.operatingSystem}.'));
}();

Pointer<Void> boot() {
  return using((arena) {
    final pointer = arena<Pointer<Void>>();
    if (initialize(pointer) != 0)
      throw StateError('Failed to initialize libusb.');
    return pointer.value;
  });
}

class USB {
  final Pointer<Void> context;
  Pointer<Void> handle = nullptr;

  USB._(this.context);

  static List<Device> list() {
    final context = boot();
    try {
      return using((arena) {
        final pointer = arena<Pointer<Pointer<Void>>>();
        final count = enumerate(context, pointer);
        if (count < 0) throw StateError('Failed to enumerate USB devices.');

        final devices = List.generate(count, (index) {
          final node = pointer.value[index];
          final descriptor = arena<Uint8>(18);
          if (describe(node, descriptor) != 0) return null;

          final opened = arena<Pointer<Void>>();
          final attached = attach(node, opened) == 0;

          String? read(int stringIndex) {
            if (!attached || stringIndex == 0) return null;
            return using((scope) {
              final buffer = scope<Uint8>(256);
              final length = label(
                context,
                opened.value,
                stringIndex,
                0x0409,
                buffer,
                256,
              );
              if (length < 0) return null;
              return String.fromCharCodes(buffer.asTypedList(length));
            });
          }

          if (attached) disconnect(opened.value);

          return Device(
            vendor: descriptor[8] | (descriptor[9] << 8),
            type: descriptor[10] | (descriptor[11] << 8),
            classification: descriptor[3],
            bus: bus(node),
            address: address(node),
            speed: speed(node),
            manufacturer: read(descriptor[14]) ?? '',
            product: read(descriptor[15]) ?? '',
            serial: read(descriptor[16]) ?? '',
          );
        }).whereType<Device>().toList();

        release(pointer.value, 1);
        return devices;
      });
    } finally {
      terminate(context);
    }
  }

  static USB open(int vendor, int product) {
    final context = boot();
    final handle = connect(context, vendor, product);
    if (handle == nullptr) {
      terminate(context);
      throw StateError(
        'Device 0x${vendor.toRadixString(16).padLeft(4, '0')}:'
        '0x${product.toRadixString(16).padLeft(4, '0')} not found.',
      );
    }
    return USB._(context)..handle = handle;
  }

  static USB find(String name) {
    final matches = list()
        .where(
          (device) => device.product.toLowerCase().contains(name.toLowerCase()),
        )
        .toList();

    if (matches.isEmpty) throw StateError('No device matching "$name" found.');
    if (matches.length > 1) {
      throw StateError(
        'Multiple devices match "$name": ${matches.map((device) => device.product).join(', ')}. Be more specific.',
      );
    }

    return USB.open(matches.first.vendor, matches.first.type);
  }

  List<int> pull(int endpoint, int length, {int timeout = 1000}) {
    return using((arena) {
      final buffer = arena<Uint8>(length);
      final transferred = arena<Int32>();
      if (transfer(handle, endpoint, buffer, length, transferred, timeout) <
          0) {
        throw StateError(
          'Read from endpoint 0x${endpoint.toRadixString(16)} failed.',
        );
      }
      return List<int>.from(buffer.asTypedList(transferred.value));
    });
  }

  int push(int endpoint, List<int> bytes, {int timeout = 1000}) {
    return using((arena) {
      final buffer = arena<Uint8>(bytes.length);
      final transferred = arena<Int32>();
      for (int index = 0; index < bytes.length; index++) {
        buffer[index] = bytes[index];
      }
      if (transfer(
            handle,
            endpoint,
            buffer,
            bytes.length,
            transferred,
            timeout,
          ) <
          0) {
        throw StateError(
          'Write to endpoint 0x${endpoint.toRadixString(16)} failed.',
        );
      }
      return transferred.value;
    });
  }

  void dispose() {
    if (handle != nullptr) disconnect(handle);
    if (context != nullptr) terminate(context);
    handle = nullptr;
  }

  T use<T>(T Function(USB usb) callback) {
    try {
      return callback(this);
    } finally {
      dispose();
    }
  }
}
