import 'dart:developer' as developer;
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
  if (Platform.isIOS) {
    developer.log(
      'Raw USB device access is restricted on iOS platforms',
      name: 'library.usb',
      level: 1000,
      stackTrace: StackTrace.current,
    );
    throw UnsupportedError('iOS blocks raw USB access.');
  }
  if (Platform.isFuchsia) {
    developer.log(
      'Raw USB device access is not supported on Fuchsia platforms',
      name: 'library.usb',
      level: 1000,
      stackTrace: StackTrace.current,
    );
    throw UnsupportedError('Fuchsia is not supported yet.');
  }

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
      () {
        final exception = StateError(
          'libusb not found on ${Platform.operatingSystem}.',
        );
        developer.log(
          'Failed to locate or load libusb dynamic library on host operating system',
          name: 'library.usb',
          level: 1000,
          error: exception,
          stackTrace: StackTrace.current,
        );
        throw exception;
      }();
}();

Pointer<Void> boot() {
  return using((arena) {
    final pointer = arena<Pointer<Void>>();
    if (initialize(pointer) != 0) {
      final exception = StateError('Failed to initialize libusb.');
      developer.log(
        'Failed to initialize libusb session context pointer',
        name: 'USB.boot',
        level: 1000,
        error: exception,
        stackTrace: StackTrace.current,
      );
      throw exception;
    }
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
        if (count < 0) {
          final exception = StateError('Failed to enumerate USB devices.');
          developer.log(
            'Failed to enumerate connected USB device list via libusb (code: $count)',
            name: 'USB.list',
            level: 1000,
            error: exception,
            stackTrace: StackTrace.current,
          );
          throw exception;
        }

        final devices = List.generate(count, (index) {
          final node = pointer.value[index];
          final descriptor = arena<Uint8>(18);
          if (describe(node, descriptor) != 0) {
            developer.log(
              'Failed to read USB device descriptor for device at index $index',
              name: 'USB.list',
              level: 900,
            );
            return null;
          }

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
      final vendorHex = vendor.toRadixString(16).padLeft(4, '0');
      final productHex = product.toRadixString(16).padLeft(4, '0');
      final exception = StateError(
        'Device 0x$vendorHex:0x$productHex not found.',
      );
      developer.log(
        'Failed to connect to USB device with VID 0x$vendorHex and PID 0x$productHex',
        name: 'USB.open',
        level: 1000,
        error: exception,
        stackTrace: StackTrace.current,
      );
      throw exception;
    }
    return USB._(context)..handle = handle;
  }

  static USB find(String name) {
    final matches = list()
        .where(
          (device) => device.product.toLowerCase().contains(name.toLowerCase()),
        )
        .toList();

    if (matches.isEmpty) {
      final exception = StateError('No device matching "$name" found.');
      developer.log(
        'USB device lookup failed: no device matching product search name "$name"',
        name: 'USB.find',
        level: 900,
        error: exception,
        stackTrace: StackTrace.current,
      );
      throw exception;
    }
    if (matches.length > 1) {
      final matchNames = matches.map((device) => device.product).join(', ');
      final exception = StateError(
        'Multiple devices match "$name": $matchNames. Be more specific.',
      );
      developer.log(
        'USB device lookup ambiguous: multiple candidate devices matched "$name" ($matchNames)',
        name: 'USB.find',
        level: 900,
        error: exception,
        stackTrace: StackTrace.current,
      );
      throw exception;
    }

    return USB.open(matches.first.vendor, matches.first.type);
  }

  List<int> pull(int endpoint, int length, {int timeout = 1000}) {
    return using((arena) {
      final buffer = arena<Uint8>(length);
      final transferred = arena<Int32>();
      final epHex = endpoint.toRadixString(16);
      if (transfer(handle, endpoint, buffer, length, transferred, timeout) <
          0) {
        final exception = StateError('Read from endpoint 0x$epHex failed.');
        developer.log(
          'Bulk read transfer failed on USB endpoint 0x$epHex',
          name: 'USB.pull',
          level: 1000,
          error: exception,
          stackTrace: StackTrace.current,
        );
        throw exception;
      }
      return List<int>.from(buffer.asTypedList(transferred.value));
    });
  }

  int push(int endpoint, List<int> bytes, {int timeout = 1000}) {
    return using((arena) {
      final buffer = arena<Uint8>(bytes.length);
      final transferred = arena<Int32>();
      final epHex = endpoint.toRadixString(16);
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
        final exception = StateError('Write to endpoint 0x$epHex failed.');
        developer.log(
          'Bulk write transfer failed on USB endpoint 0x$epHex',
          name: 'USB.push',
          level: 1000,
          error: exception,
          stackTrace: StackTrace.current,
        );
        throw exception;
      }
      return transferred.value;
    });
  }

  void dispose() {
    try {
      if (handle != nullptr) disconnect(handle);
      if (context != nullptr) terminate(context);
      handle = nullptr;
    } catch (error) {
      developer.log(
        'Failed to cleanly disconnect handles or terminate libusb context during dispose',
        name: 'USB.dispose',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  T use<T>(T Function(USB usb) callback) {
    try {
      return callback(this);
    } finally {
      dispose();
    }
  }
}
