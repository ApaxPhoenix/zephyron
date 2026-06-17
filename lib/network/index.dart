import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
  String style = '';
  bool loading = true;
  double zoom = 1.0;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        bool operational = await Geolocator.isLocationServiceEnabled();
        if (operational) {
          LocationPermission authorization = await Geolocator.checkPermission();
          if (authorization == LocationPermission.denied) {
            authorization = await Geolocator.requestPermission();
          }

          if (authorization != LocationPermission.denied &&
              authorization != LocationPermission.deniedForever) {
            Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
              ),
            ).then((telemetry) async {
              int attempts = 0;

              while (controller == null && attempts < 10) {
                await Future.delayed(const Duration(milliseconds: 200));
                attempts++;
              }

              if (controller != null) {
                await controller!.animateCamera(
                  center: Geographic(
                    lon: telemetry.longitude,
                    lat: telemetry.latitude,
                  ),
                  zoom: zoom,
                );
              }
            });
          }
        }
      } catch (error) {
        developer.log(
          'Location initialization failure: $error',
          name: 'NetworkScreen',
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
                  final content = await schema.readAsString();
                  final Map<String, dynamic> configuration = jsonDecode(
                    content,
                  );

                  configuration["sprite"] =
                      "file://${target.path}/sprites/v4/$appearance";
                  configuration["glyphs"] =
                      "file://${target.path}/fonts/{fontstack}/{range}.pbf";

                  if (configuration["sources"] != null &&
                      configuration["sources"]["vector-tiles"] != null) {
                    configuration["sources"]["vector-tiles"]["url"] =
                        "pmtiles://${file.path}";
                  }

                  if (mounted) {
                    setState(() {
                      style = jsonEncode(configuration);
                      loading = false;
                    });
                  }
                } else {
                  if (mounted) {
                    setState(() {
                      style =
                          '{"version":8,"sources":{"vector-tiles":{"type":"vector","url":"pmtiles://${file.path}"}},"layers":[{"id":"background","type":"background","paint":{"background-color":"#f7f7f7"}}]}';
                      loading = false;
                    });
                  }
                }
                return;
              }
            }
          }
        }
      } catch (error) {
        developer.log(
          'Error initializing map: $error',
          name: 'NetworkScreen',
          error: error,
        );
      }

      if (mounted) {
        setState(() => loading = false);
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    try {
      if (loading) {
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
                    initCenter: const Geographic(lon: 0, lat: 20),
                    initZoom: zoom,
                    initPitch: 0,
                    initStyle: style,
                  ),
                  onMapCreated: (map) {
                    controller = map;
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
                    final path = '${folder.path}/map/misc/locations.db';
                    final database = await openDatabase(path);

                    final clean = query.replaceAll("'", "''");
                    final rows = await database.rawQuery('''
                      SELECT l.* FROM locations l 
                      JOIN search s ON l.id = s.content_rowid 
                      WHERE search MATCH '$clean*' 
                      LIMIT 10
                    ''');

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
                    child: Icon(PhosphorIcons.gear()),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'location',
                    onPressed: () async {
                      if (controller == null) return;

                      try {
                        final telemetry = await Geolocator.getCurrentPosition();

                        await controller!.animateCamera(
                          center: Geographic(
                            lon: telemetry.longitude,
                            lat: telemetry.latitude,
                          ),
                          zoom: zoom,
                        );
                      } catch (error) {
                        developer.log(
                          'Location tracking failure: $error',
                          name: 'NetworkScreen',
                        );
                      }
                    },
                    child: Icon(PhosphorIcons.crosshair()),
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
                    child: Icon(PhosphorIcons.plus()),
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
                    child: Icon(PhosphorIcons.minus()),
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
      super.dispose();
    } catch (error) {
      developer.log(
        'Error during dispose: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'NetworkScreen.dispose',
      );
    }
  }
}
