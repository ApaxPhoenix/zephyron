import 'package:flutter/material.dart';
import 'package:zephyron/theme.dart';
import 'package:flutter/services.dart';
import 'package:zephyron/dashboard/communities/index.dart';
import 'package:zephyron/dashboard/communities/podcast.dart';
import 'package:zephyron/dashboard/communities/voice.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/stage.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/stamp.dart';

class ChannelPage extends StatefulWidget {
  final String? community;
  final String? channel;

  const ChannelPage({super.key, this.community, this.channel});

  @override
  State<ChannelPage> createState() => ChannelPageState();
}

class ChannelPageState extends State<ChannelPage> {
  final TextEditingController draft = TextEditingController();
  final FocusNode focus = FocusNode();
  bool sending = false;

  Mesh get mesh => Mesh.instance;

  @override
  void dispose() {
    draft.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> send(Community community, Room room) async {
    final text = draft.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    draft.clear();
    try {
      await mesh.say(community, room.id, text);
      if (Courier.instance.prefs.haptics) HapticFeedback.lightImpact();
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([mesh, Courier.instance, Stage.instance]),
      builder: (context, _) {
        final community = mesh.communities[widget.community];
        final rooms = community == null
            ? const <Room>[]
            : mesh
                  .rooms(community.id)
                  .where((item) => item.id == widget.channel);
        if (community == null || rooms.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(
                'This channel is gone.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }
        final room = rooms.first;
        if (room.kind == Space.podcast) {
          return PodcastPage(community: community, room: room);
        }
        if (room.kind == Space.voice) {
          return VoicePage(community: community, room: room);
        }
        final posts = mesh.messages(community.id, room.id);

        Widget entry(int index) {
          final post = posts[posts.length - 1 - index];
          final before = posts.length - 2 - index >= 0
              ? posts[posts.length - 2 - index]
              : null;
          final grouped =
              before != null &&
              before.author == post.author &&
              day(before.time) == day(post.time) &&
              post.time.difference(before.time).inMinutes < 5;
          final newDay = before == null || day(before.time) != day(post.time);
          final yourself = post.author == Courier.instance.self?.address;
          final trustee = Courier.instance.roster[post.author];
          final member = mesh
              .members(community.id)
              .where((item) => item.address == post.author);
          final name = mesh.called(community.id, post.author);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (newDay)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
                  child: Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          heading(post.time),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(top: grouped ? 2 : 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      child: grouped
                          ? null
                          : trustee != null
                          ? Portrait(address: post.author, size: 40)
                          : Avatar(
                              label: name,
                              size: 40,
                              image: yourself
                                  ? Courier.instance.me.avatar
                                  : member.isEmpty
                                  ? null
                                  : member.first.avatar,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!grouped)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: yourself
                                                ? scheme.primary
                                                : null,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    clock(post.time),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          SelectableText(
                            post.text,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            title: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pushNamed(
                context,
                '/dashboard/communities/community',
                arguments: {'id': community.id},
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    if (community.group)
                      Crest(
                        label: community.name,
                        image: community.icon,
                        size: 36,
                      )
                    else
                      Mark(kind: room.kind, color: scheme.onSurface),
                    SizedBox(width: community.group ? 12 : 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            community.group ? community.name : room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            community.group
                                ? '${mesh.members(community.id).length} members'
                                : community.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (community.group)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    tooltip: 'Group Call',
                    icon: Icon(
                      Icons.call_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => VoicePage.show(context, community),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              if (community.group)
                ...() {
                  final stage = Stage.instance;
                  final self = Courier.instance.self?.address;
                  final count = stage
                      .seated(community.general)
                      .keys
                      .where((address) => address != self)
                      .length;
                  if (count == 0 || stage.room == community.general) {
                    return const <Widget>[];
                  }
                  return [
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E9E57).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.call, color: Color(0xFF2E9E57)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Call in progress · $count ${count == 1 ? 'person' : 'people'}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: () => VoicePage.show(context, community),
                            child: const Text('Join'),
                          ),
                        ],
                      ),
                    ),
                  ];
                }(),
              Expanded(
                child: posts.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  shape: BoxShape.circle,
                                ),
                                child: Mark(
                                  kind: room.kind,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                community.group
                                    ? 'Welcome to ${community.name}'
                                    : 'Welcome to #${room.name}',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                community.group
                                    ? 'This is the start of the group. Only the people in it can read what is said here.'
                                    : 'This is the start of the channel. Messages are encrypted with the community key and passed between members over Tor.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        itemCount: posts.length,
                        itemBuilder: (context, index) => entry(index),
                      ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: draft,
                            focusNode: focus,
                            minLines: 1,
                            maxLines: 6,
                            maxLength: Mesh.limit,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: community.group
                                  ? 'Message ${community.name}'
                                  : 'Message #${room.name}',
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(color: scheme.outline),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(color: scheme.outline),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(
                                  color: scheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => send(community, room),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Send',
                          style: Pallete.solid(Theme.of(context).colorScheme),
                          onPressed: draft.text.trim().isEmpty || sending
                              ? null
                              : () => send(community, room),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
