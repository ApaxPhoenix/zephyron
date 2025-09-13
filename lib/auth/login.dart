import 'package:flutter/material.dart';
import 'dart:developer' as developer;

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
                            try {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your passphrase';
                              }
                              return warning;
                            } catch (error) {
                              developer.log(
                                'Failed to evaluate passphrase rule validations: $error',
                                error: error,
                                stackTrace: StackTrace.current,
                                name: 'LogInPage.validation',
                              );
                              return 'An unexpected error occurred.';
                            }
                          },
                          onChanged: (_) {
                            try {
                              if (!mounted) return;
                              setState(() => warning = null);
                            } catch (error) {
                              developer.log(
                                'Failed to reset warning on passphrase edit: $error',
                                error: error,
                                stackTrace: StackTrace.current,
                                name: 'LogInPage.input',
                              );
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
                                        setState(() {
                                          loading = true;
                                          warning = null;
                                        });
                                        try {
                                          if (mounted) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  Navigator.pushNamedAndRemoveUntil(
                                                    context,
                                                    '/dashboard',
                                                    (route) => false,
                                                  );
                                                });
                                          }
                                        } catch (error) {
                                          setState(
                                            () => warning =
                                                'Failed to decrypt store with provided credentials',
                                          );
                                          developer.log(
                                            'Keypair derivation or vault decryption failed: $error',
                                            error: error,
                                            stackTrace: StackTrace.current,
                                            name: 'LogInPage.decrypt',
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => loading = false);
                                          }
                                        }
                                      }
                                    } catch (error) {
                                      developer.log(
                                        'Failed to process submit action workflow: $error',
                                        error: error,
                                        stackTrace: StackTrace.current,
                                        name: 'LogInPage.submission',
                                      );
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
        'Failed to render log in view interface layout: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'LogInPage.build',
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      passphrase.dispose();
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to release input controllers: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'LogInPage.dispose',
      );
    }
  }
}
