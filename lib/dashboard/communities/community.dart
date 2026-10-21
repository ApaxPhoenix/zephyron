import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/communities/index.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/section.dart';
import 'package:zephyron/widgets/sheet.dart';
import 'package:zephyron/widgets/stamp.dart';

class CommunityPage extends StatefulWidget {
  final String? id;

  const CommunityPage({super.key, this.id});

  @override
  State<CommunityPage> createState() => CommunityPageState();
}

class CommunityPageState extends State<CommunityPage> {
  final TextEditingController search = TextEditingController();
  int page = 0;

  /// Members shown per page.
  static const int crowd = 8;

  Mesh get mesh => Mesh.instance;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> invite(Community community) async {
    final courier = Courier.instance;
    final trustees =
        courier.roster.values
            .where((item) => item.trusted)
            .where((item) => !mesh.member(community.id, item.address))
            .toList()
          ..sort((alpha, beta) => alpha.label.compareTo(beta.label));
    if (trustees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every trustee is already here, or you have none yet.'),
        ),
      );
      return;
    }
    final picked = await Sheets.pick<String>(
      context,
      title: 'Invite a Trustee',
      subtitle:
          'They get the invitation in your chat, end-to-end encrypted. Anyone you invite can invite others.',
      current: '',
      options: [
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
    if (picked == null) return;
    await mesh.invite(community, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invitation sent to ${courier.roster[picked]?.label}.'),
      ),
    );
  }

  Future<void> add(Community community) async {
    final field = TextEditingController();
    var kind = Space.text;
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, refresh) => AlertDialog(
          title: const Text('New Channel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<Space>(
                showSelectedIcon: false,
                segments: [
                  for (final option in const [Space.text, Space.podcast])
                    ButtonSegment(
                      value: option,
                      label: Text(option.label),
                      icon: Mark(kind: option),
                    ),
                ],
                selected: {kind},
                onSelectionChanged: (picked) =>
                    refresh(() => kind = picked.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: field,
                autofocus: true,
                maxLength: 32,
                decoration: InputDecoration(
                  hintText: switch (kind) {
                    Space.text => 'announcements',
                    Space.podcast => 'weekly-show',
                    Space.voice => 'lounge',
                  },
                  prefixText: kind == Space.text ? '# ' : null,
                ),
                onSubmitted: (value) => Navigator.pop(dialog, value),
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    field.dispose();
    if (name == null || name.trim().isEmpty) return;
    final room = await mesh.channel(community, name, kind);
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/dashboard/communities/channel',
      arguments: {'community': community.id, 'channel': room.id},
    );
  }

  Future<void> more(Community community) async {
    await Sheets.actions(
      context,
      header: ListTile(
        leading: Crest(label: community.name, image: community.icon, size: 40),
        title: Text(
          community.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${mesh.members(community.id).length} members'),
      ),
      items: [
        SheetAction(
          icon: Icons.edit_outlined,
          label: 'Edit Community',
          onTap: () => Navigator.pushNamed(
            context,
            '/dashboard/communities/create',
            arguments: {'id': community.id},
          ),
        ),
        SheetAction(
          icon: community.pinned ? Icons.push_pin_outlined : Icons.push_pin,
          label: community.pinned ? 'Unpin' : 'Pin to Top',
          onTap: () => mesh.amend(community..pinned = !community.pinned),
        ),
        SheetAction(
          icon: community.muted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: community.muted ? 'Unmute' : 'Mute',
          onTap: () => mesh.amend(community..muted = !community.muted),
        ),
        SheetAction(
          icon: Icons.logout,
          label: 'Leave Community',
          destructive: true,
          onTap: () async {
            final navigator = Navigator.of(context);
            final sure = await Sheets.confirm(
              context,
              title: 'Leave ${community.name}?',
              message:
                  'Its key and every post are wiped from this phone. You need a new invitation to come back.',
              action: 'Leave',
            );
            if (!sure) return;
            await mesh.leave(community.id);
            navigator.pop();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([mesh, Courier.instance]),
      builder: (context, _) {
        final community = mesh.communities[widget.id];
        if (community == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(
                'You are no longer in this community.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }

        final query = search.text.trim().toLowerCase();
        final rooms = mesh
            .rooms(community.id)
            .where((room) => query.isEmpty || room.name.contains(query))
            .toList();
        final everyone = mesh.members(community.id);
        final people = everyone
            .where(
              (member) =>
                  query.isEmpty ||
                  mesh
                      .called(community.id, member.address)
                      .toLowerCase()
                      .contains(query),
            )
            .toList();
        final pages = Pager.count(people.length, crowd);
        final current = page.clamp(0, pages - 1);

        Widget room(Room room) {
          final last = mesh.messages(community.id, room.id).lastOrNull;
          return ListTile(
            onTap: () => Navigator.pushNamed(
              context,
              '/dashboard/communities/channel',
              arguments: {'community': community.id, 'channel': room.id},
            ),
            leading: SizedBox(
              width: 24,
              child: Center(child: Mark(kind: room.kind)),
            ),
            title: Text(room.name),
            subtitle: Text(
              last == null
                  ? 'No messages yet'
                  : '${mesh.called(community.id, last.author)}: ${last.text}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: last == null
                ? null
                : Text(brief(last.time), style: theme.textTheme.labelSmall),
          );
        }

        Widget person(Member member) {
          final rank = everyone.indexOf(member) + 1;
          final trustee = Courier.instance.roster[member.address];
          final yourself = member.address == Courier.instance.self?.address;
          return ListTile(
            onTap: trustee == null || yourself
                ? null
                : () => Navigator.pushNamed(
                    context,
                    '/dashboard/peers/node',
                    arguments: {'id': member.address},
                  ),
            leading: trustee != null
                ? Portrait(address: member.address, size: 40)
                : Avatar(
                    label: mesh.called(community.id, member.address),
                    image: yourself
                        ? Courier.instance.me.avatar
                        : member.avatar,
                    size: 40,
                  ),
            title: Text(
              yourself
                  ? '${mesh.called(community.id, member.address)} (you)'
                  : mesh.called(community.id, member.address),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              member.address == community.founder
                  ? 'Started this community'
                  : 'Joined ${brief(member.since)}',
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: rank == 1
                    ? scheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
                border: Border.all(
                  color: rank == 1
                      ? scheme.primary.withValues(alpha: 0.4)
                      : scheme.outline,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '#$rank',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: rank == 1 ? scheme.primary : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            title: Text(community.name),
            actions: [
              IconButton(
                tooltip: 'Invite',
                icon: const Icon(Icons.person_add_alt_outlined),
                onPressed: () => invite(community),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => more(community),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              32 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              SizedBox(
                height: 176,
                child: Stack(
                  children: [
                    Cover(
                      banner: community.banner,
                      height: 128,
                      radius: BorderRadius.circular(16),
                    ),
                    Positioned(
                      left: 16,
                      top: 84,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Crest(
                          label: community.name,
                          image: community.icon,
                          size: 80,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (community.about.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        community.about,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final (count, label) in [
                          (everyone.length, 'Members'),
                          (mesh.rooms(community.id).length, 'Channels'),
                        ]) ...[
                          Text(
                            '$count',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => invite(community),
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('Invite'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: scheme.outline),
                        foregroundColor: scheme.onSurface,
                      ),
                      onPressed: () => add(community),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Channel'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: search,
                decoration: InputDecoration(
                  hintText: 'Search channels and members…',
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
                onChanged: (_) => setState(() => page = 0),
              ),
              Heading('Channels', count: rooms.length),
              if (rooms.isEmpty)
                const Vacant(icon: Icons.tag, text: 'No channels match.')
              else
                Group(indent: 64, children: rooms.map(room).toList()),
              Heading(
                'Members',
                count: people.length,
                description:
                    'Listed by when they joined. Nobody here outranks anyone else.',
              ),
              if (people.isEmpty)
                const Vacant(
                  icon: Icons.person_search_outlined,
                  text: 'No members match.',
                )
              else
                Group(
                  indent: 76,
                  children: Pager.slice(
                    people,
                    current,
                    crowd,
                  ).map(person).toList(),
                ),
              if (pages > 1)
                Pager(
                  page: current,
                  pages: pages,
                  onChanged: (next) => setState(() => page = next),
                ),
            ],
          ),
        );
      },
    );
  }
}
