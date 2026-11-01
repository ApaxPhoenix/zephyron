import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:cloudflare/cloudflare.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freerasp/freerasp.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:zephyron/routes.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/launch.dart';
import 'package:zephyron/services/shield.dart';
import 'package:zephyron/services/tripwire.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/wrappers/tor.dart';

late final R2API bucket;
const link = MethodChannel('security');

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // The zephyron:// link the app was opened with, and any that arrive
      // while it runs.
      Launch.channel.setMethodCallHandler((call) async {
        if (call.method == 'open' && call.arguments is String) {
          Launch.wanted.value = call.arguments as String;
        }
      });
      try {
        final first = await Launch.channel.invokeMethod<String>('initial');
        if (first != null && first.isNotEmpty) Launch.wanted.value = first;
      } on MissingPluginException {
        // Platforms that open no links have nothing to hand over.
      } catch (_) {}

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
        } catch (error) {
          developer.log(
            'Failed to execute platform authorization method channel invocation',
            name: 'main.security.signature',
            level: 1200,
            error: error,
            stackTrace: StackTrace.current,
          );
          exit(0);
        }

        // Without the signing certificate hash freeRASP can only report a
        // tampered app and the process would close itself, so monitoring is
        // skipped for builds made without --dart-define-from-file=.env.
        const hash = String.fromEnvironment('APP_CERT_HASH');
        if (hash.isEmpty) {
          developer.log(
            'APP_CERT_HASH was not provided at build time, runtime threat monitoring is disabled for this build',
            name: 'main.security.freerasp',
            level: 900,
          );
        }

        if (hash.isNotEmpty) {
          try {
            final setup = TalsecConfig(
              androidConfig: AndroidConfig(
                packageName: 'com.aveloux.zephyron',
                signingCertHashes: [hash],
                supportedStores: ['com.android.vending'],
              ),
              watcherMail: 'security@aveloux.com',
              isProd: true,
            );

            final guard = Tripwire.callback();

            Talsec.instance.attachListener(guard);
            await Talsec.instance.start(setup);
          } catch (error) {
            developer.log(
              'Failed to configure or start Talsec security monitoring service',
              name: 'main.security.freerasp',
              level: 1000,
              error: error,
              stackTrace: StackTrace.current,
            );
          }
        }
      }

      try {
        final folder = await getApplicationSupportDirectory();
        final location = '${folder.path}/tor';
        unawaited(
          Sentinel.summon().prepare(location).catchError((error) {
            developer.log(
              'Encountered unhandled error while booting shared Tor daemon',
              name: 'main.sentinel',
              level: 1000,
              error: error,
              stackTrace: StackTrace.current,
            );
          }),
        );
      } catch (error) {
        developer.log(
          'Encountered unhandled error while resolving shared Tor daemon location',
          name: 'main.sentinel',
          level: 1000,
          error: error,
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
      } catch (error) {
        developer.log(
          'Failed to instantiate Cloudflare R2 API client bucket instance',
          name: 'main.r2',
          level: 1000,
          error: error,
          stackTrace: StackTrace.current,
        );
      }

      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      runApp(const Zephyron());
    },
    (dynamic error, dynamic _) {
      developer.log(
        'Unhandled asynchronous error caught inside top-level runZonedGuarded boundary',
        name: 'main.uncaught',
        level: 1200,
        error: error,
        stackTrace: StackTrace.current,
      );
    },
  );
}

class Zephyron extends StatefulWidget {
  const Zephyron({super.key});

  @override
  State<Zephyron> createState() => _Zephyron();
}

class _Zephyron extends State<Zephyron> with WidgetsBindingObserver {
  static final GlobalKey<NavigatorState> navigator = GlobalKey();
  String route = '/';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The app icon's long-press menu. A panic wipe starts at once; the rest
    // wait for an identity to be unlocked.
    try {
      const actions = QuickActions();
      actions.initialize((type) {
        if (type == 'panic') {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => navigator.currentState?.pushNamed('/panic'),
          );
        } else {
          Launch.wanted.value = type;
        }
      });
      actions.setShortcutItems(const [
        ShortcutItem(type: 'trustee', localizedTitle: 'Add a trustee'),
        ShortcutItem(type: 'code', localizedTitle: 'Show my code'),
        ShortcutItem(type: 'lock', localizedTitle: 'Lock now'),
        ShortcutItem(type: 'panic', localizedTitle: 'Panic wipe'),
      ]);
    } catch (error) {
      developer.log(
        'Failed to register the launcher shortcuts',
        name: '_Zephyron.shortcuts',
        level: 900,
        error: error,
      );
    }
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (error) {
      developer.log(
        'Failed to cleanly unbind lifecycle observer during _Zephyron disposal',
        name: '_Zephyron.dispose',
        level: 800,
        error: error,
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

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Courier.instance.theme,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: navigator,
          title: 'Zephyron',
          debugShowMaterialGrid: false,
          debugShowCheckedModeBanner: false,
          showSemanticsDebugger: false,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          theme: Palette.day(context),
          darkTheme: Palette.compose(context, Brightness.dark),
          themeMode: mode,
          builder: (context, child) => Curtain(
            enabled: Courier.instance.shielded,
            child: child ?? const SizedBox.shrink(),
          ),
          home:
              page?.call(context) ??
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          onGenerateRoute: (RouteSettings info) {
            final page = routes[info.name];
            if (page != null) {
              return MaterialPageRoute(
                settings: info,
                builder: (context) => page(context),
              );
            }

            developer.log(
              'Requested route resolution failed: "${info.name}" is not registered in routes table',
              name: '_Zephyron.onGenerateRoute',
              level: 900,
              stackTrace: StackTrace.current,
            );
            return null;
          },
        );
      },
    );
  }
}
