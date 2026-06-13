import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:minio/minio.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => AssetsScreenState();
}

class AssetsScreenState extends State<AssetsScreen>
    with TickerProviderStateMixin {
  late AnimationController animation;
  double progress = 0.0;
  String root = '';

  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat();

    () async {
      if (progress > 0.0) return;
      try {
        root = (await getApplicationDocumentsDirectory()).path;
        await Directory('$root/map').create(recursive: true);

        final client = Minio(
          endPoint: '10.0.2.2',
          port: 9000,
          useSSL: false,
          accessKey: 'user',
          secretKey: 'password',
        );

        final items = <({String key, String name, int size, String? hash})>[];

        await for (final result in client.listObjectsV2(
          'appwrite',
          prefix: 'map/',
          recursive: true,
        )) {
          for (final object in result.objects) {
            if (object.key != null && !object.key!.endsWith('/')) {
              final name = object.key!.substring('map/'.length);
              developer.log(
                'Found item: $name (${object.size ?? 0} bytes)',
                name: 'AssetsScreen',
              );
              items.add((
                key: object.key!,
                name: name,
                size: object.size ?? 0,
                hash: object.eTag,
              ));
            }
          }
        }

        if (items.isNotEmpty) {
          if (mounted) setState(() => progress = 0.1);

          final total = items.fold<int>(0, (sum, item) => sum + item.size);
          final received = List<int>.filled(items.length, 0);

          void update() {
            if (mounted) {
              setState(
                () => progress =
                    0.1 +
                    (received.fold<int>(0, (sum, types) => sum + types) /
                            total) *
                        0.8,
              );
            }
          }

          Future<void> download(int i) async {
            final item = items[i];
            try {
              // Updated target file path to use 'map' folder
              final file = File('$root/map/${item.name}');

              final tag = (item.hash ?? '')
                  .replaceAll('"', '')
                  .replaceAll("'", '')
                  .toLowerCase();
              final has = tag.isNotEmpty && tag.length == 32;

              if (await file.exists() &&
                  (item.size == 0 || await file.length() == item.size)) {
                if (tag.isNotEmpty && tag.length == 32) {
                  final sink = Collector<Digest>();
                  final hasher = md5.startChunkedConversion(sink);
                  await for (final chunk in file.openRead()) {
                    hasher.add(chunk);
                  }
                  hasher.close();

                  if (sink.events.isNotEmpty &&
                      sink.events.first.toString() == tag) {
                    received[i] = item.size;
                    update();
                    developer.log(
                      'Match found for ${item.name} (Skipping download).',
                      name: 'AssetsScreen',
                    );
                    return;
                  }
                } else if (item.size > 0) {
                  received[i] = item.size;
                  update();
                  return;
                }
              }

              if (await file.exists()) await file.delete();
              await file.parent.create(recursive: true);

              final writer = await file.open(mode: FileMode.write);
              try {
                final buffer = BytesBuilder(copy: false);
                await for (final chunk in await client.getObject(
                  'appwrite',
                  item.key,
                )) {
                  buffer.add(chunk);
                  received[i] += chunk.length;
                  if (buffer.length >= 5 * 1024 * 1024) {
                    await writer.writeFrom(buffer.takeBytes());
                  }
                  update();
                }
                if (buffer.length > 0) {
                  await writer.writeFrom(buffer.takeBytes());
                }
                await writer.flush();
              } finally {
                await writer.close();
              }

              if (has) {
                final sink = Collector<Digest>();
                final hasher = md5.startChunkedConversion(sink);
                await for (final chunk in file.openRead()) {
                  hasher.add(chunk);
                }
                hasher.close();
                if (sink.events.isEmpty ||
                    sink.events.first.toString() != tag) {
                  await file.delete();
                  throw Exception(
                    'Corrupt file dynamic check failed: ${item.name}',
                  );
                }
              }

              received[i] = item.size;
              update();
            } catch (error, trace) {
              developer.log(
                'Sync failure on item ${item.name}: $error',
                error: error,
                stackTrace: trace,
                name: 'AssetsScreen',
                level: 1000,
              );
            }
          }

          final pool = <Future<void>>[];
          for (var i = 0; i < items.length; i++) {
            pool.add(download(i));
            if (pool.length == 3 || i == items.length - 1) {
              await Future.wait(pool..clear());
            }
          }
        }

        if (!mounted || progress >= 1.0) return;

        while (progress < 1.0) {
          await Future.delayed(const Duration(milliseconds: 16));
          if (!mounted || progress >= 1.0) break;
          setState(() => progress = (progress + 0.02).clamp(0.0, 1.0));
        }

        if (!mounted) return;

        Navigator.of(context).pushReplacementNamed('/map');
      } catch (error, trace) {
        developer.log(
          'Assets operational error: $error',
          error: error,
          stackTrace: trace,
          name: 'AssetsScreen',
          level: 1000,
        );
        if (!mounted || progress >= 1.0) return;
        Navigator.of(context).pushReplacementNamed('/');
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final double value = progress >= 0.99
                    ? animation.value
                    : animation.value % 1.0;
                if (progress >= 0.99) {
                  return Opacity(
                    opacity: value >= 0.5
                        ? 1.0 -
                              Curves.easeOut.transform(
                                ((value - 0.5) / 0.5).clamp(0.0, 1.0),
                              )
                        : 1.0,
                    child: Transform.scale(
                      scale: value >= 0.3 && value < 0.6
                          ? Curves.easeOut.transform(
                                  ((value - 0.3) / 0.3).clamp(0.0, 1.0),
                                ) *
                                30
                          : value >= 0.6
                          ? 30.0
                          : 1.0,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }
                return SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: List.generate(4, (index) {
                      final bool left = index == 0 || index == 3;
                      final bool top = index == 0 || index == 1;
                      final bool right =
                          (index + 1) % 4 == 0 || (index + 1) % 4 == 3;
                      final bool bottom =
                          (index + 1) % 4 == 0 || (index + 1) % 4 == 1;
                      final double spread = value < 0.15
                          ? Curves.easeOut.transform(
                              (value / 0.15).clamp(0.0, 1.0),
                            )
                          : value >= 0.55
                          ? 1.0 -
                                Curves.easeIn.transform(
                                  ((value - 0.55) / 0.15).clamp(0.0, 1.0),
                                )
                          : 1.0;
                      final double orbit = value >= 0.15 && value < 0.5
                          ? Curves.easeInOut.transform(
                              ((value - 0.15) / 0.35).clamp(0.0, 1.0),
                            )
                          : 0.0;
                      final double bounce = value >= 0.55 && value < 0.65
                          ? Curves.elasticOut.transform(
                              ((value - 0.55) / 0.1).clamp(0.0, 1.0),
                            )
                          : value >= 0.65
                          ? 1.0
                          : 0.0;
                      return Transform.translate(
                        offset: Offset(
                          (left ? -20.0 : 20.0) * spread +
                              (right ? -20.0 : 20.0) * spread * orbit -
                              (left ? -20.0 : 20.0) * spread * orbit,
                          (top ? -20.0 : 20.0) * spread +
                              (bottom ? -20.0 : 20.0) * spread * orbit -
                              (top ? -20.0 : 20.0) * spread * orbit,
                        ),
                        child: Container(
                          width:
                              16.0 +
                              16.0 * (1.0 - spread) +
                              8.0 * (1.0 - spread) * bounce,
                          height:
                              16.0 +
                              16.0 * (1.0 - spread) +
                              8.0 * (1.0 - spread) * bounce,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: progress > 0.0 && progress < 1.0 ? progress : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }
}

class Collector<T> implements Sink<T> {
  final List<T> events = [];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}
