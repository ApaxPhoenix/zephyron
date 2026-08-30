import 'package:flutter/material.dart';
import 'package:zephyron/enums.dart';
import 'dart:developer' as developer;

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => ChatsPageState();
}

class ChatsPageState extends State<ChatsPage> {
  final TextEditingController search = TextEditingController();
  ChatFilters filter = ChatFilters.all;
  final Set<String> highlighted = {};

  List<Map<String, dynamic>> chats = [
    {
      'id': '1',
      'name': 'Alpha Node',
      'message': 'Encrypted payload confirmed at block 842.',
      'time': '10:42 AM',
      'unread': 2,
      'group': false,
      'pinned': true,
    },
    {
      'id': '2',
      'name': 'Mesh Relay Zero',
      'message': 'Routing circuit established over onion v3.',
      'time': '08:15 AM',
      'unread': 0,
      'group': true,
      'pinned': true,
    },
    {
      'id': '3',
      'name': 'Cipher Suite',
      'message': 'Key exchange complete.',
      'time': 'Yesterday',
      'unread': 5,
      'group': false,
      'pinned': false,
    },
    {
      'id': '4',
      'name': 'Delta Gateway',
      'message': 'Heartbeat packet acknowledged.',
      'time': '2 days ago',
      'unread': 0,
      'group': false,
      'pinned': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    try {
      final results =
          chats
              .where(
                (chat) =>
                    ((chat['name'] as String? ?? '').toLowerCase().contains(
                          search.text.toLowerCase(),
                        ) ||
                        (chat['message'] as String? ?? '')
                            .toLowerCase()
                            .contains(search.text.toLowerCase())) &&
                    switch (filter) {
                      ChatFilters.unread => (chat['unread'] as int? ?? 0) > 0,
                      ChatFilters.groups => chat['group'] == true,
                      ChatFilters.pinned => chat['pinned'] == true,
                      _ => true,
                    },
              )
              .toList()
            ..sort(
              (alpha, beta) => (alpha['pinned'] == beta['pinned'])
                  ? 0
                  : (alpha['pinned'] == true ? -1 : 1),
            );

      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 16.0,
          title: Text(
            'Chats',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.qr_code_scanner_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () {},
              tooltip: 'Scan Node QR',
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: IconButton(
                icon: Icon(
                  Icons.add_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () {},
                tooltip: 'New Conversation',
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: search,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Search contacts or onion ID...',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  suffixIcon: search.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () => setState(() => search.clear()),
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: Row(
                children: ChatFilters.values.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(item.label),
                      selected: filter == item,
                      selectedColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLow,
                      labelStyle: TextStyle(
                        color: filter == item
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: filter == item
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      side: BorderSide.none,
                      onSelected: (_) => setState(() => filter = item),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: highlighted.isNotEmpty
                    ? Row(
                        key: const ValueKey('selection_header'),
                        children: [
                          ActionChip(
                            avatar: Icon(
                              highlighted.length == results.length &&
                                      results.isNotEmpty
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            label: Text(
                              highlighted.length == results.length
                                  ? 'Unhighlight All'
                                  : 'Highlight All',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            shape: const StadiumBorder(),
                            side: BorderSide.none,
                            onPressed: () {
                              setState(() {
                                if (highlighted.length == results.length) {
                                  highlighted.clear();
                                } else {
                                  highlighted.addAll(
                                    results.map((c) => c['id'] as String),
                                  );
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${highlighted.length} Highlighted',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () async {
                              final confirmed = await showModalBottomSheet<bool>(
                                context: context,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(24),
                                  ),
                                ),
                                builder: (ctx) => Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    12,
                                    24,
                                    24,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        highlighted.length > 1
                                            ? 'Delete ${highlighted.length} Chats?'
                                            : 'Delete Chat?',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        highlighted.length > 1
                                            ? 'Are you sure you want to delete these ${highlighted.length} chats?'
                                            : 'Are you sure you want to delete this chat?',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: Text(
                                                'Cancel',
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                                foregroundColor: Theme.of(
                                                  context,
                                                ).colorScheme.onError,
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Delete'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              if (confirmed == true) {
                                setState(() {
                                  chats.removeWhere(
                                    (chat) => highlighted.contains(chat['id']),
                                  );
                                  highlighted.clear();
                                });
                              }
                            },
                            tooltip: 'Delete Highlighted',
                          ),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('empty_header')),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.mark_chat_read_outlined,
                                size: 48,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No Conversations Found',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Connect with peers by scanning a QR code or entering an encrypted node address.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimary,
                              ),
                              onPressed: () {},
                              icon: const Icon(Icons.add_outlined),
                              label: const Text('Start New Chat'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        indent: highlighted.isNotEmpty ? 104 : 72,
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withAlpha(50),
                      ),
                      itemBuilder: (context, index) {
                        final chat = results[index];
                        final String id = chat['id'] as String;

                        return Dismissible(
                          key: Key(id),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (direction) async {
                            return await showModalBottomSheet<bool>(
                              context: context,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                              ),
                              builder: (ctx) => Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  12,
                                  24,
                                  24,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Delete Chat?',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Are you sure you want to delete this chat?',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: Text(
                                              'Cancel',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                              foregroundColor: Theme.of(
                                                context,
                                              ).colorScheme.onError,
                                            ),
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Delete'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          onDismissed: (_) {
                            setState(() {
                              chats.removeWhere((c) => c['id'] == id);
                              highlighted.remove(id);
                            });
                          },
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: Icon(
                              Icons.delete_outline,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            color: highlighted.contains(id)
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer.withAlpha(60)
                                : Theme.of(context).colorScheme.surface,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 2.0,
                              ),
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.fastOutSlowIn,
                                    child: highlighted.isNotEmpty
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8.0,
                                            ),
                                            child: RadioGroup<bool>(
                                              groupValue: highlighted.contains(
                                                id,
                                              ),
                                              onChanged: (_) {
                                                setState(() {
                                                  if (highlighted.contains(
                                                    id,
                                                  )) {
                                                    highlighted.remove(id);
                                                  } else {
                                                    highlighted.add(id);
                                                  }
                                                });
                                              },
                                              child: Radio<bool>(
                                                value: true,
                                                activeColor: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                  Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor:
                                            highlighted.contains(id)
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                        child: Text(
                                          (chat['name'] as String)[0],
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: highlighted.contains(id)
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.onPrimary
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      if (chat['group'] == true)
                                        Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.group,
                                            size: 12,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      chat['name'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        fontWeight: (chat['unread'] as int) > 0
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    chat['time'] as String,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: (chat['unread'] as int) > 0
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                          fontWeight:
                                              (chat['unread'] as int) > 0
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                  ),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      chat['message'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  if (chat['pinned'] == true) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.push_pin,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                  if ((chat['unread'] as int) > 0) ...[
                                    const SizedBox(width: 6),
                                    Badge(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      label: Text(
                                        chat['unread'].toString(),
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              onLongPress: () {
                                setState(() {
                                  if (highlighted.contains(id)) {
                                    highlighted.remove(id);
                                  } else {
                                    highlighted.add(id);
                                  }
                                });
                              },
                              onTap: () {
                                if (highlighted.isNotEmpty) {
                                  setState(() {
                                    if (highlighted.contains(id)) {
                                      highlighted.remove(id);
                                    } else {
                                      highlighted.add(id);
                                    }
                                  });
                                } else {
                                  Navigator.pushNamed(
                                    context,
                                    '/dashboard/chats/message',
                                    arguments: chat,
                                  );
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    } catch (error) {
      developer.log(
        'Failed to render chats view layout: $error',
        name: 'ChatsPage.build',
        error: error,
        stackTrace: StackTrace.current,
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      search.dispose();
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to dispose text controller resources: $error',
        name: 'ChatsPage.dispose',
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }
}
