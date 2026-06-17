import 'dart:core' as core;
import 'package:zephyron/enums.dart';

class Map {
  final Appearance appearance;
  final core.double cache;
  final core.bool volatile;
  final core.int fps;

  const Map({
    this.appearance = Appearance.light,
    this.cache = 500.0,
    this.volatile = true,
    this.fps = 60,
  });

  factory Map.fromJson(core.Map<core.String, core.dynamic> json) {
    return Map(
      appearance: Appearance.values.firstWhere(
        (element) => element.name == json['appearance'],
        orElse: () => Appearance.light,
      ),
      cache: (json['cache'] as core.num?)?.toDouble() ?? 500.0,
      volatile: json['volatile'] as core.bool? ?? true,
      fps: json['fps'] as core.int? ?? 60,
    );
  }

  core.Map<core.String, core.dynamic> toJson() => {
    'appearance': appearance.name,
    'cache': cache,
    'volatile': volatile,
    'fps': fps,
  };

  Map copyWith({
    Appearance? appearance,
    core.double? cache,
    core.bool? volatile,
    core.int? fps,
  }) {
    return Map(
      appearance: appearance ?? this.appearance,
      cache: cache ?? this.cache,
      volatile: volatile ?? this.volatile,
      fps: fps ?? this.fps,
    );
  }
}
