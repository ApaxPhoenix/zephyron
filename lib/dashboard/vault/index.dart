import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/compose.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/web.dart';
import 'package:zephyron/sql/session.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/beacon.dart';
import 'package:zephyron/widgets/sheet.dart';
import 'package:zephyron/wrappers/tor.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => VaultPageState();
}

class VaultPageState extends State<VaultPage> {
  late final String version = Tor.version;

  Courier get courier => Courier.instance;

  void tune(void Function(Preferences prefs) change) {
    final next = Preferences.fromJson(courier.prefs.toJson());
    change(next);
    courier.configure(next);
  }

  Future<void> lock() async {
    final sure = await Sheets.confirm(
      context,
      title: 'Lock Vault?',
      message:
          'Your onion service goes offline and the encrypted store is closed until you unlock it again.',
      action: 'Lock',
    );
    if (sure) await Session.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Settings'),
        actions: [
          const Center(child: Beacon()),
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: IconButton(
              icon: const Icon(Icons.lock_outlined),
              onPressed: lock,
              tooltip: 'Lock Vault',
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          courier,
          courier.reach,
          Sentinel.summon().progress,
        ]),
        builder: (context, _) {
          final me = courier.me;
          final prefs = courier.prefs;
          final address = courier.self?.address ?? '';
          final reach = courier.reach.value;
          final progress = Sentinel.summon().progress.value;
          final trustees = courier.roster.values.where((item) => item.trusted);
          final online = trustees
              .where((item) => courier.online(item.address))
              .length;
          final blocked = courier.roster.values
              .where((item) => item.blocked)
              .length;

          Widget header(String text) {
            return Padding(
              padding: const EdgeInsets.only(left: 4.0, top: 24, bottom: 8.0),
              child: Text(text, style: Theme.of(context).textTheme.titleSmall),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/dashboard/settings/profile',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Avatar(
                          label: me.name.isEmpty ? '?' : me.name,
                          image: me.avatar,
                          size: 56,
                          online: reach == Reach.online,
                          availability: me.availability,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                me.name.isEmpty ? 'Set Your Name' : me.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                me.mood.isNotEmpty
                                    ? me.mood
                                    : me.bio.isNotEmpty
                                    ? me.bio
                                    : 'Add a status and bio',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${trustees.length} Trustees • $online Online',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: scheme.primary),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final state in Availability.values)
                    FilterChip(
                      selected: me.availability == state,
                      showCheckmark: false,
                      avatar: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Avatar.tone(state),
                          shape: BoxShape.circle,
                        ),
                      ),
                      label: Text(state.label),
                      labelStyle: TextStyle(
                        color: me.availability == state
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      onSelected: (_) => courier.publish(
                        courier.me.copy()..availability = state,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Identifier(address: address, name: me.name),
              header('Privacy'),
              SwitchListTile(
                secondary: const Icon(Icons.done_all),
                title: const Text('Read Receipts'),
                subtitle: const Text(
                  'Let trustees see when you have read their messages',
                ),
                value: prefs.receipts,
                onChanged: (value) => tune((next) => next.receipts = value),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.keyboard_outlined),
                title: const Text('Typing Indicators'),
                subtitle: const Text('Show trustees when you are typing'),
                value: prefs.typing,
                onChanged: (value) => tune((next) => next.typing = value),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.mark_email_unread_outlined),
                title: const Text('Message Requests'),
                subtitle: const Text(
                  'Allow people who are not trustees to message you',
                ),
                value: prefs.strangers,
                onChanged: (value) => tune((next) => next.strangers = value),
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Blocked'),
                subtitle: const Text('Manage blocked keys in Trustees'),
                trailing: Text('$blocked'),
              ),
              header('Notifications'),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('In-App Banners'),
                subtitle: const Text('Muted automatically on Do not disturb'),
                value: prefs.banners,
                onChanged: (value) => tune((next) => next.banners = value),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('Haptics'),
                subtitle: const Text('Vibrate on send and long press'),
                value: prefs.haptics,
                onChanged: (value) => tune((next) => next.haptics = value),
              ),
              header('Media'),
              ListTile(
                leading: const Icon(Icons.gif_box_outlined),
                title: const Text('GIPHY'),
                subtitle: Text(
                  Giphy.ready
                      ? 'Search and previews load over Tor'
                      : 'Add GIPHY_API_KEY to .env to enable',
                ),
                trailing: Icon(
                  Giphy.ready ? Icons.check_circle : Icons.key_off,
                  color: Giphy.ready ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('GIF Content Rating'),
                trailing: DropdownButton<Rating>(
                  value: prefs.rating,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final rating in Rating.values)
                      DropdownMenuItem(
                        value: rating,
                        child: Text(rating.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) tune((next) => next.rating = value);
                  },
                ),
              ),
              header('Appearance'),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('Theme'),
                trailing: DropdownButton<ThemeMode>(
                  value: prefs.theme,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('System'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) tune((next) => next.theme = value);
                  },
                ),
              ),
              header('Network & Routing'),
              ListTile(
                leading: const Icon(Icons.router_outlined),
                title: const Text('Tor Proxy Daemon'),
                subtitle: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: reach == Reach.connecting
                      ? Padding(
                          key: const ValueKey('progress'),
                          padding: const EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(
                            value: progress > 0 ? progress / 100 : null,
                          ),
                        )
                      : Text(
                          reach == Reach.online
                              ? 'Bootstrapped and routing all traffic'
                              : 'Unavailable, retrying',
                          key: ValueKey(reach),
                        ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Onion Service'),
                subtitle: Text(
                  courier.server != null
                      ? 'Port 80 → 127.0.0.1:${Courier.port}'
                      : 'Listener not bound',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Tor Version'),
                trailing: Text(version),
              ),
              header('Security'),
              const ListTile(
                leading: Icon(Icons.storage_outlined),
                title: Text('Local Storage'),
                subtitle: Text(
                  'SQLCipher with an Argon2id key; attachments sealed with AES-256-GCM',
                ),
              ),
              const ListTile(
                leading: Icon(Icons.key_outlined),
                title: Text('Message Signing'),
                subtitle: Text('Ed25519, bound to your discovery key'),
              ),
              const ListTile(
                leading: Icon(Icons.timer_outlined),
                title: Text('Inactivity Timeout'),
                subtitle: Text('Auto-lock vault after 10 minutes of idle'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: lock,
                  icon: const Icon(Icons.lock_outlined),
                  label: const Text('Lock Vault'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
