import 'package:flutter/material.dart';
import 'package:zephyron/auth/panic.dart';
import 'package:zephyron/dashboard/chats/compose.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/duress.dart';
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
  String? decoy;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final armed = await Duress.decoy();
    if (mounted) setState(() => decoy = armed);
  }

  Future<void> duress() async {
    final navigator = Navigator.of(context);
    if (decoy == Session.profile && decoy != null) {
      await Sheets.actions(
        context,
        items: [
          SheetAction(
            icon: Icons.edit_outlined,
            label: 'Change Duress Passphrase',
            onTap: () async {
              await navigator.pushNamed('/dashboard/settings/duress');
              await refresh();
            },
          ),
          SheetAction(
            icon: Icons.remove_moderator_outlined,
            label: 'Turn Off',
            destructive: true,
            onTap: () async {
              await Duress.disarm();
              await refresh();
            },
          ),
        ],
      );
      return;
    }
    await navigator.pushNamed('/dashboard/settings/duress');
    await refresh();
  }

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

  /// Picks which trustee is this identity's mailbox, or which trustee this
  /// phone is a mailbox for.
  Future<void> mailbox({required bool own}) async {
    final trustees =
        courier.roster.values.where((item) => item.trusted).toList()
          ..sort((alpha, beta) => alpha.label.compareTo(beta.label));
    final current = own ? courier.me.mailbox : courier.prefs.serve;
    final picked = await Sheets.pick<String>(
      context,
      title: own ? 'Your Mailbox' : 'Be a Mailbox',
      subtitle: own
          ? 'Pick a trustee that is nearly always online, ideally another phone of yours. It holds sealed messages for you and cannot read them.'
          : 'This phone will hold sealed messages for the trustee you pick while they are offline, from anyone writing to them.',
      current: current,
      options: [
        Choice(
          value: '',
          label: 'None',
          leading: Icon(
            Icons.block,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        for (final trustee in trustees)
          Choice(
            value: trustee.address,
            label: trustee.label,
            leading: Portrait(
              address: trustee.address,
              size: 28,
              presence: false,
            ),
          ),
      ],
    );
    if (picked == null || picked == current) return;
    if (own) {
      await courier.publish(courier.me.copy()..mailbox = picked);
    } else {
      tune((next) => next.serve = picked);
    }
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
                          Cover(banner: me.banner, height: 72),
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
                  SwitchListTile(
                    secondary: const Icon(Icons.move_to_inbox_outlined),
                    title: const Text('Carry Messages'),
                    subtitle: const Text(
                      'Hold sealed messages for trustees while the person they are for is offline. You cannot read them',
                    ),
                    value: prefs.carry,
                    onChanged: (value) => tune((next) => next.carry = value),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.screenshot_monitor_outlined),
                    title: const Text('Screen Security'),
                    subtitle: const Text(
                      'Block screenshots and screen recording, and hide chats in the app switcher',
                    ),
                    value: prefs.shield,
                    onChanged: (value) => tune((next) => next.shield = value),
                  ),
                  ListTile(
                    leading: const Icon(Icons.block),
                    title: const Text('Blocked'),
                    subtitle: const Text('Manage blocked keys in Trustees'),
                    trailing: Pill(count: blocked),
                  ),
                ],
              ),
              const Heading(
                'Delivery',
                description:
                    'Messages go straight to the other phone. When it is offline, trustees hold them sealed until it is back.',
              ),
              Group(
                children: [
                  ListTile(
                    leading: const Icon(Icons.markunread_mailbox_outlined),
                    title: const Text('Your Mailbox'),
                    subtitle: Text(
                      me.mailbox.isEmpty
                          ? 'None. A spare always-on phone of yours can hold messages for you'
                          : 'Trustees leave messages with ${courier.roster[me.mailbox]?.label ?? me.mailbox.substring(0, 10)} while you are offline',
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () => mailbox(own: true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: const Text('Be a Mailbox'),
                    subtitle: Text(
                      prefs.serve.isEmpty
                          ? 'Off. Turn this phone into the mailbox of a trustee'
                          : 'Holding messages for ${courier.roster[prefs.serve]?.label ?? prefs.serve.substring(0, 10)}. Keep this phone unlocked and charging',
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () => mailbox(own: false),
                  ),
                ],
              ),
              const Heading(
                'Discover',
                description:
                    'An opt-in directory that travels between trustees\' phones, so people can find each other without a server.',
              ),
              Group(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.travel_explore),
                    title: const Text('List Me in Discover'),
                    subtitle: const Text(
                      'Anyone the listing reaches sees your name, bio, picture and discovery key, and can send you a request',
                    ),
                    value: prefs.listed,
                    onChanged: (value) => tune((next) => next.listed = value),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.share_outlined),
                    title: const Text('Pass Along Listings'),
                    subtitle: const Text(
                      'Share the listings this phone holds with your trustees, so discovery reaches further',
                    ),
                    value: prefs.spread,
                    onChanged: (value) => tune((next) => next.spread = value),
                  ),
                  ListTile(
                    leading: const Icon(Icons.explore_outlined),
                    title: const Text('Browse Discover'),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/dashboard/communities/discover',
                    ),
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
              Group(
                children: [
                  ListTile(
                    leading: const Icon(Icons.theater_comedy_outlined),
                    title: const Text('Duress Passphrase'),
                    subtitle: Text(
                      decoy == null
                          ? 'Off. Set one that erases everything but this identity'
                          : decoy == Session.profile
                          ? 'On. Opens this identity and erases the rest'
                          : 'On, for another identity on this phone',
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: duress,
                  ),
                  ListTile(
                    leading: Icon(Icons.storage_outlined),
                    title: Text('Local Storage'),
                    subtitle: Text(
                      "SQLCipher with an Argon2id key bound to this phone's secure hardware; attachments sealed with AES-256-GCM",
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.key_outlined),
                    title: Text('Message Signing'),
                    subtitle: Text('Ed25519, bound to your discovery key'),
                  ),
                  ListTile(
                    leading: Icon(Icons.enhanced_encryption_outlined),
                    title: Text('End-to-End Encryption'),
                    subtitle: Text(
                      'ML-KEM-768 with X25519, then the Double Ratchet and AES-256-GCM, inside Tor. Every message and file has its own key',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.gpp_maybe_outlined),
                    title: Text('Unlock Protection'),
                    subtitle: Text(
                      '${Warden.lockout} wrong passphrases across identities lock them all. Attempts that look like an attack erase every identity on this phone.',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.crisis_alert_outlined),
                    title: Text('Panic Wipe'),
                    subtitle: Text(
                      'Long-press the app icon or the unlock screen title to erase everything after a ${PanicPage.grace} second countdown',
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
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.pushNamed(context, '/panic'),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Erase Everything'),
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
