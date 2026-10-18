import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/compose.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/beacon.dart';
import 'package:zephyron/widgets/section.dart';
import 'package:zephyron/widgets/sheet.dart';
import 'package:zephyron/widgets/stamp.dart';

class Chats extends StatefulWidget {
  const Chats({super.key});

  @override
  State<Chats> createState() => _Chats();
}

class _Chats extends State<Chats> {
  final TextEditingController search = TextEditingController();
  final Set<String> shown = {};
  Filter filter = Filter.all;

  Courier get courier => Courier.instance;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> compose() => Sheets.actions(
    context,
    items: [
      Command(
        icon: Icons.chat_bubble_outline,
        label: 'New Chat',
        run: () async {
          final contact = await Compose.show(context);
          if (contact == null || !mounted) return;
          Navigator.pushNamed(
            context,
            '/dashboard/chats/message',
            arguments: {'id': contact.address},
          );
        },
      ),
      Command(
        icon: Icons.group_add_outlined,
        label: 'New Group',
        run: () => Navigator.pushNamed(context, '/dashboard/chats/group'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Chats'),
        actions: [
          const Center(child: Beacon()),
          IconButton(
            icon: const Icon(Icons.travel_explore),
            tooltip: 'Discover People',
            onPressed: () => Navigator.pushNamed(
              context,
              '/dashboard/communities/discover',
              arguments: {'shelf': Shelf.person.name},
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: IconButton(
              icon: const Icon(Icons.add),
              onPressed: compose,
              tooltip: 'New Conversation',
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([courier, Mesh.instance]),
        builder: (context, _) {
          final mesh = Mesh.instance;
          final query = search.text.trim().toLowerCase();
          final list =
              courier.roster.values.where((contact) {
                if (contact.blocked != (filter == Filter.blocked)) {
                  return false;
                }
                if (filter == Filter.requests && !contact.stranger) {
                  return false;
                }
                if (filter != Filter.blocked &&
                    contact.archived != (filter == Filter.archived)) {
                  return false;
                }
                if (filter == Filter.unread &&
                    courier.unread(contact.address) == 0) {
                  return false;
                }
                if (filter == Filter.pinned && !contact.pinned) {
                  return false;
                }
                if (query.isEmpty) return true;
                return contact.label.toLowerCase().contains(query) ||
                    contact.address.contains(query) ||
                    (courier
                            .last(contact.address)
                            ?.text
                            .toLowerCase()
                            .contains(query) ??
                        false);
              }).toList()..sort((alpha, beta) {
                if (alpha.pinned != beta.pinned) return alpha.pinned ? -1 : 1;
                final left = courier.last(alpha.address)?.time ?? alpha.created;
                final right = courier.last(beta.address)?.time ?? beta.created;
                return right.compareTo(left);
              });
          final rooms =
              const {
                Filter.archived,
                Filter.unread,
                Filter.requests,
                Filter.blocked,
              }.contains(filter)
              ? const <Community>[]
              : mesh
                    .groups()
                    .where((group) => filter != Filter.pinned || group.pinned)
                    .where(
                      (group) =>
                          query.isEmpty ||
                          group.name.toLowerCase().contains(query),
                    )
                    .toList();
          DateTime when(Object entry) => entry is Community
              ? mesh.active(entry)
              : courier.last((entry as Trustee).address)?.time ?? entry.created;
          bool pinned(Object entry) =>
              entry is Community ? entry.pinned : (entry as Trustee).pinned;
          final sorted =
              <Object>[if (filter != Filter.groups) ...list, ...rooms]
                ..sort((alpha, beta) {
                  if (pinned(alpha) != pinned(beta)) {
                    return pinned(alpha) ? -1 : 1;
                  }
                  return when(beta).compareTo(when(alpha));
                });

          // With nothing narrowed down, one list holds requests, then
          // conversations, then the trustees nobody has written to yet.
          final entries = <Object>[];
          final counts = <String, int>{};
          void section(String title, List<Object> items, {bool label = true}) {
            if (items.isEmpty) return;
            if (label) {
              entries.add(title);
              counts[title] = items.length;
            }
            entries.addAll(items);
          }

          if (filter == Filter.requests) {
            section('Requests', list.map(Plea.new).toList(), label: false);
          } else if (filter == Filter.blocked) {
            section('Blocked', list.map(Quiet.new).toList(), label: false);
          } else if (filter == Filter.all && query.isEmpty) {
            bool talked(Object item) =>
                item is Community ||
                (item is Trustee && courier.last(item.address) != null);
            final pleas = [
              for (final item in sorted)
                if (item is Trustee && item.stranger) Plea(item),
            ];
            final talks = [
              for (final item in sorted)
                if (talked(item) && !(item is Trustee && item.stranger)) item,
            ];
            final quiet =
                [
                  for (final item in sorted)
                    if (item is Trustee && !item.stranger && !talked(item))
                      Quiet(item),
                ]..sort((alpha, beta) {
                  final left = courier.online(alpha.trustee.address);
                  final right = courier.online(beta.trustee.address);
                  if (left != right) return left ? -1 : 1;
                  return alpha.trustee.label.toLowerCase().compareTo(
                    beta.trustee.label.toLowerCase(),
                  );
                });
            section('Requests', pleas);
            section(
              'Conversations',
              talks,
              label: pleas.isNotEmpty || quiet.isNotEmpty,
            );
            section('Trustees', quiet);
          } else {
            entries.addAll(sorted);
          }

          /// A trustee with no messages yet, or a blocked key, and whether
          /// they are around.
          Widget person(Trustee trustee) {
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
              key: ValueKey('trustee:${trustee.address}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 4.0,
              ),
              onTap: () => Navigator.pushNamed(
                context,
                trustee.blocked
                    ? '/dashboard/peers/node'
                    : '/dashboard/chats/message',
                arguments: {'id': trustee.address},
              ),
              onLongPress: () => Navigator.pushNamed(
                context,
                '/dashboard/peers/node',
                arguments: {'id': trustee.address},
              ),
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
              trailing: Text(
                detail ?? '',
                style: TextStyle(
                  color: live
                      ? Avatar.tone(trustee.availability)
                      : scheme.onSurfaceVariant,
                  fontWeight: live ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }

          Widget room(Community group) {
            final latest = mesh.latest(group.id);
            final count = mesh.members(group.id).length;
            return ListTile(
              key: ValueKey('group:${group.id}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 4.0,
              ),
              onTap: () => (Navigator.pushNamed(
                context,
                '/dashboard/communities/channel',
                arguments: {'community': group.id, 'channel': group.general},
              )),
              leading: Crest(label: group.name, image: group.icon, size: 48),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (latest != null)
                    Text(
                      brief(latest.time),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  latest != null
                      ? '${mesh.called(group.id, latest.author)}: ${latest.text}'
                      : '$count ${count == 1 ? 'member' : 'members'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }

          Widget content;
          if (courier.roster.isEmpty && mesh.groups().isEmpty) {
            content = Center(
              key: const ValueKey('welcome'),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(32, 32, 32, 32 + inset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mark_chat_read_outlined,
                        size: 48,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No Conversations Yet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add a trustee by their discovery key. Messages travel peer to peer over Tor onion services.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: compose,
                        icon: const Icon(Icons.add_outlined),
                        label: const Text('Start New Chat'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else if (entries.isEmpty) {
            content = Center(
              key: ValueKey('empty:${filter.name}'),
              child: Padding(
                padding: EdgeInsets.fromLTRB(32, 32, 32, 32 + inset),
                child: Text(
                  search.text.isNotEmpty
                      ? 'No chats match "${search.text}"'
                      : 'Nothing here yet',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          } else {
            content = RefreshIndicator(
              key: ValueKey('list:${filter.name}'),
              onRefresh: () => Future.wait(
                courier.roster.values
                    .where((item) => item.trusted)
                    .map((item) => courier.ping(item.address)),
              ),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: 4, bottom: 16 + inset),
                itemCount: entries.length,
                separatorBuilder: (context, index) =>
                    entries[index] is String || entries[index + 1] is String
                    ? const SizedBox.shrink()
                    : Divider(
                        height: 1,
                        indent: 84,
                        color: scheme.outlineVariant.withAlpha(50),
                      ),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  if (entry is String) {
                    return (Heading(
                      entry,
                      count: counts[entry],
                      padding: const EdgeInsets.fromLTRB(24, 20, 12, 6),
                    ));
                  }
                  if (entry is Community) return room(entry);
                  if (entry is Plea) {
                    return (ListTile(
                      key: ValueKey('request:${entry.trustee.address}'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 4.0,
                      ),
                      onTap: () => Navigator.pushNamed(
                        context,
                        '/dashboard/chats/message',
                        arguments: {'id': entry.trustee.address},
                      ),
                      leading: Portrait(
                        address: entry.trustee.address,
                        size: 48,
                        presence: false,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.trustee.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            Trust.stranger.label,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.secondary),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        courier.last(entry.trustee.address)?.preview ??
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
                            onPressed: () => courier.trust(
                              entry.trustee.address,
                              Trust.blocked,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Accept as Trustee',
                            icon: Icon(
                              Icons.check_circle_outline,
                              color: scheme.primary,
                            ),
                            onPressed: () => courier.trust(
                              entry.trustee.address,
                              Trust.trustee,
                            ),
                          ),
                        ],
                      ),
                    ));
                  }
                  if (entry is Quiet) return person(entry.trustee);
                  final contact = entry as Trustee;
                  final last = courier.last(contact.address);
                  final unread = courier.unread(contact.address);
                  final bold = unread > 0;
                  final composing = courier.status(contact.address).composing;
                  final fresh = shown.add(contact.address);

                  Widget row = Dismissible(
                    key: ValueKey('swipe:${contact.address}'),
                    dismissThresholds: const {
                      DismissDirection.startToEnd: 0.25,
                      DismissDirection.endToStart: 0.35,
                    },
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 24),
                      color: scheme.primaryContainer,
                      child: Icon(
                        contact.pinned
                            ? Icons.push_pin_outlined
                            : Icons.push_pin,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    secondaryBackground: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        contact.archived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        courier.amend(contact..pinned = !contact.pinned);
                        return false;
                      }
                      return true;
                    },
                    onDismissed: (_) {
                      contact.archived = !contact.archived;
                      setState(() {});
                      courier.amend(contact);
                    },
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 4.0,
                      ),
                      leading: Hero(
                        tag: 'avatar:${contact.address}',
                        child: Portrait(address: contact.address, size: 48),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    contact.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontWeight: bold
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (contact.stranger) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    Trust.stranger.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: scheme.secondary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (last != null)
                            Text(
                              brief(last.time),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: bold
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                    fontWeight: bold
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            if (last != null && last.mine && !composing) ...[
                              Tick(
                                status: last.status,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (last != null &&
                                last.kind != Kind.text &&
                                !composing) ...[
                              Icon(
                                switch (last.kind) {
                                  Kind.image => Icons.photo_outlined,
                                  Kind.gif => Icons.gif_box_outlined,
                                  Kind.file => Icons.insert_drive_file_outlined,
                                  _ => Icons.person_outline,
                                },
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                layoutBuilder: (current, previous) => Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [...previous, ?current],
                                ),
                                child: Text(
                                  composing
                                      ? 'typing…'
                                      : last?.preview ??
                                            (contact.stranger
                                                ? 'Wants to message you'
                                                : 'Say hello'),
                                  key: ValueKey(composing),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: composing
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                            if (contact.pinned) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.push_pin,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                              child: unread > 0
                                  ? Padding(
                                      key: ValueKey(unread),
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Badge(
                                        backgroundColor: scheme.secondary,
                                        label: Text(
                                          unread > 99 ? '99+' : '$unread',
                                          style: TextStyle(
                                            color: scheme.onSecondary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      onTap: () => Navigator.pushNamed(
                        context,
                        '/dashboard/chats/message',
                        arguments: {'id': contact.address},
                      ),
                      onLongPress: () => Sheets.actions(
                        context,
                        header: ListTile(
                          leading: Portrait(
                            address: contact.address,
                            size: 40,
                            presence: false,
                          ),
                          title: Text(
                            contact.label,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            contact.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        items: [
                          Command(
                            icon: contact.pinned
                                ? Icons.push_pin_outlined
                                : Icons.push_pin,
                            label: contact.pinned ? 'Unpin' : 'Pin to Top',
                            run: () => courier.amend(
                              contact..pinned = !contact.pinned,
                            ),
                          ),
                          Command(
                            icon: contact.archived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                            label: contact.archived ? 'Unarchive' : 'Archive',
                            run: () => courier.amend(
                              contact..archived = !contact.archived,
                            ),
                          ),
                          Command(
                            icon: Icons.info_outline,
                            label: 'View Profile',
                            run: () => Navigator.pushNamed(
                              context,
                              '/dashboard/peers/node',
                              arguments: {'id': contact.address},
                            ),
                          ),
                          Command(
                            icon: Icons.block,
                            label: 'Block',
                            destructive: true,
                            run: () async {
                              final sure = await Sheets.confirm(
                                context,
                                title: 'Block ${contact.label}?',
                                message:
                                    'Everything from this discovery key is dropped until you unblock it under Blocked.',
                                action: 'Block',
                              );
                              if (sure) {
                                await courier.trust(
                                  contact.address,
                                  Trust.blocked,
                                );
                              }
                            },
                          ),
                          Command(
                            icon: Icons.cleaning_services_outlined,
                            label: 'Clear History',
                            destructive: true,
                            run: () async {
                              final sure = await Sheets.confirm(
                                context,
                                title: 'Clear History?',
                                message:
                                    'Every message with ${contact.label} will be wiped from this device.',
                                action: 'Clear',
                              );
                              if (sure) await courier.clear(contact.address);
                            },
                          ),
                          Command(
                            icon: Icons.delete_outline,
                            label: 'Delete Chat',
                            destructive: true,
                            run: () async {
                              final sure = await Sheets.confirm(
                                context,
                                title: 'Delete Chat?',
                                message:
                                    'This removes ${contact.label} and the full conversation from this device.',
                              );
                              if (sure) await courier.remove(contact.address);
                            },
                          ),
                        ],
                      ),
                    ),
                  );

                  if (fresh && !MediaQuery.disableAnimationsOf(context)) {
                    row = TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(
                        milliseconds: 220 + index.clamp(0, 8) * 30,
                      ),
                      curve: Curves.easeOutCubic,
                      child: row,
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 12 * (1 - value)),
                          child: child,
                        ),
                      ),
                    );
                  }
                  return row;
                },
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (courier.roster.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: TextField(
                    controller: search,
                    decoration: InputDecoration(
                      hintText: 'Search trustees or messages…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: search.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: scheme.onSurfaceVariant,
                                ),
                                onPressed: () => setState(search.clear),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      for (final item in [
                        Filter.all,
                        Filter.unread,
                        Filter.requests,
                        Filter.groups,
                        Filter.pinned,
                        Filter.archived,
                        Filter.blocked,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text(item.label),
                            selected: filter == item,
                            labelStyle: TextStyle(
                              color: filter == item
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            onSelected: (_) => setState(() => filter = item),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: content,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class Tick extends StatelessWidget {
  final Status status;
  final Color color;
  final Color? highlight;
  final double size;

  const Tick({
    super.key,
    required this.status,
    required this.color,
    this.highlight,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tone) = switch (status) {
      Status.sending => (Icons.schedule, color),
      Status.sent => (Icons.done, color),
      Status.delivered => (Icons.done_all, color),
      Status.read => (
        Icons.done_all,
        highlight ?? Theme.of(context).colorScheme.secondary,
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: Icon(
        icon,
        key: ValueKey(status),
        size: status == Status.sending ? size - 3 : size,
        color: tone,
      ),
    );
  }
}

/// Someone asking to message you, shown with Accept and Block.
class Plea {
  final Trustee trustee;

  const Plea(this.trustee);
}

/// A trustee shown by presence rather than by conversation.
class Quiet {
  final Trustee trustee;

  const Quiet(this.trustee);
}
