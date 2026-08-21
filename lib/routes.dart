import 'package:flutter/material.dart';
import 'package:zephyron/splash.dart';
import 'package:zephyron/auth/index.dart';
import 'package:zephyron/dashboard/index.dart';
import 'package:zephyron/network/index.dart';
import 'package:zephyron/network/middleware.dart';

final Map<String, WidgetBuilder> routes = {
  '/': (context) => const SplashScreen(),
  '/auth': (context) => const AuthScreen(),
  '/dashboard': (context) => const DashboardScreen(),
  '/network': (context) => const NetworkScreen(),
  '/network/middleware': (context) => const NetworkMiddlewareScreen(),
};
