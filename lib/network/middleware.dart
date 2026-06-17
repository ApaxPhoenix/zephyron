import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:minio/minio.dart';

class NetworkMiddlewareScreen extends StatefulWidget {
  const NetworkMiddlewareScreen({super.key});

  @override
  State<NetworkMiddlewareScreen> createState() =>
      NetworkMiddlewareScreenState();
}

class NetworkMiddlewareScreenState extends State<NetworkMiddlewareScreen>
    with TickerProviderStateMixin {
  late final AnimationController animation;
  double progress = 0.0;
  String root = '';

  @override
  void initState() {
    super.initState();

    animation = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat();

    unawaited(() async {
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

        final stream = client
            .listObjectsV2('appwrite', prefix: 'map/', recursive: true)
            .timeout(const Duration(seconds: 4));

        await for (final result in stream) {
          for (final object in result.objects) {
            if (object.key != null && !object.key!.endsWith('/')) {
              final name = object.key!.substring('map/'.length);
              developer.log(
                'Found $name with ${object.size ?? 0} bytes',
                name: 'NetworkMiddlewareScreen',
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

          int pointer = 0;

          Future<void> worker() async {
            while (true) {
              final int current = pointer++;
              if (current >= items.length) break;

              final item = items[current];
              try {
                final file = File('$root/map/${item.name}');

                if (await file.exists() &&
                    (item.size == 0 || await file.length() == item.size)) {
                  received[current] = item.size;
                  if (mounted) {
                    setState(
                      () => progress =
                          0.1 +
                          ((received.fold<int>(0, (sum, bytes) => sum + bytes) /
                                  (total > 0 ? total : 1)) *
                              0.8),
                    );
                  }
                  developer.log(
                    'Skipping matching file ${item.name}',
                    name: 'NetworkMiddlewareScreen',
                  );
                  continue;
                }

                int start = 0;
                if (await file.exists()) {
                  final length = await file.length();
                  if (length < item.size) {
                    start = length;
                    developer.log(
                      'Resuming ${item.name} from byte $start',
                      name: 'NetworkMiddlewareScreen',
                    );
                  } else {
                    await file.delete();
                  }
                }

                await file.parent.create(recursive: true);
                received[current] = start;

                final data = start > 0
                    ? await client.getPartialObject('appwrite', item.key, start)
                    : await client.getObject('appwrite', item.key);

                final writer = file.openWrite(
                  mode: start > 0 ? FileMode.append : FileMode.write,
                );

                try {
                  await for (final chunk in data) {
                    writer.add(chunk);
                    received[current] += chunk.length;
                    if (mounted) {
                      setState(
                        () => progress =
                            0.1 +
                            ((received.fold<int>(
                                      0,
                                      (sum, bytes) => sum + bytes,
                                    ) /
                                    (total > 0 ? total : 1)) *
                                0.8),
                      );
                    }
                  }
                  await writer.flush();
                } finally {
                  await writer.close();
                }

                received[current] = item.size;
                if (mounted) {
                  setState(
                    () => progress =
                        0.1 +
                        ((received.fold<int>(0, (sum, bytes) => sum + bytes) /
                                (total > 0 ? total : 1)) *
                            0.8),
                  );
                }
              } catch (error, trace) {
                developer.log(
                  'Sync failed for ${item.name} due to $error',
                  error: error,
                  stackTrace: trace,
                  name: 'NetworkMiddlewareScreen',
                  level: 1000,
                );
              }
            }
          }

          await Future.wait([worker(), worker(), worker()]);
        }

        if (mounted) {
          setState(() => progress = 1.0);
          Navigator.of(
            context,
          ).pushReplacementNamed('/network', arguments: root);
        }
      } catch (error, trace) {
        developer.log(
          'Operational network failure from $error',
          error: error,
          stackTrace: trace,
          name: 'NetworkMiddlewareScreen',
          level: 1000,
        );

        try {
          if (root.isNotEmpty) {
            final directory = Directory('$root/map');
            if (await directory.exists()) {
              final entities = await directory.list(recursive: true).toList();
              if (entities.any((entity) => entity is File)) {
                developer.log(
                  'Routing to network view with local assets',
                  name: 'NetworkMiddlewareScreen',
                );
                if (mounted) {
                  Navigator.of(
                    context,
                  ).pushReplacementNamed('/network', arguments: root);
                  return;
                }
              }
            }
          }
        } catch (_) {}

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/');
        }
      }
    }());
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
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
}
