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
const channel = MethodChannel('zephyron/security');

Future<void> main() async {
  runZonedGuarded(
        () async {
      WidgetsFlutterBinding.ensureInitialized();

      try {
        final authorized = await channel.invokeMethod<bool>('verifyAppSignature');
        if (kReleaseMode && authorized != true) {
          exit(0);
        }
      } catch (error) {
        if (kReleaseMode) {
          exit(0);
        }
      }

      const hash = String.fromEnvironment(
        'APP_CERT_HASH', // TODO: Remember to feed your .env with google's official signature
        defaultValue: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      );

      final configuration = TalsecConfig(
        androidConfig: AndroidConfig(
          packageName: 'com.aveloux.zephyron',
          signingCertHashes: [hash],
          supportedStores: ['com.android.vending'],
        ),
        watcherMail: 'security@aveloux.com',
        isProd: kReleaseMode,
      );

      void quit() {
        if (kReleaseMode) {
          exit(0);
        } else {
          developer.log('Threat', name: 'security');
        }
      }

      final guard = ThreatCallback(
        onAppIntegrity: quit,
        onHooks: quit,
        onPrivilegedAccess: quit,
        onSimulator: quit,
      );

      Talsec.instance.attachListener(guard);
      await Talsec.instance.start(configuration);

      final folder = await getApplicationSupportDirectory();
      final path = '${folder.path}/tor';

      const binary = '/data/data/com.aveloux.zephyron/lib/libobfs4proxy.so';
      const bridge = 'obfs4 192.0.2.1:443 74A91B415C22D956A41B32E0B4AD7B02844E3D5C cert=q2325A... iat-mode=0';

      if (File(binary).existsSync()) {
        await Isolate.run(() {
          final client = Tor(
            path: path,
            binary: binary,
            bridge: bridge,
          );
          client.boot();
        });
      } else {
        developer.log('Missing', name: 'main');
      }

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
        'Error',
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
      home: builder?.call(context) ?? const Scaffold(body: Center(child: CircularProgressIndicator())),
      onGenerateRoute: (RouteSettings settings) {
        final maker = routes[settings.name];
        if (maker != null) {
          return MaterialPageRoute(builder: (context) => maker(context));
        }
        return null;
      },
    );
  }
}