import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
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
  static const chunk = 4 * 1024 * 1024;
  static const limit = 4;

  late final AnimationController loop;
  final ValueNotifier<double> rate = ValueNotifier<double>(-1.0);

  @override
  void initState() {
    super.initState();
    try {
      loop = AnimationController(
        duration: const Duration(seconds: 5),
        vsync: this,
      )..repeat();
    } catch (error) {
      developer.log(
        'Failed to initialize layout animation loops: $error',
        name: 'NetworkMiddlewareScreen.setup',
        error: error,
        stackTrace: StackTrace.current,
        level: 1000,
      );
    }

    unawaited(() async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..maxConnectionsPerHost = 16;

      try {
        if (!(rate.value > 0.0)) {
          rate.value = 0.0;
          final folder = (await getApplicationDocumentsDirectory()).path;
          final items = <dynamic>[];
          String? token;

          do {
            final page = await bucket.listObjects(
              bucket: 'zephyron',
              prefix: '',
              continuationToken: token,
            );

            if (page.isSuccessful && page.body != null) {
              items.addAll(page.body!.objects);
              final next = page.body!.nextContinuationToken;
              token =
                  (page.body!.isTruncated == true &&
                      next != null &&
                      next.isNotEmpty &&
                      next != token)
                  ? next
                  : null;
            } else {
              break;
            }
          } while (token != null);

          if (items.isNotEmpty) {
            final total = items.fold<int>(
              0,
              (sum, item) => sum + ((item.size as int?) ?? 0),
            );

            var done = 0;
            var cursor = 0;

            Future<bool> check(File file, String? hash) async {
              if (hash == null || hash.isEmpty || hash.contains('-')) {
                return true;
              }
              try {
                final flow = file.openRead();
                final tag = hash.trim().toLowerCase();
                if (tag.length == 32) {
                  final digest = await md5.bind(flow).first;
                  return digest.toString().toLowerCase() == tag;
                } else if (tag.length == 64) {
                  final digest = await sha256.bind(flow).first;
                  return digest.toString().toLowerCase() == tag;
                }
              } catch (error) {
                developer.log(
                  'Failed to compute file checksum: $error',
                  name: 'NetworkMiddlewareScreen.check',
                  error: error,
                  stackTrace: StackTrace.current,
                  level: 1000,
                );
              }
              return true;
            }

            for (final item in items) {
              final key = item.key as String?;
              final size = (item.size as int?) ?? 0;
              if (key == null || key.endsWith('/')) continue;

              final file = File('$folder/$key');
              final meta = File('$folder/$key.meta');
              final hash = item.etag?.replaceAll('"', '').toLowerCase();

              if (await file.exists() &&
                  await file.length() == size &&
                  size > 0) {
                if (await check(file, hash)) {
                  done += size;
                  continue;
                }
              }

              if (await meta.exists()) {
                try {
                  final raw = await meta.readAsString();
                  final json = jsonDecode(raw) as Map<String, dynamic>;
                  if (json['size'] == size && json['parts'] is List) {
                    final list = json['parts'] as List;
                    for (var offset = 0; offset < size; offset += chunk) {
                      final index = offset ~/ chunk;
                      if (list.contains(index)) {
                        final start = offset;
                        final end = (offset + chunk - 1 >= size)
                            ? size - 1
                            : offset + chunk - 1;
                        done += (end - start + 1);
                      }
                    }
                  }
                } catch (error) {
                  developer.log(
                    'Failed to read metadata file: $error',
                    name: 'NetworkMiddlewareScreen.meta',
                    error: error,
                    stackTrace: StackTrace.current,
                    level: 1000,
                  );
                }
              }
            }

            if (total > 0) {
              rate.value = (done / total).clamp(0.0, 1.0);
            }

            Future<bool> pull(String key, int size, File draft) async {
              for (var attempt = 0; attempt < 5; attempt++) {
                var bytes = 0;
                try {
                  final link = await bucket.presignedUrl(
                    bucket: 'zephyron',
                    key: key,
                  );
                  final request = await client.getUrl(Uri.parse(link.url));
                  final response = await request.close().timeout(
                    const Duration(seconds: 30),
                  );

                  if (response.statusCode == 200) {
                    final sink = draft.openWrite();
                    await for (final buffer in response) {
                      sink.add(buffer);
                      bytes += buffer.length;
                      done += buffer.length;
                      if (total > 0) {
                        rate.value = (done / total).clamp(0.0, 1.0);
                      }
                    }
                    await sink.flush();
                    await sink.close();
                    if (await draft.length() == size || size == 0) {
                      return true;
                    }
                  }
                } catch (error) {
                  developer.log(
                    'Download error on $key: $error',
                    name: 'NetworkMiddlewareScreen.pull',
                    error: error,
                    stackTrace: StackTrace.current,
                    level: 1000,
                  );
                }
                done -= bytes;
                if (total > 0) {
                  rate.value = (done / total).clamp(0.0, 1.0);
                }
                if (draft.existsSync()) draft.deleteSync();
                await Future.delayed(
                  Duration(milliseconds: 150 * (attempt + 1)),
                );
              }
              return false;
            }

            Future<bool> slice(
              String key,
              int size,
              File draft,
              File meta,
            ) async {
              try {
                final completed = <int>{};
                if (await meta.exists()) {
                  try {
                    final raw = await meta.readAsString();
                    final json = jsonDecode(raw) as Map<String, dynamic>;
                    if (json['size'] == size && json['parts'] is List) {
                      final list = json['parts'] as List;
                      for (final item in list) {
                        if (item is int) completed.add(item);
                      }
                    }
                  } catch (error) {
                    developer.log(
                      'Failed to parse slice metadata for $key: $error',
                      name: 'NetworkMiddlewareScreen.sliceMeta',
                      error: error,
                      stackTrace: StackTrace.current,
                      level: 1000,
                    );
                    completed.clear();
                  }
                }

                if (!await draft.exists() || await draft.length() != size) {
                  final writer = await draft.open(mode: FileMode.write);
                  await writer.truncate(size);
                  await writer.close();
                  completed.clear();
                  if (meta.existsSync()) meta.deleteSync();
                }

                final parts = <Map<String, int>>[];
                for (var offset = 0; offset < size; offset += chunk) {
                  parts.add({
                    'start': offset,
                    'end': (offset + chunk - 1 >= size)
                        ? size - 1
                        : offset + chunk - 1,
                  });
                }

                completed.removeWhere(
                  (item) => item < 0 || item >= parts.length,
                );

                var busy = false;

                Future<void> sync() async {
                  while (busy) {
                    await Future.delayed(const Duration(milliseconds: 10));
                  }
                  busy = true;
                  try {
                    final json = {'size': size, 'parts': completed.toList()};
                    await meta.writeAsString(jsonEncode(json), flush: true);
                  } catch (error) {
                    developer.log(
                      'Failed to sync metadata for $key: $error',
                      name: 'NetworkMiddlewareScreen.syncMeta',
                      error: error,
                      stackTrace: StackTrace.current,
                      level: 1000,
                    );
                  } finally {
                    busy = false;
                  }
                }

                var index = 0;
                var failed = false;

                final tasks = List.generate(limit, (_) async {
                  while (!failed) {
                    if (index >= parts.length) break;
                    final current = index++;
                    if (completed.contains(current)) continue;

                    final start = parts[current]['start']!;
                    final end = parts[current]['end']!;
                    final range = end - start + 1;

                    var success = false;
                    for (var attempt = 0; attempt < 5; attempt++) {
                      try {
                        final link = await bucket.presignedUrl(
                          bucket: 'zephyron',
                          key: key,
                        );
                        final request = await client.getUrl(
                          Uri.parse(link.url),
                        );
                        request.headers.add('Range', 'bytes=$start-$end');
                        final response = await request.close().timeout(
                          const Duration(seconds: 30),
                        );

                        if (response.statusCode == 206 ||
                            response.statusCode == 200) {
                          final builder = BytesBuilder(copy: false);
                          await for (final buffer in response) {
                            builder.add(buffer);
                          }

                          final bytes = builder.takeBytes();
                          if (bytes.length == range) {
                            final writer = await draft.open(
                              mode: FileMode.append,
                            );
                            await writer.setPosition(start);
                            await writer.writeFrom(bytes);
                            await writer.close();

                            done += range;
                            if (total > 0) {
                              rate.value = (done / total).clamp(0.0, 1.0);
                            }

                            completed.add(current);
                            await sync();

                            success = true;
                            break;
                          }
                        }
                      } catch (error) {
                        developer.log(
                          'Range error ($key, bytes $start-$end): $error',
                          name: 'NetworkMiddlewareScreen.slice',
                          error: error,
                          stackTrace: StackTrace.current,
                          level: 1000,
                        );
                      }
                      await Future.delayed(
                        Duration(milliseconds: 150 * (attempt + 1)),
                      );
                    }

                    if (!success) {
                      failed = true;
                      break;
                    }
                  }
                });

                await Future.wait(tasks);

                if (failed ||
                    completed.length != parts.length ||
                    (await draft.length() != size)) {
                  return false;
                }

                if (meta.existsSync()) meta.deleteSync();
                return true;
              } catch (error) {
                developer.log(
                  'Range failure for $key: $error',
                  name: 'NetworkMiddlewareScreen.slice',
                  error: error,
                  stackTrace: StackTrace.current,
                  level: 1000,
                );
                return false;
              }
            }

            final pool = List.generate(limit, (_) async {
              while (true) {
                if (cursor >= items.length) break;
                final item = items[cursor++];

                try {
                  final size = (item.size as int?) ?? 0;
                  final key = item.key as String?;

                  if (key == null || key.endsWith('/')) {
                    if (key != null) {
                      await Directory('$folder/$key').create(recursive: true);
                    }
                    continue;
                  }

                  final file = File('$folder/$key');
                  final draft = File('$folder/$key.tmp');
                  final meta = File('$folder/$key.meta');
                  await file.parent.create(recursive: true);

                  final hash = item.etag?.replaceAll('"', '').toLowerCase();

                  if (await file.exists()) {
                    if (await file.length() == size && size > 0) {
                      if (await check(file, hash)) {
                        continue;
                      }
                    }
                    if (file.existsSync()) file.deleteSync();
                  }

                  final success = (size > chunk)
                      ? await slice(key, size, draft, meta)
                      : await pull(key, size, draft);

                  if (success) {
                    if (await check(draft, hash)) {
                      await draft.rename(file.path);
                      if (meta.existsSync()) meta.deleteSync();
                    } else {
                      if (draft.existsSync()) draft.deleteSync();
                      if (meta.existsSync()) meta.deleteSync();
                    }
                  }
                } catch (error) {
                  developer.log(
                    'Worker error: $error',
                    name: 'NetworkMiddlewareScreen.pool',
                    error: error,
                    stackTrace: StackTrace.current,
                    level: 1000,
                  );
                }
              }
            });

            await Future.wait(pool);
            rate.value = 1.0;
          } else {
            rate.value = 1.0;
          }
        }
      } catch (error) {
        developer.log(
          'Synchronization failed: $error',
          error: error,
          stackTrace: StackTrace.current,
          level: 1000,
          name: 'NetworkMiddlewareScreen.sync',
        );
      } finally {
        client.close(force: true);
      }

      if (mounted) {
        try {
          if (rate.value >= 0.99) {
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted) {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/network', (route) => false);
            }
          } else {
            final folder = (await getApplicationDocumentsDirectory()).path;
            var found = false;

            try {
              found = Directory(folder)
                  .listSync(recursive: true)
                  .any(
                    (entity) =>
                        entity is File &&
                        !entity.path.endsWith('.tmp') &&
                        !entity.path.endsWith('.meta'),
                  );
            } catch (error) {
              developer.log(
                'Failed to inspect local directoryectory: $error',
                error: error,
                stackTrace: StackTrace.current,
                level: 1000,
                name: 'NetworkMiddlewareScreen.inspectDir',
              );
              found = false;
            }

            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil(
                found ? '/network' : '/',
                (route) => false,
              );
            }
          }
        } catch (error) {
          developer.log(
            'Navigation error after download: $error',
            error: error,
            stackTrace: StackTrace.current,
            level: 1000,
            name: 'NetworkMiddlewareScreen.navigate',
          );
          if (mounted) {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/', (route) => false);
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
                animation: loop,
                builder: (context, child) {
                  try {
                    final double tick = rate.value >= 0.99
                        ? loop.value
                        : loop.value % 1.0;

                    if (rate.value >= 0.99) {
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

                          final double size =
                              16.0 +
                              16.0 * (1.0 - spread) +
                              8.0 * (1.0 - spread) * bounce;

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
                              width: size,
                              height: size,
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
                      'Render error: $error',
                      error: error,
                      stackTrace: StackTrace.current,
                      level: 1000,
                      name: 'NetworkMiddlewareScreen.animation',
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
                valueListenable: rate,
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
        'Layout error: $error',
        error: error,
        stackTrace: StackTrace.current,
        level: 1000,
        name: 'NetworkMiddlewareScreen.build',
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      loop.dispose();
      rate.dispose();
      getApplicationDocumentsDirectory()
          .then((folder) {
            final directory = Directory(folder.path);
            if (directory.existsSync()) {
              for (final item in directory.listSync(recursive: true)) {
                if (item is File &&
                    (item.path.endsWith('.tmp') ||
                        item.path.endsWith('.meta'))) {
                  if (item.existsSync()) {
                    item.deleteSync();
                  }
                }
              }
            }
          })
          .catchError((error) {
            developer.log(
              'Purge error: $error',
              name: 'NetworkMiddlewareScreen.dispose',
              error: error,
              stackTrace: StackTrace.current,
              level: 1000,
            );
          });
    } catch (error) {
      developer.log(
        'Cleanup error: $error',
        error: error,
        stackTrace: StackTrace.current,
        level: 1000,
        name: 'NetworkMiddlewareScreen.dispose',
      );
    }
    super.dispose();
  }
}
