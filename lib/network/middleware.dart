import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
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
  final ValueNotifier<double> progress = ValueNotifier<double>(-1.0);

  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat();

    unawaited(() async {
      if (progress.value > 0.0) return;

      bool completedAll = false;

      try {
        final directory = await getApplicationDocumentsDirectory();
        final path = directory.path;
        await Directory('$path/map').create(recursive: true);

        final client = Minio(
          endPoint: '10.0.2.2',
          port: 9000,
          useSSL: false,
          accessKey: 'user',
          secretKey: 'password',
        );

        final stream = client
            .listObjectsV2('appwrite', prefix: 'map/', recursive: true)
            .timeout(const Duration(seconds: 10));

        int count = 0;
        progress.value = -1.0;

        await for (final result in stream) {
          for (final object in result.objects) {
            if (object.key != null && !object.key!.endsWith('/')) {
              final name = object.key!.substring('map/'.length);
              final size = object.size ?? 0;

              developer.log(
                'Processing $name with $size bytes',
                name: 'NetworkMiddlewareScreen.objects',
              );

              try {
                final file = File('$path/map/$name');

                if (await file.exists() &&
                    (size == 0 || await file.length() == size)) {
                  developer.log(
                    'Skipping matching file $name',
                    name: 'NetworkMiddlewareScreen.worker',
                  );
                  continue;
                }

                int start = 0;
                if (await file.exists()) {
                  final length = await file.length();
                  if (length < size) {
                    start = length;
                    developer.log(
                      'Resuming $name from byte $start',
                      name: 'NetworkMiddlewareScreen.resume',
                    );
                  } else {
                    await file.delete();
                  }
                }

                await file.parent.create(recursive: true);

                final data = start > 0
                    ? await client.getPartialObject('appwrite', object.key!, start)
                    : await client.getObject('appwrite', object.key!);

                final access = await file.open(
                  mode: start > 0 ? FileMode.append : FileMode.write,
                );

                try {
                  await for (final chunk in data) {
                    await access.writeFrom(chunk);
                  }
                } finally {
                  await access.close();
                }

                count++;

                double fake = 0.1 + (count * 0.005);
                if (fake > 0.9) fake = 0.9;
                progress.value = fake;

              } catch (error, trace) {
                developer.log(
                  'Sync failed for $name due to $error',
                  error: error,
                  stackTrace: trace,
                  name: 'NetworkMiddlewareScreen.sync',
                  level: 1000,
                );
              }
            }
          }
        }

        completedAll = true;
      } catch (error, trace) {
        developer.log(
          'Operational network failure from $error',
          error: error,
          stackTrace: trace,
          name: 'NetworkMiddlewareScreen.failure',
          level: 1000,
        );
      }

      if (!mounted) return;

      if (completedAll) {
        progress.value = 1.0;
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/network');
        }
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final path = directory.path;
        final target = Directory('$path/map');

        if (await target.exists() &&
            (await target.list(recursive: true).toList()).any((entity) => entity is File)) {
          developer.log(
            'Routing to network view with local assets',
            name: 'NetworkMiddlewareScreen.fallback',
          );
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/network');
          }
        } else {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/');
          }
        }
      }
    }());
  }

  @override
  void dispose() {
    animation.dispose();
    progress.dispose();
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
                final current = progress.value;
                final double tick = current >= 0.99
                    ? animation.value
                    : animation.value % 1.0;

                if (current >= 0.99) {
                  return Opacity(
                    opacity: tick >= 0.5
                        ? 1.0 - Curves.easeOut.transform(((tick - 0.5) / 0.5).clamp(0.0, 1.0))
                        : 1.0,
                    child: Transform.scale(
                      scale: tick >= 0.3 && tick < 0.6
                          ? Curves.easeOut.transform(((tick - 0.3) / 0.3).clamp(0.0, 1.0)) * 30
                          : tick >= 0.6 ? 30.0 : 1.0,
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
                      final bool right = (index + 1) % 4 == 0 || (index + 1) % 4 == 3;
                      final bool bottom = (index + 1) % 4 == 0 || (index + 1) % 4 == 1;

                      final double spread = tick < 0.15
                          ? Curves.easeOut.transform((tick / 0.15).clamp(0.0, 1.0))
                          : tick >= 0.55
                          ? 1.0 - Curves.easeIn.transform(((tick - 0.55) / 0.15).clamp(0.0, 1.0))
                          : 1.0;
                      final double orbit = tick >= 0.15 && tick < 0.5
                          ? Curves.easeInOut.transform(((tick - 0.15) / 0.35).clamp(0.0, 1.0))
                          : 0.0;
                      final double bounce = tick >= 0.55 && tick < 0.65
                          ? Curves.elasticOut.transform(((tick - 0.55) / 0.1).clamp(0.0, 1.0))
                          : tick >= 0.65 ? 1.0 : 0.0;

                      return Transform.translate(
                        offset: Offset(
                          (left ? -20.0 : 20.0) * spread + (right ? -20.0 : 20.0) * spread * orbit - (left ? -20.0 : 20.0) * spread * orbit,
                          (top ? -20.0 : 20.0) * spread + (bottom ? -20.0 : 20.0) * spread * orbit - (top ? -20.0 : 20.0) * spread * orbit,
                        ),
                        child: Container(
                          width: 16.0 + 16.0 * (1.0 - spread) + 8.0 * (1.0 - spread) * bounce,
                          height: 16.0 + 16.0 * (1.0 - spread) + 8.0 * (1.0 - spread) * bounce,
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
            child: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value >= 0.0 && value <= 1.0 ? value : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}