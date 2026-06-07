import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/compose.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/beacon.dart';
import 'package:zephyron/widgets/sheet.dart';
import 'package:zephyron/widgets/stamp.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => ChatsPageState();
}

class ChatsPageState extends State<ChatsPage> {
  final TextEditingController search = TextEditingController();
  final Set<String> shown = {};
  ChatFilters filter = ChatFilters.all;

  Courier get courier => Courier.instance;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> compose() async {
    final contact = await Compose.show(context);
    if (contact == null || !mounted) return;
    Navigator.pushNamed(
      context,
      '/dashboard/chats/message',
      arguments: {'id': contact.address},
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Chats'),
        actions: [
          const Center(child: Beacon()),
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
        listenable: courier,
        builder: (context, _) {
          final query = search.text.trim().toLowerCase();
          final list =
              courier.roster.values.where((contact) {
                if (contact.blocked) return false;
                if (contact.archived != (filter == ChatFilters.archived)) {
                  return false;
                }
                if (filter == ChatFilters.unread &&
                    courier.unread(contact.address) == 0) {
                  return false;
                }
                if (filter == ChatFilters.pinned && !contact.pinned) {
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

          Widget content;
          if (courier.roster.isEmpty) {
            content = Center(
              key: const ValueKey('welcome'),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32.0),
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
          } else if (list.isEmpty) {
            content = Center(
              key: ValueKey('empty:${filter.name}'),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
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
            content = ListView.separated(
              key: ValueKey('list:${filter.name}'),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: list.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                indent: 80,
                color: scheme.outlineVariant.withAlpha(50),
              ),
              itemBuilder: (context, index) {
                final contact = list[index];
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
                      contact.pinned ? Icons.push_pin_outlined : Icons.push_pin,
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
                      horizontal: 16.0,
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
                                  style: Theme.of(context).textTheme.labelSmall
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
                                ScaleTransition(scale: animation, child: child),
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
                        SheetAction(
                          icon: contact.pinned
                              ? Icons.push_pin_outlined
                              : Icons.push_pin,
                          label: contact.pinned ? 'Unpin' : 'Pin to Top',
                          onTap: () =>
                              courier.amend(contact..pinned = !contact.pinned),
                        ),
                        SheetAction(
                          icon: contact.archived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          label: contact.archived ? 'Unarchive' : 'Archive',
                          onTap: () => courier.amend(
                            contact..archived = !contact.archived,
                          ),
                        ),
                        SheetAction(
                          icon: Icons.info_outline,
                          label: 'View Profile',
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/dashboard/peers/node',
                            arguments: {'id': contact.address},
                          ),
                        ),
                        SheetAction(
                          icon: Icons.block,
                          label: 'Block',
                          destructive: true,
                          onTap: () async {
                            final sure = await Sheets.confirm(
                              context,
                              title: 'Block ${contact.label}?',
                              message:
                                  'Everything from this discovery key is dropped until you unblock it in Trustees.',
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
                        SheetAction(
                          icon: Icons.cleaning_services_outlined,
                          label: 'Clear History',
                          destructive: true,
                          onTap: () async {
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
                        SheetAction(
                          icon: Icons.delete_outline,
                          label: 'Delete Chat',
                          destructive: true,
                          onTap: () async {
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
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (courier.roster.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    children: [
                      for (final item in [
                        ChatFilters.all,
                        ChatFilters.unread,
                        ChatFilters.pinned,
                        ChatFilters.archived,
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
