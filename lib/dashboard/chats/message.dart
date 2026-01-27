import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zephyron/dashboard/chats/attach.dart';
import 'package:zephyron/dashboard/chats/index.dart';
import 'package:zephyron/dashboard/chats/viewer.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/sheet.dart';
import 'package:zephyron/widgets/stamp.dart';

class MessagePage extends StatefulWidget {
  final String? title;
  final String? id;

  const MessagePage({super.key, this.title, this.id});

  @override
  State<MessagePage> createState() => MessagePageState();
}

class MessagePageState extends State<MessagePage> {
  final TextEditingController input = TextEditingController();
  final ScrollController scroll = ScrollController();
  final FocusNode focus = FocusNode();
  final Set<String> settled = {};
  bool primed = false;
  bool away = false;

  Courier get courier => Courier.instance;
  String get peer => widget.id ?? '';

  @override
  void initState() {
    super.initState();
    courier.focus = peer;
    courier.seen(peer);
    input.addListener(() => setState(() {}));
    scroll.addListener(() {
      final far = scroll.hasClients && scroll.offset > 320;
      if (far != away) setState(() => away = far);
    });
  }

  @override
  void dispose() {
    if (courier.focus == peer) courier.focus = null;
    input.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  void bottom() {
    if (!scroll.hasClients) return;
    scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;

    return ListenableBuilder(
      listenable: Listenable.merge([courier, courier.reach]),
      builder: (context, _) {
        final trustee = courier.roster[peer];
        final name = trustee?.label ?? widget.title ?? 'Chat';
        final thread = courier.threads[peer] ?? const <Message>[];
        final presence = courier.status(peer);
        final online = courier.online(peer);
        final incoming = courier.transfers.values
            .where((item) => item.peer == peer)
            .toList();
        final extra = (presence.composing ? 1 : 0) + incoming.length;
        final ready = input.text.trim().isNotEmpty;
        final availability = trustee?.availability ?? Availability.available;
        final caption = courier.reach.value != Reach.online
            ? 'waiting for Tor…'
            : presence.composing
            ? 'typing…'
            : online && availability != Availability.available
            ? availability.label.toLowerCase()
            : online
            ? presence.latency != null
                  ? 'online · ${presence.latency} ms'
                  : 'online'
            : trustee != null && trustee.mood.isNotEmpty
            ? trustee.mood
            : presence.seen != null && availability != Availability.invisible
            ? 'last seen ${ago(presence.seen!)}'
            : 'end-to-end over Tor';

        if (!primed) {
          settled.addAll(thread.map((item) => item.id));
          primed = true;
        }

        void details() => Navigator.pushNamed(
          context,
          '/dashboard/peers/node',
          arguments: {'id': peer},
        );

        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            scrolledUnderElevation: 0.5,
            titleSpacing: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: scheme.onSurface),
              onPressed: () => Navigator.maybePop(context),
            ),
            title: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: trustee == null ? null : details,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Hero(
                      tag: 'avatar:$peer',
                      child: Portrait(address: peer, size: 36),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              caption,
                              key: ValueKey(caption),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: presence.composing || online
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (trustee != null)
                IconButton(
                  tooltip: 'Profile',
                  icon: Icon(
                    Icons.info_outline,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: details,
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(
            children: [
              if (trustee != null && trustee.stranger)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.mark_email_unread_outlined,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Message request',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'Replying adds them as a trustee',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final sure = await Sheets.confirm(
                            context,
                            title: 'Block this sender?',
                            message:
                                'Nothing from this discovery key will reach you until you unblock it.',
                            action: 'Block',
                          );
                          if (!sure) return;
                          await courier.trust(peer, Trust.blocked);
                          if (context.mounted) Navigator.maybePop(context);
                        },
                        child: const Text('Block'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => courier.trust(peer, Trust.trustee),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    if (thread.isEmpty && extra == 0)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_rounded,
                                size: 36,
                                color: scheme.primary,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Say hi to $name',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Messages, photos and files are signed with your identity key '
                                'and travel straight to their onion service. They wait here '
                                'until your trustee comes online.',
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
                    else
                      ListView.builder(
                        controller: scroll,
                        reverse: true,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: thread.length + extra,
                        itemBuilder: (context, index) {
                          if (presence.composing) {
                            if (index == 0) return const Typing();
                            index -= 1;
                          }
                          if (index < incoming.length) {
                            final transfer = incoming[index];
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 240,
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          transfer.kind == Kind.file
                                              ? Icons.download_rounded
                                              : Icons.image_outlined,
                                          size: 18,
                                          color: scheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Receiving ${switch (transfer.kind) {
                                              Kind.image => 'photo',
                                              Kind.gif => 'GIF',
                                              _ => transfer.name,
                                            }}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${(transfer.progress * 100).round()}%',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: transfer.progress,
                                        minHeight: 4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          index -= incoming.length;

                          final position = thread.length - 1 - index;
                          final message = thread[position];
                          final previous = position > 0
                              ? thread[position - 1]
                              : null;
                          final next = position < thread.length - 1
                              ? thread[position + 1]
                              : null;
                          final newDay =
                              previous == null ||
                              day(previous.time) != day(message.time);
                          bool joined(Message? other) =>
                              other != null &&
                              other.mine == message.mine &&
                              day(other.time) == day(message.time) &&
                              other.time
                                      .difference(message.time)
                                      .inMinutes
                                      .abs() <
                                  3;
                          final above = !newDay && joined(previous);
                          final below = joined(next);
                          final fresh = !settled.contains(message.id);
                          settled.add(message.id);

                          final mine = message.mine;
                          const round = Radius.circular(16);
                          const tight = Radius.circular(4);
                          final radius = BorderRadius.only(
                            topLeft: !mine && above ? tight : round,
                            bottomLeft: !mine && below ? tight : round,
                            topRight: mine && above ? tight : round,
                            bottomRight: mine && below ? tight : round,
                          );
                          final foreground = mine
                              ? scheme.onPrimary
                              : scheme.onSurface;
                          final faded = mine
                              ? scheme.onPrimary.withValues(alpha: 0.65)
                              : scheme.onSurfaceVariant;
                          final decoration = BoxDecoration(
                            borderRadius: radius,
                            color: mine
                                ? scheme.primary
                                : scheme.surfaceContainerHigh,
                          );
                          final footer = Footer(message: message, color: faded);
                          final progress = courier.progress[message.id];
                          final pending =
                              mine &&
                              message.status.index < Status.delivered.index;

                          Widget body;
                          if (message.media) {
                            final limit = (width * 0.68).clamp(160.0, 300.0);
                            body = ClipRRect(
                              borderRadius: radius,
                              child: DecoratedBox(
                                decoration: message.text.isEmpty
                                    ? const BoxDecoration()
                                    : decoration,
                                child: SizedBox(
                                  width: limit,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Frame(
                                        message: message,
                                        author: mine ? 'You' : name,
                                        limit: limit,
                                        overlay: message.text.isEmpty,
                                      ),
                                      if (message.text.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            8,
                                            10,
                                            6,
                                          ),
                                          child: Wrap(
                                            alignment: WrapAlignment.end,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.end,
                                            spacing: 8,
                                            children: [
                                              Text(
                                                message.text,
                                                style: TextStyle(
                                                  color: foreground,
                                                  fontSize: 15.5,
                                                  height: 1.3,
                                                ),
                                              ),
                                              footer,
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          } else if (message.kind == Kind.text) {
                            body = DecoratedBox(
                              decoration: decoration,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  9,
                                  10,
                                  7,
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  crossAxisAlignment: WrapCrossAlignment.end,
                                  spacing: 8,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 4,
                                        bottom: 2,
                                      ),
                                      child: Text(
                                        message.text,
                                        style: TextStyle(
                                          color: foreground,
                                          fontSize: 15.5,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                    footer,
                                  ],
                                ),
                              ),
                            );
                          } else if (message.kind == Kind.file) {
                            final extension = message.name.contains('.')
                                ? message.name.split('.').last.toUpperCase()
                                : 'FILE';
                            body = DecoratedBox(
                              decoration: decoration,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  9,
                                  10,
                                  7,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () =>
                                          Viewer.export(context, message),
                                      child: SizedBox(
                                        width: 230,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 44,
                                                  height: 44,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: foreground
                                                        .withValues(
                                                          alpha: 0.14,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    extension.length > 4
                                                        ? extension.substring(
                                                            0,
                                                            4,
                                                          )
                                                        : extension,
                                                    style: TextStyle(
                                                      color: foreground,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        message.name,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: foreground,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        measure(message.size),
                                                        style: TextStyle(
                                                          color: foreground
                                                              .withValues(
                                                                alpha: 0.7,
                                                              ),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (pending &&
                                                progress != null &&
                                                progress < 1) ...[
                                              const SizedBox(height: 8),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: progress,
                                                  minHeight: 4,
                                                  color: foreground,
                                                  backgroundColor: foreground
                                                      .withValues(alpha: 0.2),
                                                ),
                                              ),
                                            ],
                                            if (message.text.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                message.text,
                                                style: TextStyle(
                                                  color: foreground,
                                                  fontSize: 15,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    footer,
                                  ],
                                ),
                              ),
                            );
                          } else {
                            final address =
                                message.meta['address'] as String? ?? '';
                            final shared =
                                message.meta['name'] as String? ?? '';
                            final known = courier.roster[address];
                            final yourself = address == courier.self?.address;
                            final label = shared.isNotEmpty
                                ? shared
                                : address.length > 10
                                ? address.substring(0, 10)
                                : address;
                            body = DecoratedBox(
                              decoration: decoration,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  9,
                                  10,
                                  7,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 230,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Avatar(
                                                label: label,
                                                size: 44,
                                                image: known?.avatar,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      label,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: foreground,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    Text(
                                                      'Shared trustee',
                                                      style: TextStyle(
                                                        color: foreground
                                                            .withValues(
                                                              alpha: 0.7,
                                                            ),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          SizedBox(
                                            width: double.infinity,
                                            child: TextButton(
                                              style: TextButton.styleFrom(
                                                foregroundColor: foreground,
                                                disabledForegroundColor:
                                                    foreground.withValues(
                                                      alpha: 0.6,
                                                    ),
                                                backgroundColor: foreground
                                                    .withValues(alpha: 0.12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              onPressed: yourself
                                                  ? null
                                                  : () async {
                                                      if (known != null &&
                                                          known.trusted) {
                                                        Navigator.pushNamed(
                                                          context,
                                                          '/dashboard/chats/message',
                                                          arguments: {
                                                            'id': address,
                                                          },
                                                        );
                                                        return;
                                                      }
                                                      await courier.add(
                                                        address,
                                                        shared,
                                                      );
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          behavior:
                                                              SnackBarBehavior
                                                                  .floating,
                                                          content: Text(
                                                            '$label is now a trustee',
                                                          ),
                                                        ),
                                                      );
                                                    },
                                              child: Text(
                                                yourself
                                                    ? 'This is you'
                                                    : known != null &&
                                                          known.trusted
                                                    ? 'Message'
                                                    : 'Add as trustee',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    footer,
                                  ],
                                ),
                              ),
                            );
                          }

                          Widget bubble = Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(top: above ? 2 : 8),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: width * 0.78,
                                ),
                                child: GestureDetector(
                                  onLongPress: () {
                                    if (courier.prefs.haptics) {
                                      HapticFeedback.selectionClick();
                                    }
                                    Sheets.actions(
                                      context,
                                      items: [
                                        if (message.text.isNotEmpty)
                                          SheetAction(
                                            icon: Icons.copy_rounded,
                                            label: 'Copy text',
                                            onTap: () {
                                              Clipboard.setData(
                                                ClipboardData(
                                                  text: message.text,
                                                ),
                                              );
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                  duration: const Duration(
                                                    seconds: 2,
                                                  ),
                                                  content: const Text('Copied'),
                                                ),
                                              );
                                            },
                                          ),
                                        if (message.attachment)
                                          SheetAction(
                                            icon: Icons.ios_share_rounded,
                                            label: 'Share or save',
                                            onTap: () =>
                                                Viewer.export(context, message),
                                          ),
                                        if (pending)
                                          SheetAction(
                                            icon: Icons.refresh_rounded,
                                            label: 'Retry now',
                                            onTap: () => courier.flush(peer),
                                          ),
                                        SheetAction(
                                          icon: Icons.delete_outline_rounded,
                                          label: 'Delete for me',
                                          destructive: true,
                                          onTap: () => courier.erase(message),
                                        ),
                                      ],
                                    );
                                  },
                                  child: body,
                                ),
                              ),
                            ),
                          );

                          if (fresh &&
                              !MediaQuery.disableAnimationsOf(context)) {
                            bubble = TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              child: bubble,
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 14 * (1 - value)),
                                  child: Transform.scale(
                                    scale: 0.94 + 0.06 * value,
                                    alignment: mine
                                        ? Alignment.bottomRight
                                        : Alignment.bottomLeft,
                                    child: child,
                                  ),
                                ),
                              ),
                            );
                          }

                          return Column(
                            key: ValueKey(message.id),
                            children: [
                              if (newDay)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      const Expanded(child: Divider()),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text(
                                          heading(message.time),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ),
                                      const Expanded(child: Divider()),
                                    ],
                                  ),
                                ),
                              bubble,
                            ],
                          );
                        },
                      ),
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: AnimatedScale(
                        scale: away ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        child: FloatingActionButton.small(
                          heroTag: null,
                          elevation: 2,
                          backgroundColor: scheme.surfaceContainerHighest,
                          foregroundColor: scheme.onSurface,
                          onPressed: bottom,
                          child: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  color: scheme.surface,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Attach',
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: scheme.primary,
                        ),
                        onPressed: () => Attach.menu(context, peer),
                      ),
                      Expanded(
                        child: TextField(
                          controller: input,
                          focusNode: focus,
                          minLines: 1,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(color: scheme.onSurface),
                          onChanged: (_) => courier.typing(peer),
                          decoration: InputDecoration(
                            hintText: 'Message…',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(color: scheme.outline),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(color: scheme.outline),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(color: scheme.onSurface),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedScale(
                        scale: ready ? 1 : 0.9,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: IconButton.filled(
                          tooltip: 'Send',
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            disabledBackgroundColor:
                                scheme.surfaceContainerHigh,
                            disabledForegroundColor: scheme.onSurfaceVariant,
                          ),
                          icon: const Icon(Icons.arrow_upward_rounded),
                          onPressed: ready
                              ? () {
                                  if (courier.prefs.haptics) {
                                    HapticFeedback.lightImpact();
                                  }
                                  courier.send(peer, input.text);
                                  input.clear();
                                  bottom();
                                }
                              : null,
                        ),
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
  }
}

class Footer extends StatelessWidget {
  final Message message;
  final Color color;

  const Footer({super.key, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          clock(message.time),
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (message.mine) ...[
          const SizedBox(width: 3),
          Tick(
            status: message.status,
            color: color,
            highlight: const Color(0xFFA6F0FF),
            size: 15,
          ),
        ],
      ],
    );
  }
}

class Frame extends StatefulWidget {
  final Message message;
  final String author;
  final double limit;
  final bool overlay;

  const Frame({
    super.key,
    required this.message,
    required this.author,
    required this.limit,
    this.overlay = false,
  });

  @override
  State<Frame> createState() => FrameState();
}

class FrameState extends State<Frame> {
  late final Future<Uint8List> bytes = Locker.load(widget.message);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;
    final ratio = message.width > 0 && message.height > 0
        ? (message.width / message.height).clamp(0.5, 2.2)
        : 1.0;
    final width = widget.limit;
    final height = (width / ratio).clamp(120.0, 360.0);
    final progress = Courier.instance.progress[message.id];
    final pending =
        message.mine && message.status.index < Status.delivered.index;

    return SizedBox(
      width: width,
      height: height,
      child: FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (data != null)
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      opaque: false,
                      barrierColor: Colors.black,
                      transitionDuration: const Duration(milliseconds: 220),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 180,
                      ),
                      pageBuilder: (_, _, _) => Viewer(
                        message: message,
                        bytes: data,
                        author: widget.author,
                      ),
                      transitionsBuilder: (_, animation, _, child) =>
                          FadeTransition(opacity: animation, child: child),
                    ),
                  ),
                  child: Hero(
                    tag: 'media:${message.id}',
                    child: Image.memory(
                      data,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth:
                          (width * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                    ),
                  ),
                )
              else
                Container(
                  color: scheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: snapshot.hasError
                      ? Icon(
                          Icons.broken_image_outlined,
                          color: scheme.onSurfaceVariant,
                        )
                      : null,
                ),
              if (message.kind == Kind.gif)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'GIF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              if (pending && progress != null && progress < 1)
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              if (widget.overlay)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Footer(message: message, color: Colors.white),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class Typing extends StatefulWidget {
  const Typing({super.key});

  @override
  State<Typing> createState() => TypingState();
}

class TypingState extends State<Typing> with SingleTickerProviderStateMixin {
  late final AnimationController wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedBuilder(
          animation: wave,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final phase = (wave.value - index * 0.18) % 1.0;
                final lift = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 7,
                  height: 7,
                  transform: Matrix4.translationValues(0, -4 * lift, 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.onSurfaceVariant.withValues(
                      alpha: 0.4 + 0.5 * lift,
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
