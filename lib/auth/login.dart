import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:zephyron/main.dart';
import 'dart:developer' as developer;

class LogInPage extends StatefulWidget {
  const LogInPage({super.key});

  @override
  State<LogInPage> createState() => LogInPageState();
}

class LogInPageState extends State<LogInPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController password = TextEditingController();
  final TextEditingController email = TextEditingController();
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
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('image_path', width: 100, height: 100),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.05),
                  Text(
                    'Lorem ipsum dolor',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam eget magna id velit commodo lacinia vitae eget ipsum.',
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
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Enter your email',
                          ),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) {
                            try {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!RegExp(
                                r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?)*$",
                              ).hasMatch(value)) {
                                return 'Please enter a valid email';
                              }
                              return warning;
                            } catch (error) {
                              developer.log(
                                'Failed to evaluate email formatting rules: $error',
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
                                'Failed to clear active validation hints on email edit: $error',
                                error: error,
                                stackTrace: StackTrace.current,
                                name: 'LogInPage.input',
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Password',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  await Navigator.pushNamed(
                                    context,
                                    '/auth/account-recovery',
                                  );
                                } catch (error) {
                                  developer.log(
                                    'Failed to execute screen navigation to account recovery: $error',
                                    error: error,
                                    stackTrace: StackTrace.current,
                                    name: 'LogInPage.navigation',
                                  );
                                }
                              },
                              child: const Text("Forgot Password?"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        TextFormField(
                          controller: password,
                          obscureText: obscured,
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
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
                                return 'Please enter your password';
                              }
                              if (value.length < 8) {
                                return 'Password must have at least 8 characters';
                              }
                              if (!value.contains(RegExp(r'[A-Z]'))) {
                                return 'Password must contain at least one uppercase letter';
                              }
                              if (!value.contains(RegExp(r'[a-z]'))) {
                                return 'Password must contain at least one lowercase letter';
                              }
                              return warning;
                            } catch (error) {
                              developer.log(
                                'Failed to evaluate password complexity rules: $error',
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
                                'Failed to clear active validation hints on password edit: $error',
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
                                          final session = await account
                                              .createEmailPasswordSession(
                                                email: email.text,
                                                password: password.text,
                                              );
                                          if (session.$id.isNotEmpty &&
                                              mounted) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  Navigator.pushNamedAndRemoveUntil(
                                                    context,
                                                    '/dashboard',
                                                    (route) => false,
                                                  );
                                                });
                                          }
                                        } on AppwriteException catch (error) {
                                          setState(() {
                                            warning = switch (error.code) {
                                              429 =>
                                                'Too many login attempts. Please try again later',
                                              _ => switch (error.type) {
                                                'user_invalid_credentials' =>
                                                  'Incorrect email or password',
                                                'user_blocked' =>
                                                  'This account has been disabled',
                                                'user_session_already_exists' =>
                                                  'You are already logged in',
                                                'user_not_found' =>
                                                  'No account found with this email',
                                                'user_email_not_whitelisted' =>
                                                  'This email is not authorized to sign in',
                                                _ =>
                                                  'An error occurred during login. Please try again',
                                              },
                                            };
                                          });
                                          developer.log(
                                            'Appwrite server rejected authentication request: [${error.type}] ${error.message}',
                                            error: error,
                                            stackTrace: StackTrace.current,
                                            name: 'LogInPage.auth',
                                          );
                                        } catch (error) {
                                          setState(
                                            () => warning =
                                                'An unexpected error occurred',
                                          );
                                          developer.log(
                                            'Unexpected internal error during engine processing: $error',
                                            error: error,
                                            stackTrace: StackTrace.current,
                                            name: 'LogInPage.auth',
                                          );
                                          if (mounted) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  Navigator.pushNamedAndRemoveUntil(
                                                    context,
                                                    '/',
                                                    (route) => false,
                                                  );
                                                });
                                          }
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
                                : const Text('Log In'),
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
      password.dispose();
      email.dispose();
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to cleanly release input layout controllers: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'LogInPage.dispose',
      );
    }
  }
}
