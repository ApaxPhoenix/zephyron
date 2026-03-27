import 'package:flutter/material.dart';
import 'package:zephyron/splash.dart';
import 'package:zephyron/auth/index.dart';
import 'package:zephyron/auth/middleware.dart';
import 'package:zephyron/auth/account-recovery.dart';
import 'package:zephyron/dashboard/index.dart';
import 'package:zephyron/network/index.dart';
import 'package:zephyron/network/settings.dart';
import 'package:zephyron/network/middleware.dart';

final Map<String, WidgetBuilder> routes = {
  '/': (context) => const SplashScreen(),
  '/auth': (context) => const AuthScreen(),
  '/auth/middleware': (context) => const AuthMiddlewareScreen(),
  '/auth/account-recovery': (context) => const AuthAccountRecoveryPage(),
  '/dashboard': (context) => const DashboardScreen(),
  '/network': (context) => const NetworkScreen(),
  '/network/middleware': (context) => const NetworkMiddlewareScreen(),
  '/network/settings': (context) => const NetworkSettingsPage(),
};
