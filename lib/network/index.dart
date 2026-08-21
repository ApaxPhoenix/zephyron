import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/location.dart';
import 'package:zephyron/state.dart';
import 'package:zephyron/widgets/dropdown.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => NetworkScreenState();
}

class NetworkScreenState extends State<NetworkScreen> {
  final input = TextEditingController();
  MapLibreMapController? map;
  Database? database;
  String? style;
  double zoom = 14.0;
  LatLng? telemetry;

  @override
  void initState() {
    super.initState();

    () async {
      try {
        if (await Geolocator.isLocationServiceEnabled()) {
    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
    status = await Geolocator.requestPermission();
    }
    if (status != LocationPermission.denied && status != LocationPermission.deniedForever) {
    final loc = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    telemetry = LatLng(loc.latitude, loc.longitude);
    }
    }
    } catch (error) {
    developer.log(
    'Failed to setup geolocation telemetry: $error',
    error: error,
    stackTrace: StackTrace.current,
    level: 1000,
    name: 'NetworkScreen.telemetry',
    );
    }

    try {
    final path = (await getApplicationDocumentsDirectory()).path;
    final mode = notifier.value.appearance == Appearance.dark ? 'dark' : 'light';
    final schema = File('$path/styles/$mode.json');

    if (await schema.exists()) {
    final Map<String, dynamic> config = jsonDecode(await schema.readAsString());
    config['sprite'] = Uri.file('$path/sprites/v4/$mode').toString();
    config['glyphs'] = '${Uri.file('$path/fonts')}/{fontstack}/{range}.pbf';

    final tileExists = await File('$path/tiles/protomaps.pmtiles').exists();
    if (config['sources'] is Map && tileExists) {
    final pmtilesUrl = 'pmtiles://${Uri.file('$path/tiles/protomaps.pmtiles')}';
    for (final entry in (config['sources'] as Map).entries) {
    final key = entry.key.toString().toLowerCase();
    final source = entry.value;
    if (source is Map && (source['type'] == 'vector' || key.contains('protomaps') || key.contains('vector'))) {
    source.remove('tiles');
    source.remove('url');
    source['url'] = pmtilesUrl;
    }
    }
    } else {
    if (!tileExists) {
    developer.log(
    'Could not find tile file at path: $path/tiles/protomaps.pmtiles',
    stackTrace: StackTrace.current,
    level: 1000,
    name: 'NetworkScreen.setup',
    );
    }
    if (config['sources'] != null) {
    config['sources'] = {};
    config['layers'] = [
    {
    'id': 'background',
    'type': 'background',
    'paint': {'background-color': '#121212'},
    },
    ];
    }
    }
    style = jsonEncode(config);
    } else {
    developer.log(
    'Could not find schema file at path: ${schema.path}',
    stackTrace: StackTrace.current,
    level: 1000,
    name: 'NetworkScreen.setup',
    );
    }
    } catch (error) {
    developer.log(
    'Failed to initialize network screen setup: $error',
    error: error,
    stackTrace: StackTrace.current,
    level: 1000,
    name: 'NetworkScreen.setup',
    );
    }

    style ??= jsonEncode({
    'version': 8,
    'sources': {},
    'layers': [
    {
    'id': 'background',
    'type': 'background',
    'paint': {'background-color': '#121212'},
    },
    ],
    });

    if (mounted) setState(() {});
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
                initialCameraPosition: CameraPosition(
                  target: telemetry ?? const LatLng(20.0, 0.0),
                  zoom: zoom,
                ),
                styleString: style!,
                attributionButtonMargins: const math.Point(-1000, -1000),
                logoViewMargins: const math.Point(-1000, -1000),
                onMapCreated: (instance) => map = instance,
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
                        final dbPath = '${(await getApplicationDocumentsDirectory()).path}/misc/locations.database';
                        if (await File(dbPath).exists()) {
                          database = sqlite3.open(dbPath);
                        } else {
                          developer.log(
                            'Could not find database file at path: $dbPath',
                            stackTrace: StackTrace.current,
                            level: 1000,
                            name: 'NetworkScreen.search',
                          );
                        }
                      }

                      if (database != null) {
                        final filter = query
                            .trim()
                            .split(RegExp(r'\s+'))
                            .where((w) => w.isNotEmpty)
                            .map((w) => '$w*')
                            .join(' ');

                        final rows = database!.select(
                          'SELECT l.* FROM locations l JOIN search s ON l.id = s.rowid WHERE s.ascii MATCH ? LIMIT 40;',
                          [filter],
                        );

                        return rows.map((row) => Location.fromJson(row)).toList();
                      }
                    } catch (error) {
                      developer.log(
                        'Search query execution failed: $error',
                        error: error,
                        stackTrace: StackTrace.current,
                        level: 1000,
                        name: 'NetworkScreen.search',
                      );
                    }
                  }
                  return [];
                },
                select: (location) {
                  if (map != null) {
                    try {
                      map!.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          LatLng(location.latitude, location.longitude),
                          zoom,
                        ),
                      );
                    } catch (error) {
                      developer.log(
                        'Failed to animate camera to target location: $error',
                        error: error,
                        stackTrace: StackTrace.current,
                        level: 1000,
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
                          'Failed to navigate to network settings: $error',
                          error: error,
                          stackTrace: StackTrace.current,
                          level: 1000,
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
                      if (map != null && telemetry != null) {
                        try {
                          map!.animateCamera(CameraUpdate.newLatLngZoom(telemetry!, zoom));
                        } catch (error) {
                          developer.log(
                            'Failed to animate camera to telemetry location: $error',
                            error: error,
                            stackTrace: StackTrace.current,
                            level: 1000,
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
                        map?.animateCamera(CameraUpdate.zoomTo(zoom));
                      } catch (error) {
                        developer.log(
                          'Failed to zoom in: $error',
                          error: error,
                          stackTrace: StackTrace.current,
                          level: 1000,
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
                        map?.animateCamera(CameraUpdate.zoomTo(zoom));
                      } catch (error) {
                        developer.log(
                          'Failed to zoom out: $error',
                          error: error,
                          stackTrace: StackTrace.current,
                          level: 1000,
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
        'Layout error rendering network screen: $error',
        error: error,
        stackTrace: StackTrace.current,
        level: 1000,
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
        'Cleanup error in network screen dispose: $error',
        error: error,
        stackTrace: StackTrace.current,
        level: 1000,
        name: 'NetworkScreen.dispose',
      );
    }
    super.dispose();
  }
}