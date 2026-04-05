import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/state.dart';
import 'package:zephyron/models/location.dart';
import 'package:zephyron/widgets/dropdown-field.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => NetworkScreenState();
}

class NetworkScreenState extends State<NetworkScreen> {
  final input = TextEditingController();
  MapController? controller;
  Database? database;
  String? style;
  double zoom = 1.0;
  Geographic? telemetry;

  @override
  void initState() {
    super.initState();
    () async {
      telemetry = await gps();
      if (mounted) {
        setState(() {});
      }

      try {
        final folder = await getApplicationDocumentsDirectory();
        final target = Directory('${folder.path}/map');
        if (await target.exists()) {
          final files = target.list(recursive: true);
          await for (final file in files) {
            if (file is File) {
              final name = file.path.split('/').last.toLowerCase();
              if (name.contains('low') && name.endsWith('.pmtiles')) {
                final mode = switch (notifier.value.appearance) {
                  Appearance.dark => 'dark',
                  Appearance.grayscale => 'grayscale',
                  _ => 'light',
                };

                final schema = File('${target.path}/styles/$mode.json');
                if (await schema.exists()) {
                  final Map<String, dynamic> configuration = jsonDecode(
                    await schema.readAsString(),
                  );
                  configuration["sprite"] =
                      "file://${target.path}/sprites/v4/$mode";
                  configuration["glyphs"] =
                      "file://${target.path}/fonts/{fontstack}/{range}.pbf";
                  final sources = configuration["sources"];
                  if (sources != null) {
                    if (sources["protomaps"] != null) {
                      sources["protomaps"]["url"] =
                          "pmtiles://file://${file.path}";
                    }
                    if (sources["vector-tiles"] != null) {
                      sources["vector-tiles"]["url"] =
                          "pmtiles://file://${file.path}";
                    }
                  }
                  style = jsonEncode(configuration);
                } else {
                  style = jsonEncode({
                    "version": 8,
                    "sources": {
                      "protomaps": {
                        "type": "vector",
                        "url": "pmtiles://file://${file.path}",
                      },
                    },
                    "layers": [
                      {
                        "id": "background",
                        "type": "background",
                        "paint": {"background-color": "#f7f7f7"},
                      },
                    ],
                  });
                }
                break;
              }
            }
          }
        }
      } catch (error) {
        developer.log(
          'Map error: $error',
          error: error,
          name: 'NetworkScreen.mapInit',
        );
      }

      if (mounted) {
        setState(() {});
      }
    }();
  }

  Future<Geographic?> gps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      LocationPermission auth = await Geolocator.checkPermission();
      if (auth == LocationPermission.denied) {
        auth = await Geolocator.requestPermission();
      }
      if (auth == LocationPermission.denied ||
          auth == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return Geographic(lon: position.longitude, lat: position.latitude);
    } catch (error) {
      developer.log(
        'Location error: $error',
        error: error,
        name: 'NetworkScreen.location',
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      if (style == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: MapLibreMap(
                  options: MapOptions(
                    initCenter: telemetry ?? const Geographic(lon: 0, lat: 20),
                    initZoom: zoom,
                    initPitch: 0,
                    initStyle: style!,
                  ),
                  onMapCreated: (map) {
                    controller = map;
                    if (telemetry != null) {
                      try {
                        controller!.animateCamera(
                          center: telemetry!,
                          zoom: zoom,
                        );
                      } catch (error) {
                        developer.log(
                          'Navigation failure: $error',
                          error: error,
                          name: 'NetworkScreen.select',
                        );
                      }
                    }
                  },
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 16,
              left: 16,
              right: 16,
              child: DropdownField(
                controller: input,
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  border: InputBorder.none,
                  isDense: true,
                ),
                search: (query) async {
                  if (query.trim().isEmpty) return [];
                  try {
                    if (database == null || !database!.isOpen) {
                      final folder = await getApplicationDocumentsDirectory();
                      final target = Directory('${folder.path}/map');
                      if (await target.exists()) {
                        final files = target.list(recursive: true);
                        await for (final file in files) {
                          if (file is File) {
                            final name = file.path
                                .split('/')
                                .last
                                .toLowerCase();
                            if (name == 'locations.db') {
                              database = await openDatabase(
                                file.path,
                                readOnly: true,
                              );
                              break;
                            }
                          }
                        }
                      }
                    }

                    if (database == null || !database!.isOpen) return [];

                    final rows = await database!.rawQuery(
                      'SELECT l.* FROM locations l JOIN search s ON l.id = s.content_rowid WHERE search MATCH ? LIMIT 10',
                      ['$query*'],
                    );
                    return rows.map((json) => Location.fromJson(json)).toList();
                  } catch (error) {
                    developer.log(
                      'Search failure: $error',
                      error: error,
                      name: 'NetworkScreen.search',
                    );
                    return [];
                  }
                },
                select: (location) {
                  if (controller != null) {
                    try {
                      controller!.animateCamera(
                        center: Geographic(
                          lon: location.longitude,
                          lat: location.latitude,
                        ),
                        zoom: zoom,
                      );
                    } catch (error) {
                      developer.log(
                        'Navigation failure: $error',
                        error: error,
                        name: 'NetworkScreen.select',
                      );
                    }
                  }
                },
              ),
            ),
            Positioned(
              bottom: 32,
              right: 32,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'settings',
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/network/settings'),
                    child: const Icon(Icons.settings),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'location',
                    onPressed: () async {
                      if (controller != null) {
                        final position = await gps();
                        if (position != null) {
                          try {
                            controller!.animateCamera(
                              center: position,
                              zoom: zoom,
                            );
                          } catch (error) {
                            developer.log(
                              'Navigation failure: $error',
                              error: error,
                              name: 'NetworkScreen.select',
                            );
                          }
                        }
                      }
                    },
                    child: const Icon(Icons.my_location),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoom-in',
                    onPressed: () {
                      zoom = (zoom + 1).clamp(0.0, 22.0);
                      if (controller != null) {
                        controller!.animateCamera(zoom: zoom);
                      }
                    },
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoom-out',
                    onPressed: () {
                      zoom = (zoom - 1).clamp(0.0, 22.0);
                      if (controller != null) {
                        controller!.animateCamera(zoom: zoom);
                      }
                    },
                    child: const Icon(Icons.remove),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (error) {
      developer.log(
        'Error building widget: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'NetworkScreen.build',
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      input.dispose();
      database?.close();
    } catch (error) {
      developer.log(
        'Error during dispose: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'NetworkScreen.dispose',
      );
    }
    super.dispose();
  }
}
