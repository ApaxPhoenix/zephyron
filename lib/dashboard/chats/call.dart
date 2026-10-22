import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/communities/voice.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/services/stage.dart';
import 'package:zephyron/widgets/avatar.dart';

/// A direct call ringing out, ringing in, under way, or just ended. Group
/// calls ring here too, and open the group's call once answered. Leaving
/// the page hangs up.
class CallPage extends StatefulWidget {
  /// The trustee to ring when the page opens; null to show the call that is
  /// already ringing or under way.
  final String? peer;

  const CallPage({super.key, this.peer});

  @override
  State<CallPage> createState() => CallPageState();
}

class CallPageState extends State<CallPage> {
  Timer? ticker;
  Timer? closing;
  bool placing = false;
  bool answering = false;

  /// The ring this page showed, so a ring that stops can read as missed.
  Ring? heard;

  Stage get stage => Stage.instance;
  Courier get courier => Courier.instance;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final peer = widget.peer;
    if (peer == null) return;
    placing = true;
    stage.ended = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final placed = stage.dial(peer);
      if (mounted) setState(() => placing = false);
      if (!await placed && stage.ended == null) stage.ended = 'unreachable';
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    closing?.cancel();
    if (stage.direct) unawaited(stage.leave());
    super.dispose();
  }

  Future<void> accept() async {
    final call = stage.ringing;
    if (call == null) return;
    setState(() => answering = true);
    final navigator = Navigator.of(context);
    final answered = await stage.pickUp();
    if (!mounted) return;
    if (call.direct) {
      setState(() => answering = false);
      return;
    }
    final group = Mesh.instance.communities[call.community];
    if (!answered || group == null) {
      navigator.pop();
      return;
    }
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VoicePage(
          community: group,
          room: VoicePage.lobby(group),
          call: true,
        ),
      ),
    );
  }

  Future<void> decline() async {
    final navigator = Navigator.of(context);
    await stage.decline();
    if (mounted) navigator.pop();
  }

  String reason() => switch (stage.ended) {
    _ when heard != null => 'Missed call',
    'busy' => 'Busy',
    'declined' => 'Declined',
    'unanswered' => 'No answer',
    'unreachable' => 'Could not reach them',
    'dropped' => 'Call dropped',
    _ => 'Call ended',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([stage, courier]),
      builder: (context, _) {
        final ring = stage.direct ? null : stage.ringing;
        if (ring != null) heard = ring;
        final live = stage.direct;
        if (live) heard = null;
        final over = !live && ring == null && !placing;
        if (over) {
          closing ??= Timer(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).maybePop();
          });
        } else {
          closing?.cancel();
          closing = null;
        }

        final group = ring == null || ring.direct
            ? null
            : Mesh.instance.communities[ring.community];
        final who = stage.peer ?? ring?.from ?? widget.peer ?? heard?.from;
        final name = group != null
            ? group.name
            : who == null
            ? 'Call'
            : courier.roster[who]?.label ?? who.substring(0, 10);
        final connected = stage.connected;
        final status = live
            ? connected == null
                  ? stage.outgoing
                        ? 'Calling…'
                        : 'Connecting…'
                  : length(DateTime.now().difference(connected))
            : ring != null
            ? group != null
                  ? '${Mesh.instance.called(group.id, ring.from)} started a call'
                  : 'Incoming voice call'
            : placing
            ? 'Calling…'
            : reason();

        Widget round({
          required IconData icon,
          required String label,
          required Color background,
          required Color foreground,
          required VoidCallback? onPressed,
        }) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filled(
                iconSize: 30,
                tooltip: label,
                style: IconButton.styleFrom(
                  minimumSize: const Size(72, 72),
                  backgroundColor: background,
                  foregroundColor: foreground,
                ),
                onPressed: onPressed,
                icon: Icon(icon),
              ),
              const SizedBox(height: 8),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          );
        }

        final hangUp = round(
          icon: Icons.call_end,
          label: 'Hang Up',
          background: scheme.error,
          foreground: scheme.onError,
          onPressed: () => stage.leave(),
        );

        return Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              child: Column(
                children: [
                  const Spacer(),
                  if (group != null)
                    Crest(label: group.name, image: group.icon, size: 120)
                  else if (who != null)
                    Portrait(address: who, size: 120, presence: false),
                  const SizedBox(height: 24),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: over ? scheme.error : scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'End-to-end encrypted, peer to peer over Tor',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(flex: 2),
                  if (live)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        round(
                          icon: stage.muted ? Icons.mic_off : Icons.mic_none,
                          label: stage.muted ? 'Unmute' : 'Mute',
                          background: stage.muted
                              ? scheme.error.withValues(alpha: 0.14)
                              : scheme.surfaceContainerHighest,
                          foreground: stage.muted
                              ? scheme.error
                              : scheme.onSurface,
                          onPressed: () => stage.mute(!stage.muted),
                        ),
                        hangUp,
                      ],
                    )
                  else if (ring != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        round(
                          icon: Icons.call_end,
                          label: 'Decline',
                          background: scheme.error,
                          foreground: scheme.onError,
                          onPressed: answering ? null : decline,
                        ),
                        round(
                          icon: Icons.call,
                          label: 'Accept',
                          background: const Color(0xFF2E9E57),
                          foreground: Colors.white,
                          onPressed: answering ? null : accept,
                        ),
                      ],
                    )
                  else if (placing)
                    hangUp
                  else
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Close'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
