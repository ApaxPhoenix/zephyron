import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => SignUpPageState();
}

class SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController passphrase = TextEditingController();
  final TextEditingController confirmation = TextEditingController();
  bool obscured = true;
  bool toggled = false;
  bool loading = false;
  String? seed;
  String? warning;

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
                            seed ??
                                'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('Copy Seed to Clipboard'),
                            onPressed: () {
                              try {
                                Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        seed ??
                                        'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima',
                                  ),
                                );
                              } catch (error) {
                                developer.log(
                                  'Failed to write seed phrase payload to system clipboard: $error',
                                  error: error,
                                  stackTrace: StackTrace.current,
                                  name: 'SignUpPage.clipboard',
                                );
                              }
                            },
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
                            onPressed: toggled && !loading
                                ? () async {
                                    try {
                                      if (key.currentState!.validate()) {
                                        setState(() {
                                          loading = true;
                                          warning = null;
                                        });
                                        try {
                                          if (mounted) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  Navigator.pushReplacementNamed(
                                                    context,
                                                    '/dashboard',
                                                  );
                                                });
                                          }
                                        } catch (error) {
                                          setState(
                                            () => warning =
                                                'Failed to initialize and store local keypair',
                                          );
                                          developer.log(
                                            'Failed to write generated identity keypair to secure storage: $error',
                                            error: error,
                                            stackTrace: StackTrace.current,
                                            name: 'SignUpPage.storage',
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => loading = false);
                                          }
                                        }
                                      }
                                    } catch (error) {
                                      developer.log(
                                        'Failed to process submission workflow execution: $error',
                                        error: error,
                                        stackTrace: StackTrace.current,
                                        name: 'SignUpPage.submission',
                                      );
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
    try {
      passphrase.dispose();
      confirmation.dispose();
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
