import 'dart:async';
import 'dart:developer' as developer;
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/sql/session.dart';
import 'package:zephyron/wrappers/tor.dart';

Identity make(String seed) => Identity.fromInput(seed);

dynamic pack(String key) => blob(key);

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => SignUpPageState();
}

class SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController passphrase = TextEditingController();
  final TextEditingController confirmation = TextEditingController();

  bool hidden = true;
  bool agreed = false;
  bool busy = false;
  String? seed;
  String? warning;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    try {
      seed = bip39.generateMnemonic();
      developer.log(
        'Generated new mnemonic seed phrase for identity creation',
        name: 'SignUpPageState.initState',
        level: 800,
      );
    } catch (error) {
      developer.log(
        'Failed to generate random mnemonic seed phrase via BIP-39',
        name: 'SignUpPageState.initState',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  void copy(String text) {
    try {
      Clipboard.setData(ClipboardData(text: text));
      developer.log(
        'Copied mnemonic seed phrase to system clipboard',
        name: 'SignUpPageState.copy',
        level: 800,
      );

      timer?.cancel();
      timer = Timer(const Duration(seconds: 30), () async {
        try {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          if (data?.text == text) {
            await Clipboard.setData(const ClipboardData(text: ''));
            developer.log(
              'Cleared copied mnemonic seed phrase from system clipboard after timeout',
              name: 'SignUpPageState.copy',
              level: 500,
            );
          }
        } catch (error) {
          developer.log(
            'Failed to auto-clear mnemonic seed phrase from clipboard during timer execution',
            name: 'SignUpPageState.copy',
            level: 1000,
            error: error,
            stackTrace: StackTrace.current,
          );
        }
      });
    } catch (error) {
      developer.log(
        'Failed to copy mnemonic seed phrase to system clipboard',
        name: 'SignUpPageState.copy',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
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
                          obscureText: hidden,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: 'Enter encryption passphrase',
                            errorText: warning,
                            suffixIcon: IconButton(
                              icon: Icon(
                                hidden
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () => setState(() => hidden = !hidden),
                            ),
                          ),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          onChanged: (_) {
                            if (warning != null) {
                              setState(() => warning = null);
                            }
                          },
                          validator: (input) {
                            if (input == null || input.isEmpty) {
                              return 'Please enter a local passphrase';
                            }
                            if (input.length < 8) {
                              return 'Passphrase must be at least 8 characters';
                            }
                            return null;
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
                          obscureText: hidden,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: 'Re-enter encryption passphrase',
                          ),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (input) {
                            if (input != passphrase.text) {
                              return 'Passphrases do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: agreed && !busy && seed != null
                                ? () async {
                              try {
                                if (key.currentState!.validate()) {
                                  developer.log(
                                    'Starting identity generation and network initialization workflow',
                                    name: 'SignUpPageState.createIdentity',
                                    level: 800,
                                  );

                                  final mnemonic = seed!;

                                  setState(() {
                                    busy = true;
                                    warning = null;
                                  });

                                  final user = await compute(make, mnemonic);

                                  if (user.private.length != 128) {
                                    final exception = StateError(
                                      'Invalid key length: expected 128 hex chars',
                                    );
                                    developer.log(
                                      'Private key validation failed: generated seed resulted in invalid key length',
                                      name: 'SignUpPageState.createIdentity',
                                      level: 1000,
                                      error: exception,
                                      stackTrace: StackTrace.current,
                                    );
                                    throw exception;
                                  }

                                  await Session.compose(
                                    Session.label,
                                    passphrase.text,
                                    user,
                                    mnemonic,
                                  );

                                  final folder = await getApplicationSupportDirectory();
                                  final path = '${folder.path}/tor';

                                  final rawKey = user.private;
                                  final encoded = await compute(pack, rawKey);
                                  final host = await publish(path, encoded);

                                  final tor = host.replaceAll('.onion', '');
                                  final base = user.address.replaceAll('.onion', '');

                                  if (tor.length >= 50 && base.length >= 50 && tor.substring(0, 50) != base.substring(0, 50)) {
                                    final exception = StateError(
                                      'Published address pubkey does not match identity '
                                          '(tor=$host expected=${user.address}).',
                                    );
                                    developer.log(
                                      'Published Tor address public key mismatch: published host address does not match generated identity address',
                                      name: 'SignUpPageState.createIdentity',
                                      level: 1000,
                                      error: exception,
                                      stackTrace: StackTrace.current,
                                    );
                                    throw exception;
                                  }

                                  developer.log(
                                    'Completed identity creation, session composition, and network publishing successfully',
                                    name: 'SignUpPageState.createIdentity',
                                    level: 800,
                                  );

                                  if (mounted) {
                                    Navigator.of(context).pushReplacementNamed(
                                      '/dashboard',
                                      arguments: user,
                                    );
                                  }
                                } else {
                                  developer.log(
                                    'Identity creation form validation failed due to invalid user input',
                                    name: 'SignUpPageState.createIdentity',
                                    level: 900,
                                  );
                                }
                              } catch (error) {
                                developer.log(
                                  'Failed to initialize network or save identity credentials',
                                  name: 'SignUpPageState.createIdentity',
                                  level: 1000,
                                  error: error,
                                  stackTrace: StackTrace.current,
                                );

                                setState(
                                      () => warning = 'Failed to initialize network or save identity credentials',
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => busy = false);
                                }
                              }
                            }
                                : null,
                            child: busy
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
                          value: agreed,
                          onChanged: (input) =>
                              setState(() => agreed = input ?? false),
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
        'Failed to build SignUpPage UI widget tree',
        name: 'SignUpPage.build',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    try {
      passphrase.clear();
      passphrase.dispose();

      confirmation.clear();
      confirmation.dispose();

      seed = null;
      warning = null;

      developer.log(
        'Disposed SignUpPageState input controllers, state resources, and clipboard timers',
        name: 'SignUpPageState.dispose',
        level: 500,
      );
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to cleanly release input controllers or cancel timers during dispose',
        name: 'SignUpPageState.dispose',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }
}