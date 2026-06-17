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
  String? style;
  double zoom = 1.0;
  Geographic? telemetry;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        if (await Geolocator.isLocationServiceEnabled()) {
          LocationPermission authorization = await Geolocator.checkPermission();
          if (authorization == LocationPermission.denied) {
            authorization = await Geolocator.requestPermission();
          }
          if (authorization != LocationPermission.denied &&
              authorization != LocationPermission.deniedForever) {
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
          'Location error: $error',
          name: 'NetworkScreen.location',
          error: error,
        );
      }

      try {
        final folder = await getApplicationDocumentsDirectory();
        final target = Directory('${folder.path}/map');
        if (await target.exists()) {
          await for (final file in target.list(recursive: true)) {
            if (file is File) {
              final name = file.path.split('/').last.toLowerCase();
              if (name.contains('low') && name.endsWith('.pmtiles')) {
                String appearance = 'light';
                if (notifier.value.appearance == Appearance.dark) {
                  appearance = 'dark';
                }
                if (notifier.value.appearance == Appearance.grayscale) {
                  appearance = 'grayscale';
                }
                final schema = File('${target.path}/styles/$appearance.json');
                if (await schema.exists()) {
                  final Map<String, dynamic> configuration = jsonDecode(
                    await schema.readAsString(),
                  );
                  configuration["sprite"] =
                      "file://${target.path}/sprites/v4/$appearance";
                  configuration["glyphs"] =
                      "file://${target.path}/fonts/{fontstack}/{range}.pbf";
                  if (configuration["sources"] != null) {
                    if (configuration["sources"]["protomaps"] != null) {
                      configuration["sources"]["protomaps"]["url"] =
                          "pmtiles://file://${file.path}";
                    }
                    if (configuration["sources"]["vector-tiles"] != null) {
                      configuration["sources"]["vector-tiles"]["url"] =
                          "pmtiles://file://${file.path}";
                    }
                  }
                  if (mounted) {
                    setState(() => style = jsonEncode(configuration));
                  }
                } else {
                  if (mounted) {
                    setState(() {
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
                    });
                  }
                }
                return;
              }
            }
          }
        }
        if (mounted && style == null) {
          setState(() => style = null);
        }
      } catch (error) {
        developer.log(
          'Map error: $error',
          name: 'NetworkScreen.mapInit',
          error: error,
        );
        if (mounted) {
          setState(() => style = null);
        }
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
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
                    controller!.animateCamera(center: telemetry!, zoom: zoom);
                  }
                },
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
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
                try {
                  final folder = await getApplicationDocumentsDirectory();
                  final database = await openDatabase(
                    '${folder.path}/map/misc/locations.db',
                  );
                  final rows = await database.rawQuery(
                    '''
                    SELECT l.* FROM locations l 
                    JOIN search s ON l.id = s.content_rowid 
                    WHERE search MATCH ? 
                    LIMIT 10
                  ''',
                    ['${query.replaceAll("'", "''")}*'],
                  );
                  await database.close();
                  return rows.map((json) => Location.fromJson(json)).toList();
                } catch (error) {
                  developer.log(
                    'Search failure: $error',
                    name: 'NetworkScreen.search',
                    error: error,
                  );
                  return [];
                }
              },
              select: (location) async {
                if (controller != null) {
                  try {
                    await controller!.animateCamera(
                      center: Geographic(
                        lon: location.longitude,
                        lat: location.latitude,
                      ),
                      zoom: zoom,
                    );
                  } catch (error) {
                    developer.log(
                      'Navigation failure: $error',
                      name: 'NetworkScreen.select',
                      error: error,
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
                    Navigator.of(context).pushNamed('/network/settings');
                  },
                  child: const Icon(Icons.settings),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'location',
                  onPressed: () async {
                    if (controller == null) return;
                    try {
                      final position = await Geolocator.getCurrentPosition();
                      await controller!.animateCamera(
                        center: Geographic(
                          lon: position.longitude,
                          lat: position.latitude,
                        ),
                        zoom: zoom,
                      );
                    } catch (error) {
                      developer.log(
                        'Tracking failure: $error',
                        name: 'NetworkScreen.tracking',
                        error: error,
                      );
                    }
                  },
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom-in',
                  onPressed: () async {
                    if (controller != null) {
                      zoom = (zoom + 1).clamp(0.0, 22.0);
                      await controller!.animateCamera(zoom: zoom);
                    }
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom-out',
                  onPressed: () async {
                    if (controller != null) {
                      zoom = (zoom - 1).clamp(0.0, 22.0);
                      await controller!.animateCamera(zoom: zoom);
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
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }
}
