import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dart:developer' as developer;

/// Native structure for zstd input buffer
final class InBuffer extends Struct {
  external Pointer<Uint8> source;
  @IntPtr()
  external int size;
  @IntPtr()
  external int position;
}

/// Native structure for zstd output buffer
final class OutBuffer extends Struct {
  external Pointer<Uint8> destination;
  @IntPtr()
  external int size;
  @IntPtr()
  external int position;
}

/// Zstandard compression and decompression using FFI.
///
/// Provides compression and decompression of .zst files using native zstd libraries.
/// Automatically handles platform-specific library loading based on OS and architecture.
class Zstd {
  /// Native zstd library handle
  late final DynamicLibrary library;

  /// Decompression context pointer
  Pointer<Void>? decompression;

  /// Compression context pointer
  Pointer<Void>? compression;

  /// Track if disposed to prevent use-after-free
  bool disposed = false;

  /// Loads the appropriate zstd library for the current platform.
  ///
  /// Parameters:
  ///   [path] - Path to storage directory containing zstd folder
  ///
  /// Throws:
  ///   [Exception] if platform or architecture is not supported
  ///   [Exception] if library cannot be loaded
  Zstd.load(String path) {
    try {
      developer.log('Loading zstd library', name: 'Zstd.load');

      final arch = Abi.current();
      String target;

      if (Platform.isAndroid) {
        if (arch == Abi.androidArm64) {
          target = '$path/zstd/android/arm64-v8a/libzstd.so';
        } else if (arch == Abi.androidArm) {
          target = '$path/zstd/android/armeabi-v7a/libzstd.so';
        } else if (arch == Abi.androidX64) {
          target = '$path/zstd/android/x86_64/libzstd.so';
        } else if (arch == Abi.androidIA32) {
          target = '$path/zstd/android/x86/libzstd.so';
        } else {
          developer.log(
            'Unsupported Android architecture: $arch',
            name: 'Zstd.load',
            level: 1000,
          );
          throw Exception('Unsupported Android: $arch');
        }
      } else if (Platform.isIOS) {
        if (arch == Abi.iosArm64) {
          target = '$path/zstd/ios/arm64/libzstd.a';
        } else if (arch == Abi.iosX64) {
          target = '$path/zstd/ios/simulator/libzstd.a';
        } else {
          developer.log(
            'Unsupported iOS architecture: $arch',
            name: 'Zstd.load',
            level: 1000,
          );
          throw Exception('Unsupported iOS: $arch');
        }
      } else if (Platform.isLinux) {
        if (arch == Abi.linuxX64) {
          target = '$path/zstd/linux/x86_64/libzstd.so';
        } else if (arch == Abi.linuxArm64) {
          target = '$path/zstd/linux/aarch64/libzstd.so';
        } else if (arch == Abi.linuxArm) {
          target = '$path/zstd/linux/armv7l/libzstd.so';
        } else if (arch == Abi.linuxIA32) {
          target = '$path/zstd/linux/i686/libzstd.so';
        } else {
          developer.log(
            'Unsupported Linux architecture: $arch',
            name: 'Zstd.load',
            level: 1000,
          );
          throw Exception('Unsupported Linux: $arch');
        }
      } else if (Platform.isMacOS) {
        if (arch == Abi.macosArm64) {
          target = '$path/zstd/macos/arm64/libzstd.a';
        } else if (arch == Abi.macosX64) {
          target = '$path/zstd/macos/x86_64/libzstd.a';
        } else {
          developer.log(
            'Unsupported macOS architecture: $arch',
            name: 'Zstd.load',
            level: 1000,
          );
          throw Exception('Unsupported macOS: $arch');
        }
      } else if (Platform.isWindows) {
        if (arch == Abi.windowsX64) {
          target = '$path/zstd/windows/x64/libzstd.dll';
        } else if (arch == Abi.windowsIA32) {
          target = '$path/zstd/windows/x86/libzstd.dll';
        } else if (arch == Abi.windowsArm64) {
          target = '$path/zstd/windows/arm64/libzstd.dll';
        } else {
          developer.log(
            'Unsupported Windows architecture: $arch',
            name: 'Zstd.load',
            level: 1000,
          );
          throw Exception('Unsupported Windows: $arch');
        }
      } else {
        developer.log(
          'Unsupported platform: ${Platform.operatingSystem}',
          name: 'Zstd.load',
          level: 1000,
        );
        throw Exception('Unsupported platform');
      }

      developer.log('Target library: $target', name: 'Zstd.load');

      if (!File(target).existsSync()) {
        developer.log(
          'Library not found: $target',
          name: 'Zstd.load',
          level: 1000,
        );
        throw Exception('Library not found: $target');
      }

      library = DynamicLibrary.open(target);
      developer.log('Library loaded successfully', name: 'Zstd.load');

      final create = library
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'ZSTD_createDCtx',
          );

      decompression = create();
      if (decompression == nullptr) {
        developer.log(
          'Failed to create decompression context',
          name: 'Zstd.load',
          level: 1000,
        );
        throw Exception('Failed to create decompression context');
      }

      developer.log('Decompression context created', name: 'Zstd.load');

      final make = library
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'ZSTD_createCCtx',
          );

      compression = make();
      if (compression == nullptr) {
        developer.log(
          'Failed to create compression context',
          name: 'Zstd.load',
          level: 1000,
        );
        throw Exception('Failed to create compression context');
      }

      developer.log('Compression context created', name: 'Zstd.load');
      developer.log('Zstd initialized successfully', name: 'Zstd.load');
    } catch (error) {
      developer.log(
        'Error loading zstd: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'Zstd.load',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Decompresses a .zst file to an output file using streaming.
  ///
  /// Reads and decompresses the file in chunks to avoid memory issues.
  ///
  /// Parameters:
  ///   [input] - Path to compressed .zst file
  ///   [output] - Path where decompressed file will be written
  ///
  /// Throws:
  ///   [StateError] if Zstd has been disposed
  ///   [Exception] if decompression fails or files cannot be accessed
  Future<void> decompress(String input, String output) async {
    try {
      developer.log('Starting decompression', name: 'Zstd.decompress');
      developer.log('Input: $input', name: 'Zstd.decompress');
      developer.log('Output: $output', name: 'Zstd.decompress');

      if (disposed) {
        developer.log(
          'Cannot decompress: instance disposed',
          name: 'Zstd.decompress',
          level: 1000,
        );
        throw StateError('Instance disposed');
      }

      if (!await File(input).exists()) {
        developer.log(
          'Input file not found: $input',
          name: 'Zstd.decompress',
          level: 1000,
        );
        throw Exception('Input not found: $input');
      }

      RandomAccessFile? source;
      RandomAccessFile? target;
      Pointer<Uint8>? reader;
      Pointer<Uint8>? writer;

      try {
        source = await File(input).open(mode: FileMode.read);
        target = await File(output).open(mode: FileMode.write);

        // Get recommended buffer sizes from zstd
        final capacity = library
            .lookupFunction<IntPtr Function(), int Function()>(
              'ZSTD_DStreamInSize',
            )();

        final space = library.lookupFunction<IntPtr Function(), int Function()>(
          'ZSTD_DStreamOutSize',
        )();

        developer.log(
          'Buffer sizes: input=$capacity, output=$space',
          name: 'Zstd.decompress',
        );

        reader = calloc<Uint8>(capacity);
        writer = calloc<Uint8>(space);

        int total = 0;
        int written = 0;

        while (true) {
          final amount = await source.readInto(reader.asTypedList(capacity));
          if (amount == 0) break;
          total += amount;

          int offset = 0;
          while (offset < amount) {
            // Create input structure for this chunk
            final incoming = calloc<InBuffer>();
            final outgoing = calloc<OutBuffer>();

            try {
              incoming.ref.source = reader + offset;
              incoming.ref.size = amount - offset;
              incoming.ref.position = 0;

              outgoing.ref.destination = writer;
              outgoing.ref.size = space;
              outgoing.ref.position = 0;

              // Decompress stream chunk
              final stream = library
                  .lookupFunction<
                    IntPtr Function(
                      Pointer<Void>,
                      Pointer<OutBuffer>,
                      Pointer<InBuffer>,
                    ),
                    int Function(
                      Pointer<Void>,
                      Pointer<OutBuffer>,
                      Pointer<InBuffer>,
                    )
                  >('ZSTD_decompressStream');

              final result = stream(decompression!, outgoing, incoming);

              // Check for errors
              final error = library
                  .lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
                    'ZSTD_isError',
                  );

              if (error(result) != 0) {
                final name = library
                    .lookupFunction<
                      Pointer<Utf8> Function(IntPtr),
                      Pointer<Utf8> Function(int)
                    >('ZSTD_getErrorName');

                final message = name(result).toDartString();
                developer.log(
                  'Decompression stream error: $message',
                  name: 'Zstd.decompress',
                  level: 1000,
                );
                throw Exception('Zstd error: $message');
              }

              // Write decompressed data
              if (outgoing.ref.position > 0) {
                await target.writeFrom(
                  writer.asTypedList(outgoing.ref.position),
                );
                written += outgoing.ref.position;
              }

              offset += incoming.ref.position;

              // Result of 0 indicates end of frame
              if (result == 0) {
                developer.log(
                  'Decompression stream complete',
                  name: 'Zstd.decompress',
                );
                break;
              }
            } finally {
              // Always free buffers
              calloc.free(incoming);
              calloc.free(outgoing);
            }
          }
        }

        developer.log(
          'Decompressed $total bytes to $written bytes',
          name: 'Zstd.decompress',
        );
      } finally {
        // Guaranteed cleanup
        if (reader != null) calloc.free(reader);
        if (writer != null) calloc.free(writer);
        await source?.close();
        await target?.close();
      }
    } catch (error) {
      developer.log(
        'Error during decompression: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'Zstd.decompress',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Compresses a file to .zst format using streaming.
  ///
  /// Reads and compresses the file in chunks to avoid memory issues.
  ///
  /// Parameters:
  ///   [input] - Path to file to compress
  ///   [output] - Path where compressed .zst file will be written
  ///   [level] - Compression level from 1 to 22, default is 3
  ///
  /// Throws:
  ///   [StateError] if Zstd has been disposed
  ///   [Exception] if compression fails or files cannot be accessed
  Future<void> compress(String input, String output, {int level = 3}) async {
    try {
      developer.log('Starting compression', name: 'Zstd.compress');
      developer.log('Input: $input', name: 'Zstd.compress');
      developer.log('Output: $output', name: 'Zstd.compress');
      developer.log('Level: $level', name: 'Zstd.compress');

      if (disposed) {
        developer.log(
          'Cannot compress: instance disposed',
          name: 'Zstd.compress',
          level: 1000,
        );
        throw StateError('Instance disposed');
      }

      if (level < 1 || level > 22) {
        developer.log(
          'Invalid compression level: $level',
          name: 'Zstd.compress',
          level: 1000,
        );
        throw Exception('Level must be 1-22');
      }

      if (!await File(input).exists()) {
        developer.log(
          'Input file not found: $input',
          name: 'Zstd.compress',
          level: 1000,
        );
        throw Exception('Input not found: $input');
      }

      RandomAccessFile? source;
      RandomAccessFile? target;
      Pointer<Uint8>? reader;
      Pointer<Uint8>? writer;

      try {
        source = await File(input).open(mode: FileMode.read);
        target = await File(output).open(mode: FileMode.write);

        // Get recommended buffer sizes from zstd
        final capacity = library
            .lookupFunction<IntPtr Function(), int Function()>(
              'ZSTD_CStreamInSize',
            )();

        final space = library.lookupFunction<IntPtr Function(), int Function()>(
          'ZSTD_CStreamOutSize',
        )();

        developer.log(
          'Buffer sizes: input=$capacity, output=$space',
          name: 'Zstd.compress',
        );

        reader = calloc<Uint8>(capacity);
        writer = calloc<Uint8>(space);

        // Set compression level
        final parameter = library
            .lookupFunction<
              IntPtr Function(Pointer<Void>, Int32, Int32),
              int Function(Pointer<Void>, int, int)
            >('ZSTD_CCtx_setParameter');

        // 100 is ZSTD_c_compressionLevel constant
        parameter(compression!, 100, level);
        developer.log('Compression level set', name: 'Zstd.compress');

        int total = 0;
        int written = 0;

        while (true) {
          final amount = await source.readInto(reader.asTypedList(capacity));
          // 2 = ZSTD_e_end, 0 = ZSTD_e_continue
          final mode = amount == 0 ? 2 : 0;
          total += amount;

          // Create input structure for this chunk
          final incoming = calloc<InBuffer>();
          try {
            incoming.ref.source = reader;
            incoming.ref.size = amount;
            incoming.ref.position = 0;

            int finished = 0;
            while (finished == 0) {
              final outgoing = calloc<OutBuffer>();
              try {
                outgoing.ref.destination = writer;
                outgoing.ref.size = space;
                outgoing.ref.position = 0;

                // Compress stream chunk
                final stream = library
                    .lookupFunction<
                      IntPtr Function(
                        Pointer<Void>,
                        Pointer<OutBuffer>,
                        Pointer<InBuffer>,
                        Int32,
                      ),
                      int Function(
                        Pointer<Void>,
                        Pointer<OutBuffer>,
                        Pointer<InBuffer>,
                        int,
                      )
                    >('ZSTD_compressStream2');

                final remaining = stream(
                  compression!,
                  outgoing,
                  incoming,
                  mode,
                );

                // Check for errors
                final error = library
                    .lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
                      'ZSTD_isError',
                    );

                if (error(remaining) != 0) {
                  final name = library
                      .lookupFunction<
                        Pointer<Utf8> Function(IntPtr),
                        Pointer<Utf8> Function(int)
                      >('ZSTD_getErrorName');

                  final message = name(remaining).toDartString();
                  developer.log(
                    'Compression stream error: $message',
                    name: 'Zstd.compress',
                    level: 1000,
                  );
                  throw Exception('Zstd error: $message');
                }

                // Write compressed data
                if (outgoing.ref.position > 0) {
                  await target.writeFrom(
                    writer.asTypedList(outgoing.ref.position),
                  );
                  written += outgoing.ref.position;
                }

                // Check if compression is finished
                if (mode == 2 && remaining == 0) finished = 1;
                if (incoming.ref.position >= incoming.ref.size && mode == 0)
                  break;
              } finally {
                calloc.free(outgoing);
              }
            }
          } finally {
            calloc.free(incoming);
          }

          if (amount == 0) break;
        }

        developer.log(
          'Compressed $total bytes to $written bytes',
          name: 'Zstd.compress',
        );
      } finally {
        // Guaranteed cleanup
        if (reader != null) calloc.free(reader);
        if (writer != null) calloc.free(writer);
        await source?.close();
        await target?.close();
      }
    } catch (error) {
      developer.log(
        'Error during compression: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'Zstd.compress',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Releases native resources.
  ///
  /// Frees the decompression and compression contexts and cleans up memory.
  /// Should be called when finished with compression or decompression operations.
  void dispose() {
    try {
      if (disposed) return;

      developer.log('Disposing zstd resources', name: 'Zstd.dispose');

      // Free decompression context if exists
      if (decompression != null) {
        final free = library
            .lookupFunction<
              IntPtr Function(Pointer<Void>),
              int Function(Pointer<Void>)
            >('ZSTD_freeDCtx');
        free(decompression!);
        decompression = null;
        developer.log('Decompression context freed', name: 'Zstd.dispose');
      }

      // Free compression context if exists
      if (compression != null) {
        final free = library
            .lookupFunction<
              IntPtr Function(Pointer<Void>),
              int Function(Pointer<Void>)
            >('ZSTD_freeCCtx');
        free(compression!);
        compression = null;
        developer.log('Compression context freed', name: 'Zstd.dispose');
      }

      disposed = true;
      developer.log('Zstd disposed successfully', name: 'Zstd.dispose');
    } catch (error) {
      developer.log(
        'Error during dispose: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'Zstd.dispose',
        level: 1000,
      );
    }
  }
}
