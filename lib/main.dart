import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'package:cloudflare/cloudflare.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freerasp/freerasp.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/routes.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/wrappers/tor.dart';

late final R2API bucket;
const link = MethodChannel('zephyron/security');

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      if (kReleaseMode) {
        try {
          final pass = await link.invokeMethod<bool>('authorized');
          if (pass != true) {
            developer.log(
              'Application signature verification check returned false or null. Terminating process.',
              name: 'main.security.signature',
              level: 1200,
              stackTrace: StackTrace.current,
            );
            exit(0);
          }
        } catch (fail) {
          developer.log(
            'Failed to execute platform authorization method channel invocation',
            name: 'main.security.signature',
            level: 1200,
            error: fail,
            stackTrace: StackTrace.current,
          );
          exit(0);
        }

        try {
          const hash = String.fromEnvironment(
            'APP_CERT_HASH',
            defaultValue: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          );

          final setup = TalsecConfig(
            androidConfig: AndroidConfig(
              packageName: 'com.aveloux.zephyron',
              signingCertHashes: [hash],
              supportedStores: ['com.android.vending'],
            ),
            watcherMail: 'security@aveloux.com',
            isProd: true,
          );

          void quit(String risk) {
            developer.log(
              'Security runtime detected severe environment threat: $risk. Initiating shutdown.',
              name: 'main.security.threat',
              level: 1200,
              stackTrace: StackTrace.current,
            );
            exit(0);
          }

          final guard = ThreatCallback(
            onAppIntegrity: () => quit('App Integrity Tampered'),
            onHooks: () => quit('Hooking Framework Active'),
            onPrivilegedAccess: () => quit('Privileged Root Access Detected'),
            onSimulator: () => quit('Emulator Environment Detected'),
          );

          Talsec.instance.attachListener(guard);
          await Talsec.instance.start(setup);
        } catch (fail) {
          developer.log(
            'Failed to configure or start Talsec security monitoring service',
            name: 'main.security.freerasp',
            level: 1000,
            error: fail,
            stackTrace: StackTrace.current,
          );
        }
      }

      try {
        final home = await getApplicationSupportDirectory();
        final path = '${home.path}/tor';

        final pack = await link.invokeMethod<String>('packages');
        final exec = '$pack/libobfs4proxy.so';
        const node =
            'obfs4 192.0.2.1:443 74A91B415C22D956A41B32E0B4AD7B02844E3D5C cert=q2325A... iat-mode=0';

        if (exec.isNotEmpty && File(exec).existsSync()) {
          await Isolate.run(() {
            final core = Tor(path: path, binary: exec, bridge: node);
            core.boot();
          });
        } else {
          developer.log(
            'Obfs4proxy native executable binary was not found at expected file path: $exec',
            name: 'main.tor',
            level: 900,
            stackTrace: StackTrace.current,
          );
        }
      } catch (fail) {
        developer.log(
          'Encountered unhandled error while booting Tor proxy client isolate',
          name: 'main.tor',
          level: 1000,
          error: fail,
          stackTrace: StackTrace.current,
        );
      }

      try {
        bucket = R2API(
          accountId: const String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID'),
          credentials: const R2Credentials(
            accessKeyId: String.fromEnvironment('R2_ACCESS_KEY_ID'),
            secretAccessKey: String.fromEnvironment('R2_SECRET_ACCESS_KEY'),
          ),
        );
      } catch (fail) {
        developer.log(
          'Failed to instantiate Cloudflare R2 API client bucket instance',
          name: 'main.r2',
          level: 1000,
          error: fail,
          stackTrace: StackTrace.current,
        );
      }

      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      runApp(const MyApp());
    },
    (dynamic fail, dynamic _) {
      developer.log(
        'Unhandled asynchronous error caught inside top-level runZonedGuarded boundary',
        name: 'main.uncaught',
        level: 1200,
        error: fail,
        stackTrace: StackTrace.current,
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
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (fail) {
      developer.log(
        'Failed to cleanly unbind lifecycle observer during MyAppState disposal',
        name: 'MyAppState.dispose',
        level: 800,
        error: fail,
        stackTrace: StackTrace.current,
      );
    }
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
    final page = routes[route];

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
          page?.call(context) ??
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      onGenerateRoute: (RouteSettings info) {
        final page = routes[info.name];
        if (page != null) {
          return MaterialPageRoute(builder: (context) => page(context));
        }

        developer.log(
          'Requested route resolution failed: "${info.name}" is not registered in routes table',
          name: 'MyAppState.onGenerateRoute',
          level: 900,
          stackTrace: StackTrace.current,
        );
        return null;
      },
    );
  }
}
