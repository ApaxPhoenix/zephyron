import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/models/identity.dart';
import 'package:cryptography/cryptography.dart';
import 'package:zephyron/wrappers/tor.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => SignUpPageState();
}

class SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController passphrase = TextEditingController();
  final TextEditingController confirmation = TextEditingController();
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  bool obscured = true;
  bool toggled = false;
  bool loading = false;
  String? seed;
  String? warning;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    try {
      seed = bip39.generateMnemonic();
    } catch (error) {
      developer.log(
        'Failed to generate mnemonic seed: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'SignUpPage.initState',
      );
    }
  }

  void copy(String text) {
    Clipboard.setData(ClipboardData(text: text));

    timer?.cancel();
    timer = Timer(const Duration(seconds: 30), () async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
        developer.log('Clipboard automatically cleared', name: 'SignUpPage.clipboard');
      }
    });
  }

  Future<String> encrypt(String text, String pass) async {
    final cipher = AesGcm.with256bits();
    final hasher = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );

    final salt = List<int>.generate(16, (count) => count);
    final unlock = await hasher.deriveKeyFromPassword(
      password: pass,
      nonce: salt,
    );

    final box = await cipher.encrypt(
      utf8.encode(text),
      secretKey: unlock,
    );

    return base64.encode(box.concatenation());
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('assets/logo.png', width: 100, height: 100),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.05),
                  Text(
                    'Generate Identity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your identity exists exclusively on your device as an Ed25519 keypair and v3 Onion service address. Write down your recovery seed phrase.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: key,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recovery Seed Phrase',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            seed ?? 'Generating seed phrase...',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('Copy Seed to Clipboard'),
                            onPressed: seed != null
                                ? () => copy(seed!)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Local Encrypted Passphrase',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: passphrase,
                          obscureText: obscured,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: 'Enter encryption passphrase',
                            errorText: warning,
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscured
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () =>
                                  setState(() => obscured = !obscured),
                            ),
                          ),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          onChanged: (_) {
                            if (warning != null) {
                              setState(() => warning = null);
                            }
                          },
                          validator: (value) {
                            try {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a local passphrase';
                              }
                              if (value.length < 8) {
                                return 'Passphrase must be at least 8 characters';
                              }
                              return null;
                            } catch (error) {
                              developer.log(
                                'Failed to evaluate passphrase validation rule: $error',
                                error: error,
                                stackTrace: StackTrace.current,
                                name: 'SignUpPage.validation',
                              );
                              return 'An unexpected error occurred.';
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Confirm Local Passphrase',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: confirmation,
                          obscureText: obscured,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: 'Re-enter encryption passphrase',
                          ),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) {
                            try {
                              if (value != passphrase.text) {
                                return 'Passphrases do not match';
                              }
                              return null;
                            } catch (error) {
                              developer.log(
                                'Failed to evaluate confirmation passphrase validation: $error',
                                error: error,
                                stackTrace: StackTrace.current,
                                name: 'SignUpPage.validation',
                              );
                              return 'An unexpected error occurred.';
                            }
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: toggled && !loading && seed != null
                                ? () async {
                              try {
                                if (key.currentState!.validate()) {
                                  final navigator = Navigator.of(context);
                                  setState(() {
                                    loading = true;
                                    warning = null;
                                  });

                                  final encryptedSeed = await encrypt(
                                    seed!,
                                    passphrase.text,
                                  );

                                  const options = AndroidOptions();

                                  await storage.write(
                                    key: 'seed',
                                    value: encryptedSeed,
                                    aOptions: options,
                                  );

                                  final path = '${(await getApplicationSupportDirectory()).path}/tor';
                                  final torDir = Directory(path);
                                  if (!await torDir.exists()) {
                                    await torDir.create(recursive: true);
                                  }

                                  if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
                                    await Process.run('chmod', ['700', path]);
                                  }

                                  final socketFile = File('$path/control.sock');
                                  if (!await socketFile.exists()) {
                                    unawaited(Isolate.run(() {
                                      final daemon = Tor(path: path, binary: '');
                                      daemon.boot();
                                    }).catchError((err, stack) {
                                      developer.log('Tor daemon error: $err', error: err, stackTrace: stack);
                                    }));

                                    int retries = 0;
                                    while (!await socketFile.exists() && retries < 30) {
                                      await Future.delayed(const Duration(milliseconds: 500));
                                      retries++;
                                    }
                                  }

                                  final cookie = File('$path/cookie');
                                  if (await cookie.exists() && (Platform.isAndroid || Platform.isLinux || Platform.isMacOS)) {
                                    await Process.run('chmod', ['600', cookie.path]);
                                  }

                                  if (!await socketFile.exists()) {
                                    throw Exception('Timed out waiting for Tor control socket.');
                                  }

                                  final identity = Identity.fromInput(seed!);
                                  if (identity.private.length != 128) {
                                    throw Exception('Invalid key length: expected 128 hex chars');
                                  }

                                  final raw = Uint8List(64);
                                  for (var i = 0; i < 64; i++) {
                                    raw[i] = int.parse(
                                      identity.private.substring(i * 2, i * 2 + 2),
                                      radix: 16,
                                    );
                                  }
                                  final secretKey = base64.encode(raw);
                                  raw.fillRange(0, raw.length, 0);

                                  final socket = await Socket.connect(
                                    InternetAddress('$path/control.sock', type: InternetAddressType.unix),
                                    0,
                                  );

                                  final lines = socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());

                                  final bytes = await cookie.readAsBytes();
                                  final hex = bytes.map((bytes) => bytes.toRadixString(16).padLeft(2, '0')).join();

                                  socket.write('AUTHENTICATE $hex\r\n');
                                  socket.write('ADD_ONION ED25519-V3:$secretKey Port=80,127.0.0.1:8080\r\n');
                                  await socket.flush();

                                  final response = await lines.first;
                                  if (!response.startsWith('250')) {
                                    throw Exception('Tor control command failed: $response');
                                  }

                                  await socket.close();

                                  developer.log(
                                    'Created, secured, and published Tor Identity: ${identity.address}',
                                    name: 'SignUpPage.identity',
                                  );

                                  navigator.pushReplacementNamed(
                                    '/dashboard',
                                    arguments: identity,
                                  );
                                }
                              } catch (error) {
                                setState(
                                      () => warning = 'Network initialization failed: ${error.toString().split('\n').first}',
                                );
                                developer.log(
                                  'Failed to complete secure signup: $error',
                                  error: error,
                                  stackTrace: StackTrace.current,
                                  name: 'SignUpPage.submission',
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => loading = false);
                                }
                              }
                            }
                                : null,
                            child: loading
                                ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                                : const Text('Create Identity'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          title: Text.rich(
                            TextSpan(
                              text: 'I understand that ',
                              style: DefaultTextStyle.of(context).style,
                              children: const [
                                TextSpan(
                                  text: 'no central server stores my keypair',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text:
                                  '. If I lose my seed phrase or local passphrase, my account and messages cannot be recovered.',
                                ),
                              ],
                            ),
                          ),
                          value: toggled,
                          onChanged: (value) =>
                              setState(() => toggled = value ?? false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      developer.log(
        'Failed to render identity creation view layout: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'SignUpPage.build',
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    try {
      passphrase.text = '0' * passphrase.text.length;
      passphrase.clear();
      passphrase.dispose();

      confirmation.text = '0' * confirmation.text.length;
      confirmation.clear();
      confirmation.dispose();

      seed = null;
      warning = null;
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to release input controllers cleanly: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'SignUpPage.dispose',
      );
    }
  }
}