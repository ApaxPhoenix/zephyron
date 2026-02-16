import 'package:flutter/material.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/dashboard/chats/attach.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/discovery.dart';
import 'package:zephyron/widgets/sheet.dart';
import 'package:zephyron/widgets/stamp.dart';

class NodePage extends StatefulWidget {
  final String? id;
  final String? name;

  const NodePage({super.key, this.id, this.name});

  @override
  State<NodePage> createState() => NodePageState();
}

class NodePageState extends State<NodePage> {
  bool busy = false;

  Courier get courier => Courier.instance;
  String get address => widget.id ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (courier.roster[address]?.trusted == true) ping();
    });
  }

  Future<void> ping() async {
    if (busy || address.isEmpty) return;
    setState(() => busy = true);
    await courier.ping(address);
    if (mounted) setState(() => busy = false);
  }

  Future<void> trust(Trustee trustee, Trust level) async {
    if (level == Trust.blocked) {
      final sure = await Sheets.confirm(
        context,
        title: 'Block ${trustee.label}?',
        message:
            'Their messages, files and pings are dropped and they stop seeing your profile.',
        action: 'Block',
      );
      if (!sure) return;
    }
    await courier.trust(trustee.address, level);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: courier,
      builder: (context, _) {
        final trustee = courier.roster[address];
        if (trustee == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(
                'This peer was removed.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }

        final presence = courier.status(address);
        final online = courier.online(address);
        final count = courier.threads[address]?.length ?? 0;
        final mine = courier.self?.address;
        final code = mine == null ? null : Courier.safety(mine, address);
        final state = trustee.blocked
            ? 'Blocked'
            : online
            ? trustee.availability.label
            : presence.seen != null &&
                  trustee.availability != Availability.invisible
            ? 'Last seen ${ago(presence.seen!)}'
            : busy
            ? 'Reaching out over Tor…'
            : 'Offline';
        final divider = Divider(
          height: 1,
          color: scheme.outlineVariant.withAlpha(50),
        );

        Widget card(List<Widget> children) {
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0) divider,
                  children[index],
                ],
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            title: Text(trustee.label),
            actions: [
              IconButton(
                tooltip: 'Edit Nickname',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final field = TextEditingController(text: trustee.nickname);
                  final result = await showDialog<String>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: const Text('Nickname'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: field,
                            autofocus: true,
                            maxLength: 32,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              hintText: trustee.alias.isEmpty
                                  ? 'Name'
                                  : trustee.alias,
                            ),
                            onSubmitted: (value) =>
                                Navigator.pop(dialog, value),
                          ),
                          const Text(
                            'Only visible on this device. Leave empty to use the name they chose.',
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, field.text),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                  field.dispose();
                  if (result == null) return;
                  await courier.amend(trustee..nickname = result.trim());
                },
              ),
              IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: busy
                      ? const SizedBox(
                          key: ValueKey('busy'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, key: ValueKey('idle')),
                ),
                onPressed: busy || trustee.blocked ? null : ping,
                tooltip: 'Ping Node',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Hero(
                  tag: 'avatar:$address',
                  child: Portrait(address: address, size: 80),
                ),
                const SizedBox(height: 16),
                Text(
                  trustee.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
                if (trustee.nickname.isNotEmpty && trustee.alias.isNotEmpty)
                  Text(
                    'Calls themselves ${trustee.alias}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    state,
                    key: ValueKey(state),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: online
                          ? Avatar.tone(trustee.availability)
                          : scheme.onSurfaceVariant,
                      fontWeight: online ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Column(
                    children: [
                      if (trustee.mood.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          trustee.mood,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.primary),
                        ),
                      ],
                      if (trustee.bio.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(trustee.bio, textAlign: TextAlign.center),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                card([
                  ListTile(
                    leading: Icon(switch (trustee.trust) {
                      Trust.trustee => Icons.verified_user_outlined,
                      Trust.stranger => Icons.help_outline,
                      Trust.blocked => Icons.block,
                    }, color: trustee.blocked ? scheme.error : scheme.primary),
                    title: Text(trustee.trust.label),
                    subtitle: Text(switch (trustee.trust) {
                      Trust.trustee =>
                        'Can message you and sees your profile and status',
                      Trust.stranger =>
                        'Messaged you first. They cannot see your profile yet',
                      Trust.blocked => 'Everything from them is dropped',
                    }),
                  ),
                  ListTile(
                    leading: Icon(Icons.key_outlined, color: scheme.primary),
                    title: const Text('Discovery Key'),
                    subtitle: SelectableText(
                      address,
                      style: const TextStyle(
                        fontFamily: Pallete.mono,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'QR Code',
                          icon: const Icon(Icons.qr_code_2, size: 20),
                          onPressed: () => Discovery.show(
                            context,
                            address: address,
                            name: trustee.label,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => Discovery.copy(context, address),
                        ),
                      ],
                    ),
                  ),
                  if (code != null)
                    ListTile(
                      leading: Icon(
                        Icons.shield_outlined,
                        color: scheme.primary,
                      ),
                      title: const Text('Safety Code'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            '${code.take(3).join('  ')}\n${code.skip(3).join('  ')}',
                            style: TextStyle(
                              fontFamily: Pallete.mono,
                              fontSize: 16,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Compare with ${trustee.label} in person. Matching codes mean nobody swapped their key.',
                          ),
                        ],
                      ),
                    ),
                  ListTile(
                    leading: Icon(Icons.speed, color: scheme.primary),
                    title: const Text('Latency'),
                    subtitle: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        presence.latency != null
                            ? '${presence.latency}ms'
                            : 'Offline',
                        key: ValueKey(presence.latency),
                        style: TextStyle(
                          color: presence.latency != null
                              ? scheme.primary
                              : scheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.forum_outlined, color: scheme.primary),
                    title: const Text('Messages'),
                    subtitle: Text('$count'),
                  ),
                  ListTile(
                    leading: Icon(Icons.event_outlined, color: scheme.primary),
                    title: const Text('Added'),
                    subtitle: Text(brief(trustee.created)),
                  ),
                ]),
                const SizedBox(height: 24),
                if (!trustee.blocked) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: busy ? null : ping,
                          icon: const Icon(Icons.sync),
                          label: const Text('Ping'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final navigator = Navigator.of(context);
                            var found = false;
                            navigator.popUntil((route) {
                              final arguments = route.settings.arguments;
                              if (route.settings.name ==
                                      '/dashboard/chats/message' &&
                                  arguments is Map &&
                                  arguments['id'] == trustee.address) {
                                found = true;
                                return true;
                              }
                              return route.isFirst;
                            });
                            if (!found) {
                              navigator.pushNamed(
                                '/dashboard/chats/message',
                                arguments: {'id': trustee.address},
                              );
                            }
                          },
                          icon: const Icon(Icons.message),
                          label: const Text('Message'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share Trustee'),
                      onPressed: () => Sheets.actions(
                        context,
                        items: [
                          SheetAction(
                            icon: Icons.forum_outlined,
                            label: 'Send to a Trustee',
                            onTap: () async {
                              final target = await Chooser.show(
                                context,
                                title: 'Send ${trustee.label} to',
                                exclude: {trustee.address},
                              );
                              if (target == null) return;
                              await courier.share(target.address, trustee);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Shared with ${target.label}'),
                                ),
                              );
                            },
                          ),
                          SheetAction(
                            icon: Icons.qr_code_2,
                            label: 'Show QR Code',
                            onTap: () => Discovery.show(
                              context,
                              address: trustee.address,
                              name: trustee.label,
                            ),
                          ),
                          SheetAction(
                            icon: Icons.share,
                            label: 'Share Outside Zephyron',
                            onTap: () => Discovery.spread(
                              trustee.address,
                              trustee.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                card([
                  SwitchListTile(
                    secondary: const Icon(Icons.push_pin_outlined),
                    title: const Text('Pinned'),
                    value: trustee.pinned,
                    onChanged: (value) =>
                        courier.amend(trustee..pinned = value),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.archive_outlined),
                    title: const Text('Archived'),
                    value: trustee.archived,
                    onChanged: (value) =>
                        courier.amend(trustee..archived = value),
                  ),
                ]),
                const SizedBox(height: 16),
                card([
                  if (trustee.trusted)
                    ListTile(
                      leading: const Icon(Icons.remove_moderator_outlined),
                      title: const Text('Revoke Trust'),
                      onTap: () => trust(trustee, Trust.stranger),
                    )
                  else if (trustee.stranger)
                    ListTile(
                      leading: Icon(
                        Icons.add_moderator_outlined,
                        color: scheme.primary,
                      ),
                      title: const Text('Add as Trustee'),
                      onTap: () => trust(trustee, Trust.trustee),
                    ),
                  if (trustee.blocked)
                    ListTile(
                      leading: const Icon(Icons.lock_open),
                      title: const Text('Unblock'),
                      onTap: () => trust(trustee, Trust.stranger),
                    )
                  else
                    ListTile(
                      leading: Icon(Icons.block, color: scheme.error),
                      title: Text(
                        'Block',
                        style: TextStyle(color: scheme.error),
                      ),
                      onTap: () => trust(trustee, Trust.blocked),
                    ),
                  ListTile(
                    leading: Icon(
                      Icons.cleaning_services_outlined,
                      color: scheme.error,
                    ),
                    title: Text(
                      'Clear History',
                      style: TextStyle(color: scheme.error),
                    ),
                    onTap: () async {
                      final sure = await Sheets.confirm(
                        context,
                        title: 'Clear History?',
                        message:
                            'Every message and attachment with ${trustee.label} will be wiped from this device.',
                        action: 'Clear',
                      );
                      if (sure) await courier.clear(address);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.person_remove_outlined,
                      color: scheme.error,
                    ),
                    title: Text(
                      'Delete Trustee',
                      style: TextStyle(color: scheme.error),
                    ),
                    onTap: () async {
                      final sure = await Sheets.confirm(
                        context,
                        title: 'Delete ${trustee.label}?',
                        message:
                            'The trustee, the conversation and every attachment are removed from this device.',
                      );
                      if (!sure) return;
                      await courier.remove(address);
                      if (context.mounted) {
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      }
                    },
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
