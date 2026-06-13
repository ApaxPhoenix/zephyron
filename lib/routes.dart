import 'package:flutter/material.dart';
import 'package:zephyron/splash.dart';
import 'package:zephyron/auth/index.dart';
import 'package:zephyron/auth/middleware.dart';
import 'package:zephyron/auth/reset.dart';
import 'package:zephyron/dashboard/index.dart';
import 'package:zephyron/map/index.dart';
import 'package:zephyron/map/assets.dart';

final Map<String, WidgetBuilder> routes = {
  '/': (context) => const SplashScreen(),
  '/auth': (context) => const AuthScreen(),
  '/auth/middleware': (context) => const MiddlewareScreen(),
  '/auth/reset': (context) => const AccountResetScreen(),
  '/dashboard': (context) => const DashboardScreen(),
  '/map': (context) => const MapsScreen(),
  '/map/assets': (context) => const AssetsScreen(),
};
