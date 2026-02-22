import 'package:flutter/material.dart';
import 'package:zephyron/theme.dart';
import 'package:flutter/services.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/widgets/discovery.dart';
import 'package:zephyron/widgets/sheet.dart';

class Compose extends StatefulWidget {
  final String? address;
  final String? name;

  const Compose({super.key, this.address, this.name});

  static Future<Trustee?> show(
    BuildContext context, {
    String? address,
    String? name,
  }) {
    return showModalBottomSheet<Trustee>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Compose(address: address, name: name),
    );
  }

  @override
  State<Compose> createState() => ComposeState();
}

class ComposeState extends State<Compose> {
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  late final TextEditingController address = TextEditingController(
    text: widget.address ?? '',
  );
  late final TextEditingController name = TextEditingController(
    text: widget.name ?? '',
  );
  String? problem;
  bool busy = false;

  @override
  void dispose() {
    address.dispose();
    name.dispose();
    super.dispose();
  }

  void absorb(String text) {
    final found = Courier.parse(text);
    if (found == null) return;
    address.text = found.address;
    if (name.text.trim().isEmpty && found.name.isNotEmpty) {
      name.text = found.name;
    }
  }

  Future<void> submit() async {
    absorb(address.text);
    if (!key.currentState!.validate()) return;
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      final trustee = await Courier.instance.add(address.text, name.text);
      if (mounted) Navigator.pop(context, trustee);
    } on FormatException catch (error) {
      setState(() {
        busy = false;
        problem = error.message;
      });
      key.currentState!.validate();
    } catch (_) {
      setState(() {
        busy = false;
        problem = 'Could not save this trustee. Try again.';
      });
      key.currentState!.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final courier = Courier.instance;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Sheets.grabber(context)),
              Center(
                child: Text(
                  'Add Trustee',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Trustees can message you and see your profile. Exchange discovery keys with people you actually trust.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Identifier(
                address: courier.self?.address ?? '',
                name: courier.me.name,
              ),
              const SizedBox(height: 24),
              Text(
                'Discovery Key',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: address,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontFamily: Pallete.mono, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Paste an .onion key or zephyron:// link',
                  errorMaxLines: 3,
                  suffixIcon: IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste),
                    onPressed: () async {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      final text = data?.text?.trim() ?? '';
                      setState(() {
                        if (Courier.parse(text) != null) {
                          absorb(text);
                        } else {
                          address.text = text;
                        }
                        problem = null;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  final text = value?.trim().toLowerCase() ?? '';
                  if (text.isEmpty) return 'Please enter a discovery key';
                  if (!Identity.valid(text)) {
                    return 'Enter a full v3 key ending in .onion (56 characters)';
                  }
                  return problem;
                },
                onChanged: (_) {
                  if (problem != null) setState(() => problem = null);
                },
              ),
              const SizedBox(height: 24),
              Text('Nickname', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => submit(),
                decoration: const InputDecoration(
                  hintText: 'Optional, only visible on this device',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: busy ? null : submit,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: busy
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add Trustee', key: ValueKey('idle')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Identifier extends StatelessWidget {
  final String address;
  final String name;
  final bool compact;

  const Identifier({
    super.key,
    required this.address,
    this.name = '',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: address.isEmpty
          ? null
          : () => Discovery.show(
              context,
              address: address,
              name: name,
              own: true,
            ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.key_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Discovery Key',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address.isEmpty ? 'Locked' : address,
                    maxLines: compact ? 1 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Pallete.mono,
                      fontSize: 13,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Show QR code',
              icon: Icon(Icons.qr_code_2, color: scheme.primary),
              onPressed: address.isEmpty
                  ? null
                  : () => Discovery.show(
                      context,
                      address: address,
                      name: name,
                      own: true,
                    ),
            ),
            IconButton(
              tooltip: 'Copy',
              icon: Icon(Icons.copy, size: 20, color: scheme.primary),
              onPressed: address.isEmpty
                  ? null
                  : () => Discovery.copy(context, address),
            ),
          ],
        ),
      ),
    );
  }
}
