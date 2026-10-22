import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/communities/index.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/stage.dart';
import 'package:zephyron/widgets/avatar.dart';

/// A live voice room, or a group's call. Leaving the page leaves it.
class VoicePage extends StatefulWidget {
  final Community community;
  final Room room;

  /// A group's call, which starts as soon as the page opens.
  final bool call;

  const VoicePage({
    super.key,
    required this.community,
    required this.room,
    this.call = false,
  });

  /// The room a group's call happens in.
  static Room lobby(Community group) => Room(
    id: group.general,
    community: group.id,
    name: group.name,
    kind: Space.voice,
    author: group.founder,
    created: group.created,
  );

  /// Opens [group]'s call, starting it if nobody is on it yet.
  static Future<void> show(BuildContext context, Community group) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              VoicePage(community: group, room: lobby(group), call: true),
        ),
      );

  @override
  State<VoicePage> createState() => VoicePageState();
}

class VoicePageState extends State<VoicePage> {
  bool joining = false;

  Stage get stage => Stage.instance;

  bool get here => stage.room == widget.room.id;

  @override
  void initState() {
    super.initState();
    if (widget.call && !here) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) join();
      });
    }
  }

  @override
  void dispose() {
    if (here) stage.leave();
    super.dispose();
  }

  Future<void> join() async {
    setState(() => joining = true);
    try {
      final seated = await stage.join(widget.community, widget.room.id);
      if (!seated && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This room is full. Voice rooms hold six people so Tor can keep up.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mesh = Mesh.instance;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            if (widget.call)
              Crest(
                label: widget.community.name,
                image: widget.community.icon,
                size: 36,
              )
            else
              Mark(kind: Space.voice, color: scheme.onSurface),
            SizedBox(width: widget.call ? 12 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.call ? 'Group call' : widget.community.name,
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
      body: ListenableBuilder(
        listenable: Listenable.merge([stage, Courier.instance]),
        builder: (context, _) {
          final self = Courier.instance.self?.address;
          final seats = stage.seated(widget.room.id).entries.toList()
            ..sort((alpha, beta) {
              if (alpha.key == self) return -1;
              if (beta.key == self) return 1;
              return alpha.value.seen.compareTo(beta.value.seen);
            });

          Widget tile(MapEntry<String, Seat> entry) {
            final address = entry.key;
            final seat = entry.value;
            final talking = !seat.muted && seat.level > 0.12;
            final name = mesh.called(widget.community.id, address);
            final trustee = Courier.instance.roster[address];
            final member = mesh
                .members(widget.community.id)
                .where((item) => item.address == address);
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: talking
                            ? const Color(0xFF34C759)
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: trustee != null
                        ? Portrait(address: address, size: 64, presence: false)
                        : Avatar(
                            label: name,
                            size: 64,
                            image: address == self
                                ? Courier.instance.me.avatar
                                : member.isEmpty
                                ? null
                                : member.first.avatar,
                          ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (seat.muted) ...[
                          Icon(Icons.mic_off, size: 14, color: scheme.error),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            address == self ? '$name (you)' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.science_outlined, color: scheme.tertiary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.call
                              ? 'Experimental. Voices travel peer to peer over Tor, encrypted with the group key, so expect about a second of delay.'
                              : 'Experimental. Voices travel peer to peer over Tor, encrypted with the community key, so expect about a second of delay.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: seats.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.headset_mic_outlined,
                                  size: 32,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nobody Is Talking',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Join, and members who come in will hear you.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : GridView.count(
                        padding: const EdgeInsets.all(20),
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.15,
                        children: seats.map(tile).toList(),
                      ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    child: here
                        ? Row(
                            children: [
                              IconButton.filledTonal(
                                iconSize: 26,
                                tooltip: stage.muted ? 'Unmute' : 'Mute',
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(56, 56),
                                  backgroundColor: stage.muted
                                      ? scheme.error.withValues(alpha: 0.12)
                                      : null,
                                ),
                                onPressed: () => stage.mute(!stage.muted),
                                icon: Icon(
                                  stage.muted ? Icons.mic_off : Icons.mic_none,
                                  color: stage.muted ? scheme.error : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(56),
                                    backgroundColor: scheme.error,
                                    foregroundColor: scheme.onError,
                                  ),
                                  onPressed: stage.leave,
                                  icon: const Icon(Icons.call_end),
                                  label: Text(
                                    widget.call ? 'Hang Up' : 'Leave Room',
                                  ),
                                ),
                              ),
                            ],
                          )
                        : FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              backgroundColor: const Color(0xFF2E9E57),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: joining ? null : join,
                            icon: const Icon(Icons.headset_mic),
                            label: Text(
                              widget.call
                                  ? seats.isEmpty
                                        ? 'Start Call'
                                        : 'Join Call'
                                  : seats.isEmpty
                                  ? 'Join Voice'
                                  : 'Join ${seats.length} ${seats.length == 1 ? 'Person' : 'People'}',
                            ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
