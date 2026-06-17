import 'package:flutter/material.dart';
import 'package:zephyron/main.dart';
import 'dart:developer' as developer;
import 'dart:async';

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
            if (mounted) {
              if (user.emailVerification) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    Navigator.pushNamed(context, '/dashboard');
                  }
                });
              } else {
                setState(() {
                  email = user.email;
                  loading = false;
                });

                account
                    .createEmailVerification(url: 'https://example.com')
                    .then((_) {
                      developer.log(
                        'Verification email sent',
                        name: 'AuthMiddlewareScreen.send',
                      );
                    })
                    .catchError((error) {
                      developer.log(
                        'Error sending verification: $error',
                        error: error,
                        name: 'AuthMiddlewareScreen.send',
                      );
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
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                Navigator.pushNamed(context, '/dashboard');
                              }
                            });
                          }
                        })
                        .catchError((error) {
                          developer.log(
                            'Error polling: $error',
                            error: error,
                            name: 'AuthMiddlewareScreen.poll',
                          );
                        });
                  } catch (error) {
                    developer.log(
                      'Error: $error',
                      error: error,
                      name: 'AuthMiddlewareScreen.timer',
                    );
                    time.cancel();
                  }
                });
              }
            }
          })
          .catchError((error) {
            developer.log(
              'Error: $error',
              error: error,
              name: 'AuthMiddlewareScreen.init',
            );
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.pushReplacementNamed(context, '/');
              });
            }
          });
    } catch (error) {
      developer.log(
        'Error: $error',
        error: error,
        name: 'AuthMiddlewareScreen.init',
      );
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pushReplacementNamed(context, '/');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (email != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    email!,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
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
                              .then((_) {
                                developer.log(
                                  'Verification email resent',
                                  name: 'AuthMiddlewareScreen.resend',
                                );
                              })
                              .catchError((error) {
                                developer.log(
                                  'Error resending verification: $error',
                                  error: error,
                                  name: 'AuthMiddlewareScreen.resend',
                                );
                              });

                          countdown = Timer.periodic(
                            const Duration(seconds: 1),
                            (timer) {
                              try {
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
                              } catch (error) {
                                developer.log(
                                  'Error: $error',
                                  error: error,
                                  name: 'AuthMiddlewareScreen.countdown',
                                );
                                timer.cancel();
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
  }

  @override
  void dispose() {
    try {
      timer?.cancel();
      countdown?.cancel();
      super.dispose();
    } catch (error) {
      developer.log(
        'Error: $error',
        error: error,
        name: 'AuthMiddlewareScreen.dispose',
      );
    }
  }
}
