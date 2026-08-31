import 'dart:async';
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

  @override
  Widget build(BuildContext context) {
    try {
      final locked = quarantine != null;

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
                    'Unlock Identity',
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
                          'Identity',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        identities.isEmpty
                            ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'No identities have been created on this device yet.',
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => Navigator.of(
                                  context,
                                ).pushNamed('/signup'),
                                child: const Text('Create an Identity'),
                              ),
                            ],
                          ),
                        )
                            : DropdownButtonFormField<String>(
                          initialValue: selection,
                          decoration: const InputDecoration(
                            labelText: 'Select Identity',
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
                          onChanged: (input) {
                            if (warning != null) {
                              setState(() => warning = null);
                            }
                          },
                        ),
                        if (locked) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Too many failed attempts. Try again in '
                                '${quarantine!.inSeconds} seconds.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                            (loading || selection == null || locked)
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
                                  final target = selection!;
                                  setState(() {
                                    loading = true;
                                    warning = null;
                                  });

                                  final identity = await Session.open(
                                    target,
                                    passphrase.text,
                                  );

                                  final folder =
                                  await getApplicationSupportDirectory();
                                  final path = '${folder.path}/tor';
                                  final address = await Sentinel
                                      .summon()
                                      .publish(
                                    path,
                                    blob(identity.private),
                                  );

                                  final network = address.replaceAll(
                                    '.onion',
                                    '',
                                  );
                                  final base = identity.address
                                      .replaceAll('.onion', '');

                                  if (network.length >= 50 &&
                                      base.length >= 50 &&
                                      network.substring(0, 50) !=
                                          base.substring(0, 50)) {
                                    final exception = StateError(
                                      'Published address pubkey does not match identity '
                                          '(network=$address expected=${identity.address}).',
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
                                    'This identity exceeded the maximum failed attempts and has been permanently erased from this device.';
                                    if (destroyed != null) {
                                      identities.remove(destroyed);
                                    }
                                    selection = identities.isNotEmpty
                                        ? identities.first
                                        : null;
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
                                    'Too many failed attempts. Try again in '
                                        '${error.remaining.inSeconds} seconds.',
                                  );
                                }
                                await refresh();
                              } catch (error) {
                                developer.log(
                                  'Failed to decrypt store or publish Tor onion service with provided credentials',
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
                                        ? 'Failed to decrypt store with provided credentials '
                                        '($remaining attempt${remaining == 1 ? '' : 's'} remaining before permanent deletion).'
                                        : 'Failed to decrypt store with provided credentials',
                                  );
                                }
                                await refresh();
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