import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/profile.dart';
import 'package:zephyron/main.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/utils/formats.dart';

class DiscussionScreen extends StatefulWidget {
  final String id;
  const DiscussionScreen({super.key, required this.id});

  @override
  State<DiscussionScreen> createState() => DiscussionScreenState();
}

class DiscussionScreenState extends State<DiscussionScreen> {
  final TextEditingController input = TextEditingController();
  final ScrollController scroller = ScrollController();

  String? me;
  String? name;
  String? avatar;
  String? kind;
  String? typer;
  RealtimeSubscription? watcher;

  @override
  void initState() {
    super.initState();
    () async {
      final user = await account.get();
      final convo = await tables.getRow(
        databaseId: '69951d1f002692e40827',
        tableId: '699cc9550038b09d24ae',
        rowId: widget.id,
      );

      if (convo.data['type'] == 'communal') {
        setState(() {
          me = user.$id;
          kind = 'communal';
          name = convo.data['name'] as String? ?? 'Group';
        });
      } else {
        final raw = (convo.data['users'] as List?) ?? [];
        final other = raw
            .map((u) => u is Map ? u['\$id'] as String? : u as String?)
            .whereType<String>()
            .firstWhere((id) => id != user.$id, orElse: () => '');

        if (other.isNotEmpty) {
          final row = await tables.getRow(
            databaseId: '69951d1f002692e40827',
            tableId: '69965edb0019ed7a133f',
            rowId: other,
          );
          setState(() {
            me = user.$id;
            name =
                row.data['name'] as String? ??
                row.data['email'] as String? ??
                other;
            avatar = row.data['avatar'] as String?;
          });
        } else {
          setState(() => me = user.$id);
        }
      }

      watcher = realtime.subscribe([
        'databases.69951d1f002692e40827.collections.699cc9550038b09d24ae.documents.${widget.id}',
      ]);
      watcher!.stream.listen((event) {
        final who = event.payload['typing'] as String?;
        if (!mounted) return;
        setState(() => typer = (who != null && who != me) ? who : null);
      });
    }();
  }

  @override
  void dispose() {
    if (me != null) {
      tables.updateRow(
        databaseId: '69951d1f002692e40827',
        tableId: '699cc9550038b09d24ae',
        rowId: widget.id,
        data: {'typing': null},
      );
    }
    watcher?.close();
    input.dispose();
    scroller.dispose();
    super.dispose();
  }

  void scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroller.hasClients) {
        scroller.animateTo(
          scroller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Stream<List<models.Row>> get messages async* {
    final result = await tables.listRows(
      databaseId: '69951d1f002692e40827',
      tableId: '699cc83500262c5c67d6',
      queries: [
        Query.equal('conversations', widget.id),
        Query.orderAsc('\$createdAt'),
      ],
    );
    yield result.rows;
    scrollBottom();
    yield* realtime
        .subscribe([
          'databases.69951d1f002692e40827.collections.699cc83500262c5c67d6.documents',
        ])
        .stream
        .asyncMap((_) async {
          final updated = await tables.listRows(
            databaseId: '69951d1f002692e40827',
            tableId: '699cc83500262c5c67d6',
            queries: [
              Query.equal('conversations', widget.id),
              Query.orderAsc('\$createdAt'),
            ],
          );
          scrollBottom();
          return updated.rows;
        });
  }

  Future<void> send() async {
    final body = input.text.trim();
    if (body.isEmpty) return;
    input.clear();
    setState(() {});
    tables.updateRow(
      databaseId: '69951d1f002692e40827',
      tableId: '699cc9550038b09d24ae',
      rowId: widget.id,
      data: {'typing': null},
    );
    await tables.createRow(
      databaseId: '69951d1f002692e40827',
      tableId: '699cc83500262c5c67d6',
      rowId: ID.unique(),
      data: {
        'body': body,
        'status': 'sent',
        'conversations': widget.id,
        'users': me,
      },
    );
    scrollBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              ),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Pallete.neutral100,
                backgroundImage: avatar != null && avatar!.isNotEmpty
                    ? NetworkImage(avatar!)
                    : null,
                child: avatar == null || avatar!.isEmpty
                    ? Icon(
                        kind == 'communal' ? Icons.group : Icons.person,
                        size: 18,
                        color: Pallete.neutral500,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: name == null
                  ? Container(
                      height: 14,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Pallete.neutral100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (typer != null)
                          Text(
                            'typing...',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.videocam), onPressed: () {}),
          IconButton(icon: const Icon(Icons.phone), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<models.Row>>(
              stream: messages,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      snapshot.error is AppwriteException
                          ? (snapshot.error as AppwriteException).message ??
                                'Something went wrong'
                          : 'Something went wrong',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Pallete.neutral500,
                      ),
                    ),
                  );
                }

                final msgs = snapshot.data ?? [];
                if (msgs.isEmpty && typer == null) {
                  return Center(
                    child: Text(
                      'No messages yet',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Pallete.neutral500,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: scroller,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: msgs.length + (typer != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (typer != null && index == msgs.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Pallete.neutral100,
                              backgroundImage:
                                  avatar != null && avatar!.isNotEmpty
                                  ? NetworkImage(avatar!)
                                  : null,
                              child: avatar == null || avatar!.isEmpty
                                  ? const Icon(
                                      Icons.person,
                                      size: 14,
                                      color: Pallete.neutral500,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(18),
                                  topRight: Radius.circular(18),
                                  bottomLeft: Radius.circular(4),
                                  bottomRight: Radius.circular(18),
                                ),
                              ),
                              child: const Dots(),
                            ),
                          ],
                        ),
                      );
                    }

                    final msg = msgs[index];
                    final sender = msg.data['users'] is Map
                        ? (msg.data['users'] as Map)['\$id'] as String?
                        : msg.data['users'] as String?;
                    final mine = me != null && sender == me;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: mine
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!mine) ...[
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Pallete.neutral100,
                              backgroundImage:
                                  avatar != null && avatar!.isNotEmpty
                                  ? NetworkImage(avatar!)
                                  : null,
                              child: avatar == null || avatar!.isEmpty
                                  ? const Icon(
                                      Icons.person,
                                      size: 14,
                                      color: Pallete.neutral500,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: mine
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(mine ? 18 : 4),
                                  bottomRight: Radius.circular(mine ? 4 : 18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: mine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.data['body'] ?? '',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: mine
                                          ? theme.colorScheme.onPrimary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        time(DateTime.parse(msg.$createdAt)),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: mine
                                                  ? theme.colorScheme.onPrimary
                                                        .withValues(alpha: 0.7)
                                                  : theme.colorScheme.onSurface
                                                        .withValues(alpha: 0.5),
                                            ),
                                      ),
                                      if (mine) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          switch (msg.data['status']
                                              as String?) {
                                            'sent' => Icons.check,
                                            'delivered' => Icons.done_all,
                                            'received' => Icons.done_all,
                                            _ => Icons.access_time,
                                          },
                                          size: 14,
                                          color:
                                              msg.data['status'] == 'received'
                                              ? theme.colorScheme.onPrimary
                                              : theme.colorScheme.onPrimary
                                                    .withValues(alpha: 0.7),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.add), onPressed: () {}),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: input,
                        onChanged: (val) {
                          setState(() {});
                          if (me != null) {
                            tables.updateRow(
                              databaseId: '69951d1f002692e40827',
                              tableId: '699cc9550038b09d24ae',
                              rowId: widget.id,
                              data: {
                                'typing': val.trim().isNotEmpty ? me : null,
                              },
                            );
                          }
                        },
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (input.text.trim().isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.send, color: theme.colorScheme.primary),
                      onPressed: send,
                    )
                  else ...[
                    IconButton(
                      icon: const Icon(Icons.attach_file),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.photo_camera),
                      onPressed: () {},
                    ),
                    IconButton(icon: const Icon(Icons.mic), onPressed: () {}),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Dots extends StatefulWidget {
  const Dots({super.key});

  @override
  State<Dots> createState() => DotsState();
}

class DotsState extends State<Dots> with SingleTickerProviderStateMixin {
  late AnimationController animation;

  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.4);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final offset = ((animation.value * 3) - i).clamp(0.0, 1.0);
          final bounce = offset < 0.5 ? offset * 2 : (1 - offset) * 2;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.translate(
              offset: Offset(0, -4 * bounce),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          );
        }),
      ),
    );
  }
}
