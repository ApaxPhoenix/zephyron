import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/state.dart';
import 'package:zephyron/models/location.dart';
import 'package:zephyron/widgets/dropdown.dart';

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
  double zoom = 14.0;
  Geographic? telemetry;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        if (await Geolocator.isLocationServiceEnabled()) {
          LocationPermission auth = await Geolocator.checkPermission();
          if (auth == LocationPermission.denied) {
            auth = await Geolocator.requestPermission();
          }
          if (auth != LocationPermission.denied &&
              auth != LocationPermission.deniedForever) {
            final position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
              ),
            );
            telemetry = Geographic(
              lon: position.longitude,
              lat: position.latitude,
            );
          }
        }
      } catch (error) {
        developer.log(
          'Failed to capture hardware device telemetry: $error',
          error: error,
          stackTrace: StackTrace.current,
          name: 'NetworkScreen.telemetry',
        );
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
          'Failed to assemble stylesheet definitions from engine storage: $error',
          error: error,
          stackTrace: StackTrace.current,
          name: 'NetworkScreen.setup',
        );
      }

      if (mounted) {
        setState(() {});
      }
    }();
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
                      controller!.animateCamera(center: telemetry!, zoom: zoom);
                    } catch (error) {
                      developer.log(
                        'Failed to reposition camera target tracking to active location: $error',
                        error: error,
                        stackTrace: StackTrace.current,
                        name: 'NetworkScreen.navigation',
                      );
                    }
                  }
                },
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
                  contentPadding: EdgeInsets.all(16),
                ),
                search: (query) async {
                  if (query.trim().isNotEmpty) {
                    try {
                      if (database == null) {
                        final directory = await getApplicationDocumentsDirectory();
                        final file = File('${directory.path}/map/misc/locations.db');
                        if (await file.exists()) {
                          database = sqlite3.open(file.path);
                        }
                      }

                      if (database != null) {
                        final rows = database!.select(
                          "SELECT id, ascii, iso, latitude, longitude "
                              "FROM locations "
                              "WHERE id IN (SELECT rowid FROM search WHERE search MATCH ?) "
                              "LIMIT 40",
                          [
                            query.trim().split(RegExp(r'\s+')).map((word) => '$word*').join(' OR ')
                          ],
                        );

                        return rows.map((json) => Location.fromJson(json)).toList();
                      }
                    } catch (error) {
                      developer.log(
                        'Failed to filter search rows against index conditions: $error',
                        error: error,
                        stackTrace: StackTrace.current,
                        name: 'NetworkScreen.search',
                      );
                    }
                  }
                  return [];
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
                        'Failed to direct camera translation to explicit target: $error',
                        error: error,
                        stackTrace: StackTrace.current,
                        name: 'NetworkScreen.navigation',
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
                    onPressed: () {
                      try {
                        Navigator.of(context).pushNamed('/network/settings');
                      } catch (error) {
                        developer.log(
                          'Failed to route screen navigation to network settings: $error',
                          error: error,
                          stackTrace: StackTrace.current,
                          name: 'NetworkScreen.navigation',
                        );
                      }
                    },
                    child: const Icon(Icons.settings),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'location',
                    onPressed: () {
                      if (controller != null && telemetry != null) {
                        try {
                          controller!.animateCamera(
                            center: telemetry!,
                            zoom: zoom,
                          );
                        } catch (error) {
                          developer.log(
                            'Failed to snap camera back to active telemetry coordinates: $error',
                            error: error,
                            stackTrace: StackTrace.current,
                            name: 'NetworkScreen.navigation',
                          );
                        }
                      }
                    },
                    child: const Icon(Icons.my_location),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoom-in',
                    onPressed: () {
                      try {
                        zoom = (zoom + 1).clamp(0.0, 22.0);
                        if (controller != null) {
                          controller!.animateCamera(zoom: zoom);
                        }
                      } catch (error) {
                        developer.log(
                          'Failed to adjust dynamic rendering magnification scale: $error',
                          error: error,
                          stackTrace: StackTrace.current,
                          name: 'NetworkScreen.navigation',
                        );
                      }
                    },
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoom-out',
                    onPressed: () {
                      try {
                        zoom = (zoom - 1).clamp(0.0, 22.0);
                        if (controller != null) {
                          controller!.animateCamera(zoom: zoom);
                        }
                      } catch (error) {
                        developer.log(
                          'Failed to adjust dynamic rendering magnification scale: $error',
                          error: error,
                          stackTrace: StackTrace.current,
                          name: 'NetworkScreen.navigation',
                        );
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
        'Failed to render interactive geographic dashboard view interface: $error',
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
        'Failed to cleanly release mapping and telemetry framework allocations: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'NetworkScreen.dispose',
      );
    }
    super.dispose();
  }
}
