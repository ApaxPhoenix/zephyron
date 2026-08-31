import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyron/sql/session.dart';
import 'package:zephyron/wrappers/tor.dart';

class LogInPage extends StatefulWidget {
  const LogInPage({super.key});

  @override
  State<LogInPage> createState() => LogInPageState();
}

class LogInPageState extends State<LogInPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController passphrase = TextEditingController();
  bool obscured = true;
  bool loading = false;
  String? warning;

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('assets/logo.png', width: 100, height: 100),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.05),
                  Text(
                    'Unlock Database',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter your local passphrase or seed phrase to decrypt your Tor identity keypair and local store.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: key,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Passphrase or Seed',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: passphrase,
                          obscureText: obscured,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: 'Enter local passphrase or 12-word seed',
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
                            if (value == null || value.isEmpty) {
                              return 'Please enter your passphrase';
                            }
                            return warning;
                          },
                          onChanged: (_) {
                            if (warning != null) {
                              setState(() => warning = null);
                            }
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: loading
                                ? null
                                : () async {
                                    try {
                                      if (key.currentState!.validate()) {
                                        developer.log(
                                          'Starting database decryption and Tor service publication workflow',
                                          name: 'LogInPageState.unlockDatabase',
                                          level: 800,
                                        );

                                        final navigator = Navigator.of(context);
                                        setState(() {
                                          loading = true;
                                          warning = null;
                                        });

                                        final identity = await Session.open(
                                          Session.label,
                                          passphrase.text,
                                        );

                                        final folder =
                                            await getApplicationSupportDirectory();
                                        final path = '${folder.path}/tor';
                                        final address = await publish(
                                          path,
                                          blob(identity.private),
                                        );

                                        final tor = address.replaceAll(
                                          '.onion',
                                          '',
                                        );
                                        final base = identity.address
                                            .replaceAll('.onion', '');

                                        if (tor.length >= 50 &&
                                            base.length >= 50 &&
                                            tor.substring(0, 50) !=
                                                base.substring(0, 50)) {
                                          final exception = StateError(
                                            'Published address pubkey does not match identity '
                                            '(tor=$address expected=${identity.address}).',
                                          );
                                          developer.log(
                                            'Published Tor address public key mismatch: derived service address does not match expected identity address',
                                            name:
                                                'LogInPageState.unlockDatabase',
                                            level: 1000,
                                            error: exception,
                                            stackTrace: StackTrace.current,
                                          );
                                          throw exception;
                                        }

                                        developer.log(
                                          'Database decryption and network publishing completed successfully',
                                          name: 'LogInPageState.unlockDatabase',
                                          level: 800,
                                        );

                                        if (mounted) {
                                          navigator.pushNamedAndRemoveUntil(
                                            '/dashboard',
                                            (route) => false,
                                            arguments: identity,
                                          );
                                        }
                                      } else {
                                        developer.log(
                                          'Database decryption form validation failed due to invalid user input',
                                          name: 'LogInPageState.unlockDatabase',
                                          level: 900,
                                        );
                                      }
                                    } catch (error) {
                                      developer.log(
                                        'Failed to decrypt store or publish Tor onion service with provided credentials',
                                        name: 'LogInPageState.unlockDatabase',
                                        level: 1000,
                                        error: error,
                                        stackTrace: StackTrace.current,
                                      );

                                      setState(
                                        () => warning =
                                            'Failed to decrypt store with provided credentials',
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() => loading = false);
                                      }
                                    }
                                  },
                            child: loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Decrypt Identity'),
                          ),
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
        'Failed to build LogInPage UI widget tree',
        name: 'LogInPage.build',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      passphrase.clear();
      passphrase.dispose();

      developer.log(
        'Disposed LogInPageState input controllers and state resources',
        name: 'LogInPageState.dispose',
        level: 500,
      );
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to release input text controllers cleanly during dispose',
        name: 'LogInPageState.dispose',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }
}
