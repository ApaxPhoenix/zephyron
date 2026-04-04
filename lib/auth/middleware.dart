import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zephyron/main.dart';
import 'dart:developer' as developer;

class AuthMiddlewareScreen extends StatefulWidget {
  const AuthMiddlewareScreen({super.key});

  @override
  State<AuthMiddlewareScreen> createState() => AuthMiddlewareScreenState();
}

class AuthMiddlewareScreenState extends State<AuthMiddlewareScreen> {
  Timer? timer;
  Timer? countdown;
  String? email;
  bool disabled = false;
  int count = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    try {
      account
          .get()
          .then((user) {
            if (!mounted) return;
            if (user.emailVerification) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/dashboard',
                    (route) => false,
                  );
                }
              });
            } else {
              setState(() {
                email = user.email;
                loading = false;
              });
              account
                  .createEmailVerification(url: 'https://example.com')
                  .catchError((error) {
                    developer.log(
                      'Failed to dispatch automatic verification challenge email: $error',
                      name: 'AuthMiddlewareScreen.verification',
                      error: error,
                    );
                    throw error;
                  });
              timer = Timer.periodic(const Duration(seconds: 10), (time) {
                try {
                  if (!mounted) {
                    time.cancel();
                    return;
                  }
                  account
                      .get()
                      .then((user) {
                        if (mounted && user.emailVerification) {
                          time.cancel();
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/dashboard',
                            (route) => false,
                          );
                        }
                      })
                      .catchError((error) {
                        developer.log(
                          'Failed to evaluate remote user verification status during sync polling: $error',
                          name: 'AuthMiddlewareScreen.polling',
                          error: error,
                        );
                        throw error;
                      });
                } catch (error) {
                  developer.log(
                    'Failed during verification status engine loop: $error',
                    name: 'AuthMiddlewareScreen.timer',
                    error: error,
                  );
                  time.cancel();
                }
              });
            }
          })
          .catchError((error) {
            developer.log(
              'Failed to retrieve active session parameters during startup profiling: $error',
              name: 'AuthMiddlewareScreen.session',
              error: error,
            );
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/',
                    (route) => false,
                  );
                }
              });
            }
            throw error;
          });
    } catch (error) {
      developer.log(
        'Unexpected structural fault during layout controller initialization: $error',
        name: 'AuthMiddlewareScreen.setup',
        error: error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      if (loading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Verify Your Email',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please check your email for the verification link.',
                    textAlign: TextAlign.center,
                  ),
                  if (email != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      email!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: disabled
                        ? null
                        : () {
                            setState(() {
                              disabled = true;
                              count = 60;
                            });
                            account
                                .createEmailVerification(
                                  url: 'https://example.com',
                                )
                                .catchError((error) {
                                  developer.log(
                                    'Failed to dispatch manual user-requested confirmation challenge: $error',
                                    name: 'AuthMiddlewareScreen.verification',
                                    error: error,
                                  );
                                  throw error;
                                });
                            countdown = Timer.periodic(
                              const Duration(seconds: 1),
                              (timer) {
                                if (!mounted) {
                                  timer.cancel();
                                  return;
                                }
                                if (count > 0) {
                                  setState(() => count--);
                                } else {
                                  timer.cancel();
                                  setState(() => disabled = false);
                                }
                              },
                            );
                          },
                    child: disabled
                        ? Text('Resend in $count seconds')
                        : const Text('Resend Email'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      developer.log(
        'Failed to render verification state fallback user interface: $error',
        name: 'AuthMiddlewareScreen.build',
        error: error,
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      timer?.cancel();
      countdown?.cancel();
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to cleanly terminate long-lived polling worker engines: $error',
        name: 'AuthMiddlewareScreen.dispose',
        error: error,
      );
    }
  }
}
