import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/compose.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/warden.dart';
import 'package:zephyron/services/web.dart';
import 'package:zephyron/sql/session.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/beacon.dart';
import 'package:zephyron/widgets/section.dart';
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

  Future<void> status() async {
    final picked = await Sheets.availability(
      context,
      current: courier.me.availability,
    );
    if (picked == null || picked == courier.me.availability) return;
    await courier.publish(courier.me.copy()..availability = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Settings'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: Beacon()),
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

          Widget value(String text) => Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          );

          Widget choice<T>({
            required T value,
            required List<(T, String)> options,
            required ValueChanged<T> onChanged,
          }) {
            return DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                borderRadius: BorderRadius.circular(12),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                icon: Icon(
                  Icons.unfold_more,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                items: [
                  for (final (option, label) in options)
                    DropdownMenuItem(value: option, child: Text(label)),
                ],
                onChanged: (picked) {
                  if (picked != null) onChanged(picked);
                },
              ),
            );
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + inset),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 128,
                      child: Stack(
                        children: [
                          Container(
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  scheme.primary,
                                  scheme.secondary.withValues(alpha: 0.75),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            top: 32,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: theme.cardTheme.color ?? scheme.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Avatar(
                                label: me.name.isEmpty ? '?' : me.name,
                                image: me.avatar,
                                size: 76,
                                online: reach == Reach.online,
                                availability: me.availability,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 16,
                            top: 86,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 34),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                side: BorderSide(color: scheme.outline),
                                foregroundColor: scheme.onSurface,
                              ),
                              onPressed: () => Navigator.pushNamed(
                                context,
                                '/dashboard/settings/profile',
                              ),
                              child: const Text('Edit Profile'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            me.name.isEmpty ? 'Set Your Name' : me.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
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
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              for (final (count, label) in [
                                (trustees.length, 'Trustees'),
                                (online, 'Online'),
                              ]) ...[
                                Text(
                                  '$count',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(label, style: theme.textTheme.bodySmall),
                                const SizedBox(width: 16),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      onTap: status,
                      leading: SizedBox(
                        width: 24,
                        child: Center(
                          child: Glyph(availability: me.availability),
                        ),
                      ),
                      title: Text(me.availability.label),
                      subtitle: Text(me.availability.hint),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Identifier(address: address, name: me.name),
              const Heading('Privacy'),
              Group(
                children: [
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
                    onChanged: (value) =>
                        tune((next) => next.strangers = value),
                  ),
                  ListTile(
                    leading: const Icon(Icons.block),
                    title: const Text('Blocked'),
                    subtitle: const Text('Manage blocked keys in Trustees'),
                    trailing: Pill(count: blocked),
                  ),
                ],
              ),
              const Heading('Notifications'),
              Group(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined),
                    title: const Text('In-App Banners'),
                    subtitle: const Text(
                      'Muted automatically on Do not disturb',
                    ),
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
                ],
              ),
              const Heading('Media'),
              Group(
                children: [
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
                      color: Giphy.ready
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text('GIF Content Rating'),
                    trailing: choice<Rating>(
                      value: prefs.rating,
                      options: [
                        for (final rating in Rating.values)
                          (rating, rating.label),
                      ],
                      onChanged: (picked) =>
                          tune((next) => next.rating = picked),
                    ),
                  ),
                ],
              ),
              const Heading('Appearance'),
              Group(
                children: [
                  ListTile(
                    leading: const Icon(Icons.brightness_6_outlined),
                    title: const Text('Theme'),
                    trailing: choice<ThemeMode>(
                      value: prefs.theme,
                      options: const [
                        (ThemeMode.system, 'System'),
                        (ThemeMode.light, 'Light'),
                        (ThemeMode.dark, 'Dark'),
                      ],
                      onChanged: (picked) =>
                          tune((next) => next.theme = picked),
                    ),
                  ),
                ],
              ),
              const Heading('Network & Routing'),
              Group(
                children: [
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
                    trailing: value(version),
                  ),
                ],
              ),
              const Heading('Security'),
              const Group(
                children: [
                  ListTile(
                    leading: Icon(Icons.storage_outlined),
                    title: Text('Local Storage'),
                    subtitle: Text(
                      'SQLCipher with an Argon2id key; attachments sealed with AES-256-GCM',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.key_outlined),
                    title: Text('Message Signing'),
                    subtitle: Text('Ed25519, bound to your discovery key'),
                  ),
                  ListTile(
                    leading: Icon(Icons.gpp_maybe_outlined),
                    title: Text('Unlock Protection'),
                    subtitle: Text(
                      '${Warden.lockout} wrong passphrases across identities lock them all. Attempts that look like an attack erase every identity on this phone.',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.timer_outlined),
                    title: Text('Inactivity Timeout'),
                    subtitle: Text('Auto-lock vault after 10 minutes of idle'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.6)),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: lock,
                icon: const Icon(Icons.lock_outlined),
                label: const Text('Lock Vault'),
              ),
              const SizedBox(height: 16),
              Text(
                'Zephyron · Tor $version',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          );
        },
      ),
    );
  }
}
