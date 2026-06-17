import 'dart:async';
import 'dart:developer' as developer;
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zephyron/routes.dart';
import 'package:zephyron/theme.dart';

late final Client client;
late final Account account;
late final Storage storage;
late final Realtime realtime;
late final Databases databases;
late final TablesDB tables;

Future main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      client = Client()
        ..setSelfSigned()
        ..setEndpoint('http://10.0.2.2/v1')
        ..setProject('69951d1500159f9e1d20');
      account = Account(client);
      storage = Storage(client);
      databases = Databases(client);
      tables = TablesDB(client);
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
  String? route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    account
        .get()
        .timeout(const Duration(seconds: 6))
        .then((user) {
          if (mounted) setState(() => route = '/auth/middleware');
        })
        .catchError((error) {
          if (mounted) setState(() => route = '/');
        });
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
    final builder = route != null ? routes[route] : null;

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
