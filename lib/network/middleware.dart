import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/main.dart';

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
    try {
      animation = AnimationController(
        duration: const Duration(seconds: 5),
        vsync: this,
      )..repeat();
    } catch (error) {
      developer.log(
        'Failed to initialize layout animation loops: $error',
        name: 'NetworkMiddlewareScreen.setup',
        error: error,
        stackTrace: StackTrace.current,
      );
    }

    unawaited(() async {
      try {
        if (!(progress.value > 0.0)) {
          progress.value = 0.0;
          final directory = await getApplicationDocumentsDirectory();
          await Directory('${directory.path}/map').create(recursive: true);

          final stream = bucket
              .listObjectsV2('appwrite', prefix: 'map/', recursive: true)
              .timeout(const Duration(seconds: 10));

          await for (final result in stream) {
            final objects = result.objects
                .where((object) => object.key != null && !object.key!.endsWith("/"))
                .toList();

            await Future.wait(objects.asMap().entries.map((entry) async {
              final index = entry.key;
              final object = entry.value;
              final name = object.key!.substring("/map".length);
              final size = object.size ?? 0;

              try {
                final file = File('${directory.path}/map/$name');
                final exists = await file.exists();
                int offset = 0;

                if (exists) {
                  final length = await file.length();
                  if (size == 0 || length == size) {
                    return;
                  }
                  if (length >= size) {
                    await file.delete();
                  } else {
                    offset = length;
                  }
                }

                final data = offset > 0
                    ? await bucket.getPartialObject('appwrite', object.key!, offset)
                    : await bucket.getObject('appwrite', object.key!);

                final sink = file.openWrite(
                  mode: offset > 0 ? FileMode.append : FileMode.write,
                );

                try {
                  await sink.addStream(data);
                } finally {
                  await sink.close();
                }

                progress.value = (0.1 + ((index + 1) * 0.005)).clamp(0.0, 0.9);
              } catch (error) {
                developer.log(
                  'Downstream failed for $name due to $error',
                  error: error,
                  stackTrace: StackTrace.current,
                  name: 'NetworkMiddlewareScreen.sync',
                  level: 1000,
                );
              }
            }));
          }
          progress.value = 1.0;
        }
      } catch (error, stackTrace) {
        developer.log(
          'Synchronization cycle failed unexpectedly: $error',
          error: error,
          stackTrace: stackTrace,
          name: 'NetworkMiddlewareScreen.synchronization',
        );
      }

      if (mounted) {
        try {
          if (progress.value == 1.0) {
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/network',
                    (route) => false,
              );
            }
          } else {
            final directory = await getApplicationDocumentsDirectory();
            final target = Directory('${directory.path}/map');
            if (await target.exists() && await target.list(recursive: true).any((entity) => entity is File)) {
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/network',
                      (route) => false,
                );
              }
            } else {
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/',
                      (route) => false,
                );
              }
            }
          }
        } catch (error, stackTrace) {
          if (mounted) {
            developer.log(
              'Navigation fallback routing execution failed: $error',
              error: error,
              stackTrace: stackTrace,
              name: 'NetworkMiddlewareScreen.routing',
            );
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/',
                  (route) => false,
            );
          }
        }
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        body: Stack(
          children: [
            Center(
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  try {
                    final current = progress.value;
                    final double tick = current >= 0.99
                        ? animation.value
                        : animation.value % 1.0;

                    if (current >= 0.99) {
                      return Opacity(
                        opacity: tick >= 0.5
                            ? 1.0 -
                            Curves.easeOut.transform(
                              ((tick - 0.5) / 0.5).clamp(0.0, 1.0),
                            )
                            : 1.0,
                        child: Transform.scale(
                          scale: tick >= 0.3 && tick < 0.6
                              ? Curves.easeOut.transform(
                            ((tick - 0.3) / 0.3).clamp(0.0, 1.0),
                          ) *
                              30
                              : tick >= 0.6
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

                          final double spread = tick < 0.15
                              ? Curves.easeOut.transform(
                            (tick / 0.15).clamp(0.0, 1.0),
                          )
                              : tick >= 0.55
                              ? 1.0 -
                              Curves.easeIn.transform(
                                ((tick - 0.55) / 0.15).clamp(0.0, 1.0),
                              )
                              : 1.0;
                          final double orbit = tick >= 0.15 && tick < 0.5
                              ? Curves.easeInOut.transform(
                            ((tick - 0.15) / 0.35).clamp(0.0, 1.0),
                          )
                              : 0.0;
                          final double bounce = tick >= 0.55 && tick < 0.65
                              ? Curves.elasticOut.transform(
                            ((tick - 0.55) / 0.1).clamp(0.0, 1.0),
                          )
                              : tick >= 0.65
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
                  } catch (error) {
                    developer.log(
                      'Failed to compile step parameters inside sub-frame generator: $error',
                      name: 'NetworkMiddlewareScreen.animation',
                      error: error,
                      stackTrace: StackTrace.current,
                    );
                    return const SizedBox.shrink();
                  }
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
    } catch (error) {
      developer.log(
        'Failed to render network synchronization layout interface: $error',
        name: 'NetworkMiddlewareScreen.build',
        error: error,
        stackTrace: StackTrace.current,
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      animation.dispose();
      progress.dispose();
    } catch (error) {
      developer.log(
        'Failed to cleanly terminate active state lifecycle controllers: $error',
        name: 'NetworkMiddlewareScreen.dispose',
        error: error,
        stackTrace: StackTrace.current,
      );
    }
    super.dispose();
  }
}