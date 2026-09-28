import 'package:flutter/material.dart';
import 'package:zephyron/services/duress.dart';
import 'package:zephyron/sql/database.dart';
import 'package:zephyron/sql/session.dart';

class DuressPage extends StatefulWidget {
  const DuressPage({super.key});

  @override
  State<DuressPage> createState() => DuressPageState();
}

class DuressPageState extends State<DuressPage> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final TextEditingController current = TextEditingController();
  final TextEditingController duress = TextEditingController();
  final TextEditingController confirm = TextEditingController();
  bool hidden = true;
  bool busy = false;
  String? wrong;

  @override
  void dispose() {
    for (final field in [current, duress, confirm]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  Future<void> arm() async {
    setState(() => wrong = null);
    if (!key.currentState!.validate()) return;
    final name = Session.profile;
    if (name == null) return;
    setState(() => busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Database.verify(name, current.text)) {
        setState(() => wrong = 'That is not this identity\'s passphrase');
        key.currentState!.validate();
        return;
      }
      await Duress.arm(name, current.text, duress.text);
      messenger.showSnackBar(
        const SnackBar(content: Text('Duress passphrase is ready.')),
      );
      navigator.pop(true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget label(String title, String hint) {
      return Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(hint, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: hidden ? 'Show' : 'Hide',
        icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
        onPressed: () => setState(() => hidden = !hidden),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Duress Passphrase')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Form(
            key: key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.theater_comedy_outlined,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'If someone forces you to unlock',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Type the duress passphrase instead of your real one. Every other identity on this phone is erased without any warning, and ${Session.profile ?? 'this identity'} opens as if nothing happened.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Make this identity look ordinary: a real name, a few trustees, everyday messages. An empty decoy is easy to see through. It cannot protect you if the phone was copied before you unlocked it, and misleading the authorities can be a crime in some countries.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                label(
                  'This identity\'s passphrase',
                  'Proves it is you, and lets the decoy open without it.',
                ),
                TextFormField(
                  controller: current,
                  obscureText: hidden,
                  textInputAction: TextInputAction.next,
                  decoration: field('Your current passphrase'),
                  validator: (input) {
                    if (input == null || input.isEmpty) {
                      return 'Enter this identity\'s passphrase';
                    }
                    return wrong;
                  },
                ),
                label(
                  'Duress passphrase',
                  'Different from every real passphrase you use, and easy to remember under stress.',
                ),
                TextFormField(
                  controller: duress,
                  obscureText: hidden,
                  textInputAction: TextInputAction.next,
                  decoration: field('At least 12 characters'),
                  validator: (input) {
                    if (input == null || input.length < 12) {
                      return 'Use at least 12 characters';
                    }
                    if (input == current.text) {
                      return 'It must differ from your real passphrase';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirm,
                  obscureText: hidden,
                  textInputAction: TextInputAction.done,
                  decoration: field('Type it again'),
                  onFieldSubmitted: (_) => busy ? null : arm(),
                  validator: (input) => input != duress.text
                      ? 'The passphrases don\'t match'
                      : null,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: busy ? null : arm,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: busy
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Arm Duress Passphrase',
                            key: ValueKey('idle'),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
