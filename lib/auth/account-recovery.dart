import 'dart:async';
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:zephyron/main.dart';
import 'dart:developer' as developer;

class AuthAccountRecoveryPage extends StatefulWidget {
  const AuthAccountRecoveryPage({super.key});

  @override
  State<AuthAccountRecoveryPage> createState() =>
      AuthAccountRecoveryPageState();
}

class AuthAccountRecoveryPageState extends State<AuthAccountRecoveryPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController email = TextEditingController();
  String? warning;
  bool disabled = false;
  int countdown = 0;
  Timer? timer;

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Account Recovery',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter the email address associated with your account to receive instructions for account recovery. '
                    'If you don\'t see the email in your inbox, please check your junk or spam folders.',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: key,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Email',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: 'Enter your email',
                          ),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (String? email) {
                            try {
                              if (email == null || email.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!RegExp(
                                r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+\.[a-zA-Z]{2,}$",
                              ).hasMatch(email)) {
                                return 'Please enter a valid email';
                              }
                              if (email.contains(' ')) {
                                return 'Email must not contain spaces';
                              }
                              return null;
                            } catch (error) {
                              developer.log(
                                'Failed to validate user email input: $error',
                                error: error,
                                stackTrace: StackTrace.current,
                                name: 'AuthAccountRecoveryPage.validation',
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
                                'Failed to process email field changes: $error',
                                error: error,
                                stackTrace: StackTrace.current,
                                name: 'AuthAccountRecoveryPage.input',
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: disabled
                        ? null
                        : () async {
                            try {
                              if (key.currentState!.validate()) {
                                try {
                                  await account.createRecovery(
                                    email: email.text,
                                    url: 'http://localhost:8000/reset-password',
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    return;
                                  }

                                  setState(() {
                                    countdown = 60;
                                    disabled = true;
                                  });

                                  timer = Timer.periodic(
                                    const Duration(seconds: 1),
                                    (timer) {
                                      try {
                                        if (!mounted) {
                                          timer.cancel();
                                          return;
                                        }
                                        if (countdown > 0) {
                                          setState(() => countdown--);
                                        } else {
                                          timer.cancel();
                                          setState(() => disabled = false);
                                        }
                                      } catch (error) {
                                        developer.log(
                                          'Failed during cooldown timer execution: $error',
                                          error: error,
                                          stackTrace: StackTrace.current,
                                          name: 'AuthAccountRecoveryPage.timer',
                                        );
                                        timer.cancel();
                                      }
                                    },
                                  );
                                } on AppwriteException catch (error) {
                                  setState(() {
                                    warning = switch (error.type) {
                                      'user_not_found' =>
                                        'No user found with this email address.',
                                      'user_invalid_credentials' =>
                                        'Please enter a valid email address.',
                                      'rate_limit_exceeded' =>
                                        'Too many attempts. Please try again later.',
                                      _ =>
                                        'Error recovering account. Please try again.',
                                    };
                                  });
                                  developer.log(
                                    'Appwrite server rejected recovery request: [${error.type}] ${error.message}',
                                    error: error,
                                    stackTrace: StackTrace.current,
                                    name: 'AuthAccountRecoveryPage.recovery',
                                  );
                                } catch (error) {
                                  setState(
                                    () => warning =
                                        'An unexpected error occurred.',
                                  );
                                  developer.log(
                                    'Unexpected internal exception during authentication recovery: $error',
                                    error: error,
                                    stackTrace: StackTrace.current,
                                    name: 'AuthAccountRecoveryPage.recovery',
                                  );
                                }
                              }
                            } catch (error) {
                              developer.log(
                                'Failed to process authentication form submission: $error',
                                error: error,
                                stackTrace: StackTrace.current,
                                name: 'AuthAccountRecoveryPage.submission',
                              );
                            }
                          },
                    child: disabled
                        ? Text('Retry in $countdown seconds')
                        : const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      developer.log(
        'Failed to render account recovery user interface layout: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'AuthAccountRecoveryPage.build',
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      timer?.cancel();
      email.dispose();
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to cleanly release widget layout resources: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'AuthAccountRecoveryPage.dispose',
      );
    }
  }
}
