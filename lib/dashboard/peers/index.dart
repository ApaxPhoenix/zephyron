import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:zephyron/theme.dart';

class PeersPage extends StatefulWidget {
  const PeersPage({super.key});

  @override
  State<PeersPage> createState() => PeersPageState();
}

class PeersPageState extends State<PeersPage> {
  final TextEditingController search = TextEditingController();
  final Set<String> highlighted = {};

  List<Map<String, dynamic>> peers = [
    {
      'id': 'peer_01',
      'name': 'Alpha Node',
      'address': '192.168.1.10',
      'latency': '24ms',
      'online': true,
      'pinned': true,
      'pending': false,
    },
    {
      'id': null,
      'name': 'Beta Relay',
      'address': '10.0.0.45',
      'latency': '120ms',
      'online': false,
      'pinned': false,
      'pending': true,
    },
    {
      'id': 'peer_03',
      'name': 'Gamma Gateway',
      'address': '172.16.0.2',
      'latency': '45ms',
      'online': true,
      'pinned': false,
      'pending': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    try {
      final results = peers
          .where(
            (peer) =>
        (peer['name']?.toString() ?? '').toLowerCase().contains(
          search.text.toLowerCase(),
        ) ||
            (peer['address']?.toString() ?? '').toLowerCase().contains(
              search.text.toLowerCase(),
            ),
      )
          .toList();

      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 16.0,
          title: Text(
            'Peer Nodes',
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
              tooltip: 'Scan Peer QR',
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: IconButton(
                icon: Icon(
                  Icons.person_add_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () {},
                tooltip: 'Add Peer Node',
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
                  hintText: 'Search peer name or address...',
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
                              results.map(
                                    (peer) =>
                                peer['id']?.toString() ??
                                    peer['address']?.toString() ??
                                    '',
                              ),
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
                                      ? 'Remove ${highlighted.length} Peers?'
                                      : 'Remove Peer?',
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
                                      ? 'Are you sure you want to remove these ${highlighted.length} peers?'
                                      : 'Are you sure you want to remove this peer node?',
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
                                        child: const Text('Remove'),
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
                            peers.removeWhere(
                                  (peer) => highlighted.contains(
                                peer['id']?.toString() ??
                                    peer['address']?.toString() ??
                                    '',
                              ),
                            );
                            highlighted.clear();
                          });
                        }
                      },
                      tooltip: 'Remove Highlighted',
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
                          Icons.hub_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No Peer Nodes Found',
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
                        'Scan a node QR code or manually specify a host address to establish peer connection.',
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
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Add Peer Node'),
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
                  final peer = results[index];
                  final String id =
                      peer['id']?.toString() ??
                          peer['address']?.toString() ??
                          index.toString();

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
                                'Remove Peer?',
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
                                'Are you sure you want to remove this peer node?',
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
                                      child: const Text('Remove'),
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
                        peers.removeWhere(
                              (peer) =>
                          (peer['id']?.toString() ??
                              peer['address']?.toString() ??
                              '') ==
                              id,
                        );
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
                                    (peer['name']?.toString() ?? 'U')
                                        .isNotEmpty
                                        ? (peer['name']?.toString() ??
                                        'U')[0]
                                        .toUpperCase()
                                        : '?',
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
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: peer['pending'] == true
                                        ? Theme.of(
                                      context,
                                    ).colorScheme.tertiary
                                        : (peer['online'] == true
                                        ? Pallete.success500
                                        : Theme.of(
                                      context,
                                    ).colorScheme.outline),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface,
                                      width: 2,
                                    ),
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
                                peer['name']?.toString() ??
                                    'Unknown Peer',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: peer['pending'] == true
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Text(
                              peer['latency']?.toString() ?? 'Offline',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                color: peer['online'] == true
                                    ? Theme.of(
                                  context,
                                ).colorScheme.primary
                                    : Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: peer['online'] == true
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
                                peer['address']?.toString() ??
                                    'No address',
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
                            if (peer['pinned'] == true) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.push_pin,
                                size: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ],
                            if (peer['pending'] == true) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Pending',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onTertiaryContainer,
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
                              '/dashboard/peers/node',
                              arguments: {
                                'id': peer['id'],
                                'name': peer['name'],
                                'address': peer['address'],
                              },
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
        'Failed to render peers view layout: $error',
        name: 'PeersPage.build',
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
        name: 'PeersPage.dispose',
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }
}