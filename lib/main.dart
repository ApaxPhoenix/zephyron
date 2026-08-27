import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'package:cloudflare/cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/routes.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/wrappers/tor.dart';

late final R2API bucket;

Future main() async {
  runZonedGuarded(
        () async {
      WidgetsFlutterBinding.ensureInitialized();

      final directory = await getApplicationSupportDirectory();
      final path = '${directory.path}/tor';

      await Isolate.run(() {
        final instance = Tor(path: path);
        instance.boot();
      });

      bucket = R2API(
        accountId: const String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID'),
        credentials: const R2Credentials(
          accessKeyId: String.fromEnvironment('R2_ACCESS_KEY_ID'),
          secretAccessKey: String.fromEnvironment('R2_SECRET_ACCESS_KEY'),
        ),
      );

      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      runApp(const MyApp());
    },
        (dynamic error, dynamic stack) {
      developer.log(
        'Uncaught application error',
        name: 'main',
        level: 1200,
        error: error,
        stackTrace: stack,
      );
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  String route = '/';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final builder = routes[route];

    return MaterialApp(
      title: 'Zephyron',
      debugShowMaterialGrid: false,
      debugShowCheckedModeBanner: false,
      showSemanticsDebugger: false,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      theme: MediaQuery.of(context).platformBrightness == Brightness.light
          ? Pallete.lightTheme(context)
          : Pallete.darkTheme(context),
      home:
      builder?.call(context) ??
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      onGenerateRoute: (RouteSettings settings) {
        final builder = routes[settings.name];
        if (builder != null) {
          return MaterialPageRoute(builder: (context) => builder(context));
        }
        return null;
      },
    );
  }
}