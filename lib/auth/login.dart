import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:zephyron/auth/onion.dart';
import 'package:zephyron/sql/session.dart';

class LogInPage extends StatefulWidget {
  /// Called when the person has no identity yet and wants to create one.
  final VoidCallback? onSignUp;

  const LogInPage({super.key, this.onSignUp});

  @override
  State<LogInPage> createState() => LogInPageState();
}

class LogInPageState extends State<LogInPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController passphrase = TextEditingController();
  bool obscured = true;
  bool loading = false;
  String? warning;
  List<String> identities = [];
  String? selection;
  Duration? quarantine;
  Timer? countdown;

  @override
  void initState() {
    super.initState();
    unawaited(hydrate());
  }

  Future<void> hydrate() async {
    try {
      final roster = await Session.sessions();
      if (mounted) {
        setState(() {
          identities = roster;
          selection = roster.isNotEmpty ? roster.first : null;
        });
      }
      await refresh();
      developer.log(
        'Loaded enrolled identity roster for login selector',
        name: 'LogInPageState.hydrate',
        level: 800,
      );
    } catch (error) {
      developer.log(
        'Failed to load enrolled identity roster for login selector',
        name: 'LogInPageState.hydrate',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  Future<void> refresh() async {
    countdown?.cancel();
    final name = selection;
    if (name == null) {
      if (mounted) setState(() => quarantine = null);
      return;
    }

    try {
      final remaining = await Session.quarantineRemaining(name);
      if (!mounted) return;
      setState(() => quarantine = remaining);

      if (remaining != null) {
        countdown = Timer.periodic(const Duration(seconds: 1), (ticker) async {
          final updated = await Session.quarantineRemaining(name);
          if (!mounted) {
            ticker.cancel();
            return;
          }
          setState(() => quarantine = updated);
          if (updated == null) ticker.cancel();
        });
      }
    } catch (error) {
      developer.log(
        'Failed to refresh quarantine countdown status for profile: $name',
        name: 'LogInPageState.refresh',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  static String pause(Duration wait) {
    final seconds = wait.inSeconds + 1;
    if (seconds < 60) return '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
    final minutes = (seconds / 60).ceil();
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  }

  Future<void> unlock() async {
    try {
      if (!key.currentState!.validate()) {
        developer.log(
          'Database decryption form validation failed due to invalid user input',
          name: 'LogInPageState.unlockDatabase',
          level: 900,
        );
        return;
      }

      developer.log(
        'Starting database decryption workflow',
        name: 'LogInPageState.unlockDatabase',
        level: 800,
      );

      final navigator = Navigator.of(context);
      final target = selection!;
      setState(() {
        loading = true;
        warning = null;
      });

      final identity = await Session.open(target, passphrase.text);

      developer.log(
        'Database decryption completed successfully',
        name: 'LogInPageState.unlockDatabase',
        level: 800,
      );

      // Going online can take a while, so it carries on in the background and
      // never holds the person at this screen.
      unawaited(announce(identity));

      if (mounted) {
        navigator.pushNamedAndRemoveUntil(
          '/dashboard',
          (route) => false,
          arguments: identity,
        );
      }
    } on IdentityAnnihilatedException catch (error) {
      developer.log(
        'Identity permanently annihilated after exceeding maximum failed unlock attempts',
        name: 'LogInPageState.unlockDatabase',
        level: 1200,
        error: error,
        stackTrace: StackTrace.current,
      );

      final destroyed = selection;
      if (mounted) {
        setState(() {
          warning =
              'Too many wrong passphrases. This identity has been erased from this device.';
          if (destroyed != null) {
            identities.remove(destroyed);
          }
          selection = identities.isNotEmpty ? identities.first : null;
          quarantine = null;
        });
      }
    } on IdentitiesPurgedException catch (error) {
      developer.log(
        'Every identity purged after unlock attempts looked like an attack',
        name: 'LogInPageState.unlockDatabase',
        level: 1200,
        error: error,
        stackTrace: StackTrace.current,
      );

      if (mounted) {
        setState(() {
          warning =
              'Those attempts looked like someone trying to break in. Every identity on this phone has been erased.';
          identities = [];
          selection = null;
          quarantine = null;
        });
      }
    } on IdentityQuarantinedException catch (error) {
      developer.log(
        'Identity temporarily quarantined after repeated failed unlock attempts',
        name: 'LogInPageState.unlockDatabase',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );

      if (mounted) {
        setState(
          () => warning =
              'Too many wrong passphrases. Try again in '
              '${pause(error.remaining)}.',
        );
      }
      await refresh();
    } catch (error) {
      developer.log(
        'Failed to decrypt store with provided credentials',
        name: 'LogInPageState.unlockDatabase',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );

      final target = selection;
      final remaining = target != null
          ? await Session.remainingAttempts(target)
          : null;

      if (mounted) {
        setState(
          () => warning = remaining != null
              ? 'That passphrase didn\'t work. You have $remaining '
                    '${remaining == 1 ? 'try' : 'tries'} left before this '
                    'identity is erased from this device.'
              : 'That passphrase didn\'t work.',
        );
      }
      await refresh();
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final theme = Theme.of(context);
      final locked = quarantine != null;

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
                    // A long press starts the panic wipe countdown, for when
                    // someone takes the phone before it is unlocked.
                    GestureDetector(
                      onLongPress: () =>
                          Navigator.of(context).pushNamed('/panic'),
                      child: Text(
                        'Welcome back',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your passphrase to unlock your identity and messages on this phone.',
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
                          Text('Identity', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          identities.isEmpty
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: theme.dividerColor,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'There are no identities on this phone yet.',
                                      ),
                                      if (widget.onSignUp != null) ...[
                                        const SizedBox(height: 8),
                                        TextButton(
                                          onPressed: widget.onSignUp,
                                          child: const Text(
                                            'Create your first identity',
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : DropdownButtonFormField<String>(
                                  initialValue: selection,
                                  decoration: const InputDecoration(
                                    hintText: 'Choose an identity',
                                  ),
                                  items: identities
                                      .map(
                                        (entry) => DropdownMenuItem(
                                          value: entry,
                                          child: Text(entry),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: loading
                                      ? null
                                      : (value) {
                                          setState(() {
                                            selection = value;
                                            warning = null;
                                          });
                                          unawaited(refresh());
                                        },
                                ),
                          const SizedBox(height: 24),
                          Text(
                            'Passphrase',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: passphrase,
                            obscureText: obscured,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (!loading && selection != null && !locked) {
                                unawaited(unlock());
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Enter your passphrase',
                              errorMaxLines: 3,
                              suffixIcon: IconButton(
                                tooltip: obscured ? 'Show' : 'Hide',
                                icon: Icon(
                                  obscured
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () =>
                                    setState(() => obscured = !obscured),
                              ),
                            ),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter your passphrase';
                              }
                              return warning;
                            },
                            onChanged: (input) {
                              if (warning != null) {
                                setState(() => warning = null);
                              }
                            },
                          ),
                          if (locked) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Too many wrong passphrases. Try again in '
                              '${pause(quarantine!)}.',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  (loading || selection == null || locked)
                                  ? null
                                  : () => unawaited(unlock()),
                              child: loading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Unlock'),
                            ),
                          ),
                          if (widget.onSignUp != null &&
                              identities.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: loading ? null : widget.onSignUp,
                                child: const Text(
                                  'New here? Create an identity',
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
      countdown?.cancel();
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
