import 'package:flutter/material.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/beacon.dart';
import 'package:zephyron/widgets/section.dart';
import 'package:zephyron/widgets/stamp.dart';

class CommunitiesPage extends StatefulWidget {
  const CommunitiesPage({super.key});

  @override
  State<CommunitiesPage> createState() => CommunitiesPageState();
}

class CommunitiesPageState extends State<CommunitiesPage> {
  final TextEditingController search = TextEditingController();

  Mesh get mesh => Mesh.instance;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void create() =>
      Navigator.pushNamed(context, '/dashboard/communities/create');

  void open(Community community) => Navigator.pushNamed(
    context,
    '/dashboard/communities/community',
    arguments: {'id': community.id},
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Communities'),
        actions: [
          const Center(child: Beacon()),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Create Community',
              onPressed: create,
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([mesh, Courier.instance]),
        builder: (context, _) {
          final query = search.text.trim().toLowerCase();
          final all = mesh.ordered();
          final shown = all
              .where(
                (item) =>
                    query.isEmpty ||
                    item.name.toLowerCase().contains(query) ||
                    item.about.toLowerCase().contains(query),
              )
              .toList();
          final pinned = shown.where((item) => item.pinned).toList();
          final rest = shown.where((item) => !item.pinned).toList();

          Widget tile(Community community) {
            final latest = mesh.latest(community.id);
            final count = mesh.members(community.id).length;
            return ListTile(
              key: ValueKey(community.id),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 4,
              ),
              onTap: () => open(community),
              leading: Crest(label: community.name, image: community.icon),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      community.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (community.muted) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                latest != null
                    ? '${mesh.called(community.id, latest.author)}: ${latest.text}'
                    : community.about.isNotEmpty
                    ? community.about
                    : '$count ${count == 1 ? 'member' : 'members'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (latest != null)
                    Text(brief(latest.time), style: theme.textTheme.labelSmall),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text('$count', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ),
            );
          }

          final children = <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: TextField(
                controller: search,
                decoration: InputDecoration(
                  hintText: 'Search communities…',
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
          ];

          if (all.isEmpty) {
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
                        Icons.diversity_3_outlined,
                        size: 48,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No Communities Yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start one for your people, or join from an invitation a trustee sends you. Nobody owns a community; members keep it alive for each other.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: create,
                      icon: const Icon(Icons.add),
                      label: const Text('Create a Community'),
                    ),
                  ],
                ),
              ),
            );
          } else if (shown.isEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No communities match "${search.text}"',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          } else {
            const padding = EdgeInsets.fromLTRB(24, 28, 12, 8);
            if (pinned.isNotEmpty) {
              children
                ..add(Heading('Pinned', count: pinned.length, padding: padding))
                ..addAll(pinned.map(tile));
            }
            if (rest.isNotEmpty) {
              children
                ..add(
                  Heading(
                    pinned.isEmpty ? 'Your Communities' : 'Everything Else',
                    count: rest.length,
                    padding: padding,
                  ),
                )
                ..addAll(rest.map(tile));
            }
            children.add(const SizedBox(height: 24));
          }

          return ListView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            children: children,
          );
        },
      ),
    );
  }
}

/// The mark shown before a channel's name.
class Mark extends StatelessWidget {
  final Space kind;
  final Color? color;

  const Mark({super.key, required this.kind, this.color});

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return switch (kind) {
      Space.text => Text(
        '#',
        style: TextStyle(
          color: tone,
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
      ),
      Space.podcast => Icon(Icons.podcasts, color: tone, size: 22),
      Space.voice => Icon(Icons.volume_up_outlined, color: tone, size: 22),
    };
  }
}
