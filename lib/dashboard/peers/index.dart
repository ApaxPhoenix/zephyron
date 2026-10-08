import 'package:flutter/material.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/dashboard/chats/compose.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/beacon.dart';
import 'package:zephyron/widgets/stamp.dart';

class PeersPage extends StatefulWidget {
  const PeersPage({super.key});

  @override
  State<PeersPage> createState() => PeersPageState();
}

class PeersPageState extends State<PeersPage> {
  final TextEditingController search = TextEditingController();
  bool reveal = false;

  Courier get courier => Courier.instance;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void open(Trustee trustee) {
    Navigator.pushNamed(
      context,
      '/dashboard/peers/node',
      arguments: {'id': trustee.address},
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Trustees'),
        actions: [
          const Center(child: Beacon()),
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: IconButton(
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () => Compose.show(context),
              tooltip: 'Add Trustee',
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: courier,
        builder: (context, _) {
          final query = search.text.trim().toLowerCase();
          final everyone =
              courier.roster.values
                  .where(
                    (item) =>
                        query.isEmpty ||
                        item.label.toLowerCase().contains(query) ||
                        item.alias.toLowerCase().contains(query) ||
                        item.address.contains(query),
                  )
                  .toList()
                ..sort(
                  (alpha, beta) => alpha.label.toLowerCase().compareTo(
                    beta.label.toLowerCase(),
                  ),
                );
          final requests = everyone.where((item) => item.stranger).toList();
          final trusted = everyone.where((item) => item.trusted);
          final online = trusted
              .where((item) => courier.online(item.address))
              .toList();
          final offline = trusted
              .where((item) => !courier.online(item.address))
              .toList();
          final blocked = everyone.where((item) => item.blocked).toList();

          Widget header(String text, int count, {Widget? trailing}) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 8, 6),
              child: Row(
                children: [
                  Text(text, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outline),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            );
          }

          Widget tile(Trustee trustee) {
            final presence = courier.status(trustee.address);
            final live = courier.online(trustee.address);
            final detail = trustee.blocked
                ? null
                : live
                ? (trustee.availability != Availability.available
                      ? trustee.availability.label
                      : presence.latency != null
                      ? '${presence.latency}ms'
                      : 'Online')
                : presence.seen != null &&
                      trustee.availability != Availability.invisible
                ? ago(presence.seen!)
                : null;

            return ListTile(
              key: ValueKey(trustee.address),
              onTap: () => open(trustee),
              leading: AnimatedOpacity(
                opacity: trustee.blocked ? 0.5 : 1,
                duration: const Duration(milliseconds: 200),
                child: Portrait(address: trustee.address, size: 48),
              ),
              title: Text(
                trustee.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                trustee.mood.isNotEmpty ? trustee.mood : trustee.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: trustee.mood.isNotEmpty
                    ? null
                    : const TextStyle(fontFamily: Pallete.mono, fontSize: 12),
              ),
              trailing: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  detail ?? '',
                  key: ValueKey(detail),
                  style: TextStyle(
                    color: live
                        ? Avatar.tone(trustee.availability)
                        : scheme.onSurfaceVariant,
                    fontWeight: live ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }

          final children = <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: search,
                decoration: InputDecoration(
                  hintText: 'Search name or discovery key…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: search.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => setState(search.clear),
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Identifier(
                address: courier.self?.address ?? '',
                name: courier.me.name,
                compact: true,
              ),
            ),
          ];

          if (courier.roster.isEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.verified_user_outlined,
                        size: 48,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No Trustees Yet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Share your discovery key above, or add someone by theirs. Only trustees see your profile.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            if (requests.isNotEmpty) {
              children.add(header('Requests', requests.length));
              for (final trustee in requests) {
                children.add(
                  ListTile(
                    key: ValueKey('request:${trustee.address}'),
                    onTap: () => open(trustee),
                    leading: Portrait(
                      address: trustee.address,
                      size: 48,
                      presence: false,
                    ),
                    title: Text(
                      trustee.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      courier.last(trustee.address)?.preview ??
                          'Wants to message you',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Block',
                          icon: Icon(Icons.block, color: scheme.error),
                          onPressed: () =>
                              courier.trust(trustee.address, Trust.blocked),
                        ),
                        IconButton(
                          tooltip: 'Accept as Trustee',
                          icon: Icon(
                            Icons.check_circle_outline,
                            color: scheme.primary,
                          ),
                          onPressed: () =>
                              courier.trust(trustee.address, Trust.trustee),
                        ),
                      ],
                    ),
                  ),
                );
              }
            }
            if (online.isNotEmpty) {
              children.add(header('Online', online.length));
              children.addAll(online.map(tile));
            }
            if (offline.isNotEmpty) {
              children.add(header('Offline', offline.length));
              children.addAll(offline.map(tile));
            }
            if (blocked.isNotEmpty) {
              children.add(
                header(
                  'Blocked',
                  blocked.length,
                  trailing: IconButton(
                    icon: AnimatedRotation(
                      turns: reveal ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    onPressed: () => setState(() => reveal = !reveal),
                  ),
                ),
              );
              children.add(
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: reveal
                      ? Column(children: blocked.map(tile).toList())
                      : const SizedBox(width: double.infinity),
                ),
              );
            }
            children.add(const SizedBox(height: 24));
          }

          return RefreshIndicator(
            onRefresh: () => Future.wait(
              courier.roster.values
                  .where((item) => item.trusted)
                  .map((item) => courier.ping(item.address)),
            ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: children,
            ),
          );
        },
      ),
    );
  }
}
