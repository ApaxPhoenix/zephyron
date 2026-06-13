import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:minio/minio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre/maplibre.dart';

class MapsPage extends StatefulWidget {
  const MapsPage({super.key});

  @override
  State<MapsPage> createState() => MapsPageState();
}

class MapsPageState extends State<MapsPage> with TickerProviderStateMixin {
  late AnimationController animation;
  double progress = 0.0;

  MapController? controller;
  double zoom = 1;
  String root = '';
  String style = '';

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
        await Directory('$root/contents').create(recursive: true);

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
                'Found: $name (${object.size ?? 0} bytes)',
                name: 'MapsPage',
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
                    (received.fold<int>(0, (sum, b) => sum + b) / total) * 0.8,
              );
            }
          }

          Future<void> download(int i) async {
            final item = items[i];
            try {
              final file = File('$root/contents/${item.name}');
              final etag = item.hash?.replaceAll('"', '').toLowerCase();
              final validEtag =
                  etag != null &&
                  etag.isNotEmpty &&
                  !etag.contains('-') &&
                  etag.length == 32;

              if (await file.exists() &&
                  (item.size == 0 || await file.length() == item.size)) {
                if (validEtag) {
                  final sink = AccumulatorSink<Digest>();
                  final hasher = md5.startChunkedConversion(sink);
                  await for (final chunk in file.openRead()) hasher.add(chunk);
                  hasher.close();
                  if (sink.events.isNotEmpty &&
                      sink.events.first.toString() == etag) {
                    received[i] = item.size;
                    update();
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
                  if (buffer.length >= 5 * 1024 * 1024)
                    await writer.writeFrom(buffer.takeBytes());
                  update();
                }
                if (buffer.length > 0)
                  await writer.writeFrom(buffer.takeBytes());
                await writer.flush();
              } finally {
                await writer.close();
              }

              if (validEtag) {
                final sink = AccumulatorSink<Digest>();
                final hasher = md5.startChunkedConversion(sink);
                await for (final chunk in file.openRead()) hasher.add(chunk);
                hasher.close();
                if (sink.events.isEmpty ||
                    sink.events.first.toString() != etag) {
                  await file.delete();
                  throw Exception('Corrupt file ${item.name}');
                }
              }

              received[i] = item.size;
              update();
            } catch (error) {
              developer.log(
                'Item error ${item.name}: $error',
                error: error,
                stackTrace: StackTrace.current,
                name: 'MapsPage',
                level: 1000,
              );
            }
          }

          final pool = <Future<void>>[];
          for (var i = 0; i < items.length; i++) {
            pool.add(download(i));
            if (pool.length == 3 || i == items.length - 1)
              await Future.wait(pool..clear());
          }
        }

        if (!mounted || progress >= 1.0) return;

        while (progress < 1.0) {
          await Future.delayed(const Duration(milliseconds: 16));
          if (!mounted || progress >= 1.0) break;
          setState(() => progress = (progress + 0.02).clamp(0.0, 1.0));
        }

        if (!mounted) return;
        final dark =
            MediaQuery.of(context).platformBrightness == Brightness.dark;
        final bg = dark ? '#1a1a2e' : '#f5f5f0';
        final land = dark ? '#2a2a3e' : '#e8e0d8';
        final water = dark ? '#0d1b2a' : '#a8d4e6';
        final road = dark ? '#3a3a5a' : '#ffffff';
        final text = dark ? '#e0e0e0' : '#333333';
        setState(
          () => style =
              '''
{
  "version": 8,
  "sources": {
    "protomaps": {
      "type": "vector",
      "url": "pmtiles://$root/contents/low.pmtiles",
      "attribution": ""
    }
  },
  "layers": [
    {"id":"background","type":"background","paint":{"background-color":"$bg"}},
    {"id":"earth","type":"fill","source":"protomaps","source-layer":"earth","paint":{"fill-color":"$land"}},
    {"id":"water","type":"fill","source":"protomaps","source-layer":"water","paint":{"fill-color":"$water"}},
    {"id":"landuse_park","type":"fill","source":"protomaps","source-layer":"landuse","filter":["in","pmap:kind","park","nature_reserve","forest","wood"],"paint":{"fill-color":"${dark ? '#1e3a2a' : '#c8e6c9'}"}},
    {"id":"roads_other","type":"line","source":"protomaps","source-layer":"roads","filter":["all",["!=","pmap:kind","highway"],["!=","pmap:kind","major_road"]],"paint":{"line-color":"$road","line-width":1}},
    {"id":"roads_major","type":"line","source":"protomaps","source-layer":"roads","filter":["==","pmap:kind","major_road"],"paint":{"line-color":"$road","line-width":2}},
    {"id":"roads_highway","type":"line","source":"protomaps","source-layer":"roads","filter":["==","pmap:kind","highway"],"paint":{"line-color":"$road","line-width":3}},
    {"id":"buildings","type":"fill","source":"protomaps","source-layer":"buildings","paint":{"fill-color":"${dark ? '#2e2e4a' : '#d9d0c7'}","fill-outline-color":"${dark ? '#3a3a5a' : '#c0b8ae'}"}},
    {"id":"places","type":"symbol","source":"protomaps","source-layer":"places","layout":{"text-field":"{name}","text-size":12,"text-font":[],"text-anchor":"center"},"paint":{"text-color":"$text","text-halo-color":"$bg","text-halo-width":1}}
  ]
}
''',
        );
      } catch (error) {
        developer.log(
          'Assets error: $error',
          error: error,
          stackTrace: StackTrace.current,
          name: 'MapsPage',
          level: 1000,
        );
        if (!mounted || progress >= 1.0) return;
        Navigator.of(context).pushReplacementNamed('/');
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    if (progress < 1.0 || style.isEmpty) {
      return Scaffold(
        body: Stack(
          children: [
            Center(
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final double val = progress >= 0.99
                      ? animation.value
                      : animation.value % 1.0;
                  if (progress >= 0.99) {
                    return Opacity(
                      opacity: val >= 0.5
                          ? 1.0 -
                                Curves.easeOut.transform(
                                  ((val - 0.5) / 0.5).clamp(0.0, 1.0),
                                )
                          : 1.0,
                      child: Transform.scale(
                        scale: val >= 0.3 && val < 0.6
                            ? Curves.easeOut.transform(
                                    ((val - 0.3) / 0.3).clamp(0.0, 1.0),
                                  ) *
                                  30
                            : val >= 0.6
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
                      children: List.generate(4, (pos) {
                        final bool lx = pos == 0 || pos == 3;
                        final bool ly = pos == 0 || pos == 1;
                        final bool nx =
                            (pos + 1) % 4 == 0 || (pos + 1) % 4 == 3;
                        final bool ny =
                            (pos + 1) % 4 == 0 || (pos + 1) % 4 == 1;
                        final double spread = val < 0.15
                            ? Curves.easeOut.transform(
                                (val / 0.15).clamp(0.0, 1.0),
                              )
                            : val >= 0.55
                            ? 1.0 -
                                  Curves.easeIn.transform(
                                    ((val - 0.55) / 0.15).clamp(0.0, 1.0),
                                  )
                            : 1.0;
                        final double orbit = val >= 0.15 && val < 0.5
                            ? Curves.easeInOut.transform(
                                ((val - 0.15) / 0.35).clamp(0.0, 1.0),
                              )
                            : 0.0;
                        final double bounce = val >= 0.55 && val < 0.65
                            ? Curves.elasticOut.transform(
                                ((val - 0.55) / 0.1).clamp(0.0, 1.0),
                              )
                            : val >= 0.65
                            ? 1.0
                            : 0.0;
                        return Transform.translate(
                          offset: Offset(
                            (lx ? -20.0 : 20.0) * spread +
                                (nx ? -20.0 : 20.0) * spread * orbit -
                                (lx ? -20.0 : 20.0) * spread * orbit,
                            (ly ? -20.0 : 20.0) * spread +
                                (ny ? -20.0 : 20.0) * spread * orbit -
                                (ly ? -20.0 : 20.0) * spread * orbit,
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

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        color: MediaQuery.platformBrightnessOf(context) == Brightness.dark
            ? const Color(0xFF1A1A2E)
            : const Color(0xFFF5F5F5),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                MapLibreMap(
                  options: MapOptions(
                    initCenter: const Geographic(lon: 0, lat: 20),
                    initZoom: 1,
                    initPitch: 45,
                    initStyle: style,
                  ),
                  onMapCreated: (map) => controller = map,
                  onStyleLoaded: (style) async {
                    final permission = await Geolocator.requestPermission();
                    if (permission == LocationPermission.denied ||
                        permission == LocationPermission.deniedForever)
                      return;
                    final position = await Geolocator.getCurrentPosition();
                    await style.addSource(
                      GeoJsonSource(
                        id: 'user-location',
                        data:
                            '{"type":"Feature","geometry":{"type":"Point","coordinates":[${position.longitude},${position.latitude}]},"properties":{}}',
                      ),
                    );
                    await style.addLayer(
                      const CircleStyleLayer(
                        id: 'user-location-halo',
                        sourceId: 'user-location',
                        paint: {
                          'circle-radius': 20,
                          'circle-color': '#4285F4',
                          'circle-opacity': 0.15,
                        },
                      ),
                    );
                    await style.addLayer(
                      const CircleStyleLayer(
                        id: 'user-location-layer',
                        sourceId: 'user-location',
                        paint: {
                          'circle-radius': 8,
                          'circle-color': '#4285F4',
                          'circle-stroke-width': 3,
                          'circle-stroke-color': '#FFFFFF',
                        },
                      ),
                    );
                    await controller?.animateCamera(
                      center: Geographic(
                        lon: position.longitude,
                        lat: position.latitude,
                      ),
                      zoom: 14,
                      nativeDuration: const Duration(milliseconds: 800),
                    );
                  },
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoom_in',
                        onPressed: () async {
                          setState(() => zoom = (zoom + 1).clamp(1, 22));
                          await controller?.animateCamera(
                            zoom: zoom,
                            nativeDuration: const Duration(milliseconds: 300),
                          );
                        },
                        child: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoom_out',
                        onPressed: () async {
                          setState(() => zoom = (zoom - 1).clamp(1, 22));
                          await controller?.animateCamera(
                            zoom: zoom,
                            nativeDuration: const Duration(milliseconds: 300),
                          );
                        },
                        child: const Icon(Icons.remove),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'my_location',
                        onPressed: () async {
                          final position =
                              await Geolocator.getCurrentPosition();
                          await controller?.animateCamera(
                            center: Geographic(
                              lon: position.longitude,
                              lat: position.latitude,
                            ),
                            zoom: 14,
                            nativeDuration: const Duration(milliseconds: 600),
                          );
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }
}

class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}
