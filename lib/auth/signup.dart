import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:zephyron/main.dart';
import 'package:zephyron/models/user.dart' as model;
import 'dart:developer' as developer;

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => SignUpPageState();
}

class SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController name = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController email = TextEditingController();
  bool obscured = true;
  bool toggled = false;
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
                    'Create your account',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: key,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Username',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Enter your username',
                          ),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) {
                            try {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a username';
                              }
                              if (value.length < 3) {
                                return 'Username must be at least 3 characters';
                              }
                              if (value.length > 20) {
                                return 'Username must be no more than 20 characters';
                              }
                              if (!RegExp(r'^[a-zA-Z]').hasMatch(value)) {
                                return 'Username must start with a letter';
                              }
                              if (!RegExp(
                                r'^[a-zA-Z][a-zA-Z0-9._]*$',
                              ).hasMatch(value)) {
                                return 'Username can only contain letters, numbers, underscores, and periods';
                              }
                              if (RegExp(r'[._]{2,}').hasMatch(value)) {
                                return 'Username cannot have consecutive periods or underscores';
                              }
                              if (RegExp(r'[._]$').hasMatch(value)) {
                                return 'Username cannot end with a period or underscore';
                              }
                              return null;
                            } catch (error) {
                              developer.log(
                                'Failed to evaluate username configuration rules: $error',
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
                                r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$",
                              ).hasMatch(value)) {
                                return 'Please enter a valid email';
                              }
                              if (value.contains(' ')) {
                                return 'Email must not contain spaces';
                              }
                              return warning;
                            } catch (error) {
                              developer.log(
                                'Failed to evaluate email formatting rules: $error',
                                error: error,
                                stackTrace: StackTrace.current,
                                name: 'SignUpPage.validation',
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
                                name: 'SignUpPage.input',
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Password',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
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
                                return 'Password must be at least 8 characters';
                              }
                              if (!value.contains(RegExp(r'[A-Z]'))) {
                                return 'Password must contain at least one uppercase letter';
                              }
                              if (!value.contains(RegExp(r'[a-z]'))) {
                                return 'Password must contain at least one lowercase letter';
                              }
                              if (!value.contains(
                                RegExp(r'[!@#%^&*_~(),.?":{}|<>]'),
                              )) {
                                return 'Password must contain at least one symbol';
                              }
                              if (value.contains(' ')) {
                                return 'Password must not contain spaces';
                              }
                              return null;
                            } catch (error) {
                              developer.log(
                                'Failed to evaluate password complexity rules: $error',
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
                                          final auth = await account.create(
                                            userId: ID.unique(),
                                            email: email.text,
                                            password: password.text,
                                            name: name.text,
                                          );
                                          await account
                                              .createEmailPasswordSession(
                                                email: email.text,
                                                password: password.text,
                                              );
                                          final info = model.User(
                                            id: auth.$id,
                                            email: email.text,
                                            name: name.text,
                                            phone: auth.phone.isNotEmpty
                                                ? auth.phone
                                                : null,
                                          );
                                          try {
                                            await tables.createRow(
                                              databaseId:
                                                  '69951d1f002692e40827',
                                              tableId: '69965edb0019ed7a133f',
                                              rowId: auth.$id,
                                              data: info.toMap(),
                                              permissions: [
                                                Permission.read(
                                                  Role.user(auth.$id),
                                                ),
                                                Permission.update(
                                                  Role.user(auth.$id),
                                                ),
                                                Permission.delete(
                                                  Role.user(auth.$id),
                                                ),
                                              ],
                                            );
                                          } catch (error) {
                                            developer.log(
                                              'Failed to write initialized registration record to primary collection: $error',
                                              error: error,
                                              stackTrace: StackTrace.current,
                                              name: 'SignUpPage.database',
                                            );
                                            throw Exception(
                                              'Failed to store user data',
                                            );
                                          }
                                          if (mounted) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  Navigator.pushReplacementNamed(
                                                    context,
                                                    '/auth/middleware',
                                                  );
                                                });
                                          }
                                        } on AppwriteException catch (error) {
                                          setState(() {
                                            warning = switch (error.code) {
                                              409 =>
                                                'Email address is already in use',
                                              401 =>
                                                'Invalid email or password format',
                                              429 =>
                                                'Too many requests. Please try again later',
                                              _ => switch (error.type) {
                                                'user_already_exists' =>
                                                  'An account with this email already exists',
                                                'user_blocked' =>
                                                  'Your account has been blocked. Please contact support',
                                                'user_invalid' =>
                                                  'Invalid user information provided',
                                                'password_recently_used' =>
                                                  'This password has been used recently',
                                                'password_personal_data' =>
                                                  'Password must not contain personal information',
                                                'user_password_mismatch' =>
                                                  'Password does not meet the required criteria',
                                                _ =>
                                                  'An error occurred during sign up. Please try again',
                                              },
                                            };
                                          });
                                          developer.log(
                                            'Appwrite server rejected registration request: [${error.type}] ${error.message}',
                                            error: error,
                                            stackTrace: StackTrace.current,
                                            name: 'SignUpPage.auth',
                                          );
                                        } catch (error) {
                                          setState(
                                            () => warning =
                                                'An unexpected error occurred.',
                                          );
                                          developer.log(
                                            'Unexpected core exception during registration workflow: $error',
                                            error: error,
                                            stackTrace: StackTrace.current,
                                            name: 'SignUpPage.auth',
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
                                : const Text('Sign Up'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          title: Text.rich(
                            TextSpan(
                              text: 'I accept the ',
                              style: DefaultTextStyle.of(context).style,
                              children: [
                                TextSpan(
                                  text: 'Terms of Use',
                                  style: const TextStyle(
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {},
                                ),
                                const TextSpan(
                                  text:
                                      ' and confirm that I have fully read and understood the ',
                                ),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: const TextStyle(
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {},
                                ),
                                const TextSpan(text: '.'),
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
        'Failed to render registration profile interface layout: $error',
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
      name.dispose();
      password.dispose();
      email.dispose();
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to cleanly release input text tracking layouts: $error',
        error: error,
        stackTrace: StackTrace.current,
        name: 'SignUpPage.dispose',
      );
    }
  }
}
