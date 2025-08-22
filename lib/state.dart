import 'package:flutter/material.dart';
import 'package:zephyron/models/map.dart' as model;

final ValueNotifier<model.Map> notifier = ValueNotifier<model.Map>(
  const model.Map(),
);
