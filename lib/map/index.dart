import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class MapsScreen extends StatefulWidget {
  const MapsScreen({super.key});

  @override
  State<MapsScreen> createState() => MapsScreenState();
}

class MapsScreenState extends State<MapsScreen> {
  MapController? controller;
  String style = '';
  bool loading = true;
  double zoom = 1.0;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final folder = await getApplicationDocumentsDirectory();
        final target = Directory('${folder.path}/map');

        developer.log(
          'Target directory path: ${target.path}',
          name: 'MapsScreen',
        );

        if (await target.exists()) {
          final files = target.listSync(recursive: true);
          developer.log(
            'Total items found recursively: ${files.length}',
            name: 'MapsScreen',
          );

          for (final file in files) {
            if (file is File) {
              final name = file.path.split('/').last.toLowerCase();
              developer.log('Evaluating file: $name', name: 'MapsScreen');

              if (name.contains('low') && name.endsWith('.pmtiles')) {
                developer.log(
                  'Matching file located: ${file.path}',
                  name: 'MapsScreen',
                );

                final jsonFile = File('${target.path}/styles/light.json');
                if (await jsonFile.exists()) {
                  final content = await jsonFile.readAsString();
                  final Map<String, dynamic> data = jsonDecode(content);

                  data["sprite"] = "file://${target.path}/sprites/v4/light";
                  data["glyphs"] =
                      "file://${target.path}/fonts/{fontstack}/{range}.pbf";

                  if (data["sources"] != null &&
                      data["sources"]["vector-tiles"] != null) {
                    data["sources"]["vector-tiles"]["url"] =
                        "pmtiles://${file.path}";
                  }

                  if (mounted) {
                    setState(() {
                      style = jsonEncode(data);
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
          developer.log(
            'Search complete. No matching low pmtiles file found.',
            name: 'MapsScreen',
          );
        } else {
          developer.log(
            'Target map directory does not exist on disk.',
            name: 'MapsScreen',
          );
        }
      } catch (error) {
        developer.log(
          'Error initializing map: $error',
          name: 'MapsScreen',
          error: error,
          stackTrace: StackTrace.current,
        );
      }

      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }();
  }

  void zoomIn() {
    if (controller == null) return;
    setState(() {
      zoom = (zoom + 1).clamp(0.0, 22.0);
    });
    controller!.moveCamera(zoom: zoom);
  }

  void zoomOut() {
    if (controller == null) return;
    setState(() {
      zoom = (zoom - 1).clamp(0.0, 22.0);
    });
    controller!.moveCamera(zoom: zoom);
  }

  Future<void> goToCurrentLocation() async {
    if (controller == null) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();
      controller!.moveCamera(
        center: Geographic(lon: position.longitude, lat: position.latitude),
      );
    } catch (error) {
      developer.log('Location tracking failure: $error', name: 'MapsScreen');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            options: MapOptions(
              initCenter: const Geographic(lon: 0, lat: 20),
              initZoom: zoom,
              initPitch: 0,
              initStyle: style,
            ),
            onMapCreated: (map) {
              controller = map;
              developer.log(
                'MapLibre controller successfully instantiated.',
                name: 'MapsScreen',
              );
            },
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'zoom_in',
                    mini: true,
                    onPressed: zoomIn,
                    child: Icon(PhosphorIcons.plus()),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'zoom_out',
                    mini: true,
                    onPressed: zoomOut,
                    child: Icon(PhosphorIcons.minus()),
                  ),
                  const SizedBox(height: 16),
                  FloatingActionButton(
                    heroTag: 'my_location',
                    onPressed: goToCurrentLocation,
                    child: Icon(PhosphorIcons.crosshair()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
