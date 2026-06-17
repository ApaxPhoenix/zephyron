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
                if (mounted)
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/dashboard',
                    (route) => false,
                  );
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
                      'Error sending verification: $error',
                      name: 'AuthMiddlewareScreen.send',
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
                          'Error polling: $error',
                          name: 'AuthMiddlewareScreen.poll',
                          error: error,
                        );
                        throw error;
                      });
                } catch (error) {
                  developer.log(
                    'Error in timer: $error',
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
              'Initialization error: $error',
              name: 'AuthMiddlewareScreen.init',
              error: error,
            );
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.pushReplacementNamed(context, '/');
              });
            }
            throw error;
          });
    } catch (error) {
      developer.log(
        'Global init error: $error',
        name: 'AuthMiddlewareScreen.init',
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
                  Text(
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
                                    'Resend error: $error',
                                    name: 'AuthMiddlewareScreen.resend',
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
        'Build error: $error',
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
        'Dispose error: $error',
        name: 'AuthMiddlewareScreen.dispose',
        error: error,
      );
    }
  }
}
