import 'dart:async';
import 'dart:developer' as developer;
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zephyron/auth/onion.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/sql/database.dart';
import 'package:zephyron/sql/session.dart';

Identity make(String seed) => Identity.fromInput(seed);

class SignUpPage extends StatefulWidget {
  /// Called when the person already has an identity and wants to unlock it.
  final VoidCallback? onLogin;

  const SignUpPage({super.key, this.onLogin});

  @override
  State<SignUpPage> createState() => SignUpPageState();
}

class SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController moniker = TextEditingController();
  final TextEditingController passphrase = TextEditingController();
  final TextEditingController confirmation = TextEditingController();

  bool hidden = true;
  bool agreed = false;
  bool busy = false;
  String? seed;
  String? warning;
  Timer? timer;
  List<String> existing = [];

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
    unawaited(hydrate());
  }

  Future<void> hydrate() async {
    try {
      final roster = await Session.sessions();
      if (mounted) setState(() => existing = roster);
      developer.log(
        'Loaded existing identity roster for label uniqueness validation',
        name: 'SignUpPageState.hydrate',
        level: 800,
      );
    } catch (error) {
      developer.log(
        'Failed to load existing identity roster for label uniqueness validation',
        name: 'SignUpPageState.hydrate',
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

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Recovery phrase copied. Your clipboard clears in 30 seconds.',
            ),
          ),
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

  Future<void> create() async {
    final navigator = Navigator.of(context);

    try {
      if (!key.currentState!.validate()) {
        developer.log(
          'Identity creation form validation failed due to invalid user input',
          name: 'SignUpPageState.identity',
          level: 900,
        );
        return;
      }

      developer.log(
        'Starting identity generation workflow',
        name: 'SignUpPageState.identity',
        level: 800,
      );

      final mnemonic = seed!;
      final designation = moniker.text.trim();

      setState(() {
        busy = true;
        warning = null;
      });

      // Check against the live roster so an identity that already exists can
      // never be overwritten or wiped by a failed attempt under the same name.
      final roster = await Session.sessions();
      if (roster.contains(designation)) {
        if (mounted) {
          setState(() {
            existing = roster;
            warning = null;
          });
          key.currentState?.validate();
        }
        return;
      }

      const limit = 3;
      var round = 0;
      Object? cause;
      Identity? user;

      while (round < limit) {
        round += 1;
        try {
          final generated = await compute(make, mnemonic);

          if (generated.private.length != 128) {
            throw StateError('Invalid key length: expected 128 hex chars');
          }

          await Session.compose(
            designation,
            passphrase.text,
            generated,
            mnemonic,
          );

          developer.log(
            'Completed identity creation and session composition successfully',
            name: 'SignUpPageState.identity',
            level: 800,
          );

          user = generated;
          cause = null;
          break;
        } catch (error) {
          cause = error;
          developer.log(
            'Attempt $round of $limit failed during identity creation',
            name: 'SignUpPageState.identity',
            level: 1000,
            error: error,
            stackTrace: StackTrace.current,
          );

          await Session.dispose();

          if (round < limit) {
            await Future.delayed(Duration(seconds: round));
          }
        }
      }

      if (cause == null && user != null) {
        // The identity is saved. Going online can take a while, so it carries
        // on in the background instead of holding up the dashboard.
        unawaited(announce(user));
        if (mounted) {
          navigator.pushReplacementNamed('/dashboard', arguments: user);
        }
        return;
      }

      developer.log(
        'Exhausted all retry attempts, discarding the partially created local database',
        name: 'SignUpPageState.identity',
        level: 1200,
        error: cause,
        stackTrace: StackTrace.current,
      );

      try {
        await Database.wipe(designation);
        await Session.erase(designation);
      } catch (error) {
        developer.log(
          'Failed to delete local database after exhausting retry attempts',
          name: 'SignUpPageState.identity',
          level: 1000,
          error: error,
          stackTrace: StackTrace.current,
        );
      }

      if (mounted) {
        setState(
          () => warning =
              'We couldn\'t save your identity on this device, so nothing was created. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget heading(BuildContext context, String title, [String? note]) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      final theme = Theme.of(context);
      final words = (seed ?? '').split(' ').where((w) => w.isNotEmpty);

      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image.asset('assets/logo.png', width: 100, height: 100),
                    // SizedBox(height: MediaQuery.of(context).size.height * 0.05),
                    Text(
                      'Create your identity',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No email, no phone number, no account on a server. '
                      'Your identity is a private key that lives only on this phone.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Form(
                      key: key,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading(
                            context,
                            'Name this identity',
                            'Only you will see it, and only on this device.',
                          ),
                          TextFormField(
                            controller: moniker,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Personal, Work, Alias',
                            ),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (input) {
                              final trimmed = input?.trim() ?? '';
                              if (trimmed.isEmpty) {
                                return 'Give this identity a name';
                              }
                              if (trimmed.length > 64) {
                                return 'Keep the name under 64 characters';
                              }
                              if (existing.contains(trimmed)) {
                                return 'You already have an identity with this name';
                              }
                              return null;
                            },
                            onChanged: (input) {
                              if (warning != null) {
                                setState(() => warning = null);
                              }
                            },
                          ),
                          const SizedBox(height: 24),
                          heading(
                            context,
                            'Your recovery phrase',
                            'Write these words down in order and keep them safe. '
                                'They are the only way to restore your identity.',
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: seed == null
                                ? const Text('Preparing your phrase...')
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final entry in words.indexed)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '${entry.$1 + 1}  ',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                                TextSpan(
                                                  text: entry.$2,
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy phrase'),
                              onPressed: seed != null
                                  ? () => copy(seed!)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 24),
                          heading(
                            context,
                            'Choose a passphrase',
                            'Unlocks this identity on this phone every time you open the app.',
                          ),
                          TextFormField(
                            controller: passphrase,
                            obscureText: hidden,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: 'At least 12 characters',
                              errorText: warning,
                              errorMaxLines: 3,
                              suffixIcon: IconButton(
                                tooltip: hidden ? 'Show' : 'Hide',
                                icon: Icon(
                                  hidden
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () =>
                                    setState(() => hidden = !hidden),
                              ),
                            ),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            onChanged: (input) {
                              if (warning != null) {
                                setState(() => warning = null);
                              }
                            },
                            validator: (input) {
                              if (input == null || input.isEmpty) {
                                return 'Choose a passphrase';
                              }
                              if (input.length < 12) {
                                return 'Use at least 12 characters';
                              }
                              if (!RegExp(r'[A-Z]').hasMatch(input)) {
                                return 'Add an uppercase letter';
                              }
                              if (!RegExp(r'[a-z]').hasMatch(input)) {
                                return 'Add a lowercase letter';
                              }
                              if (!RegExp(r'[0-9]').hasMatch(input)) {
                                return 'Add a number';
                              }
                              if (!RegExp(
                                r'[!@#$%^&*(),.?":{}|<>]',
                              ).hasMatch(input)) {
                                return 'Add a symbol, like ! @ # \$';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          heading(context, 'Confirm your passphrase'),
                          TextFormField(
                            controller: confirmation,
                            obscureText: hidden,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              hintText: 'Type it once more',
                            ),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (input) {
                              if (input != passphrase.text) {
                                return 'The passphrases don\'t match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text.rich(
                              TextSpan(
                                text: 'I\'ve saved my recovery phrase. ',
                                style: theme.textTheme.bodyMedium,
                                children: const [
                                  TextSpan(
                                    text: 'No server keeps a copy',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        ', so if I lose both my phrase and my passphrase, '
                                        'my identity and messages can\'t be recovered.',
                                  ),
                                ],
                              ),
                            ),
                            value: agreed,
                            onChanged: busy
                                ? null
                                : (input) =>
                                      setState(() => agreed = input ?? false),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: agreed && !busy && seed != null
                                  ? () => unawaited(create())
                                  : null,
                              child: busy
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Create identity'),
                            ),
                          ),
                          if (widget.onLogin != null) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: busy ? null : widget.onLogin,
                                child: const Text(
                                  'Already have an identity? Unlock it',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
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
      moniker.clear();
      moniker.dispose();

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
