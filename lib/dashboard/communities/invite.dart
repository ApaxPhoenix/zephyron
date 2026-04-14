import 'package:flutter/material.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/widgets/avatar.dart';

/// A community invitation shown inside a chat.
class Invitation extends StatefulWidget {
  final Message message;
  final Color foreground;
  final BoxDecoration decoration;
  final Widget footer;

  const Invitation({
    super.key,
    required this.message,
    required this.foreground,
    required this.decoration,
    required this.footer,
  });

  @override
  State<Invitation> createState() => InvitationState();
}

class InvitationState extends State<Invitation> {
  bool busy = false;

  Future<void> join() async {
    setState(() => busy = true);
    final navigator = Navigator.of(context);
    try {
      final community = await Mesh.instance.join(widget.message.meta);
      if (community != null) {
        navigator.pushNamed(
          '/dashboard/communities/community',
          arguments: {'id': community.id},
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = widget.message.meta;
    final name = meta['name'] as String? ?? 'Community';
    final about = meta['about'] as String? ?? '';
    final id = meta['community'] as String? ?? '';
    final faded = widget.foreground.withValues(alpha: 0.7);

    return ListenableBuilder(
      listenable: Mesh.instance,
      builder: (context, _) {
        final joined = Mesh.instance.communities.containsKey(id);
        return DecoratedBox(
          decoration: widget.decoration,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 236,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMMUNITY INVITATION',
                        style: TextStyle(
                          color: faded,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Crest(label: name, size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.foreground,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (about.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          about,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: faded, height: 1.3),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (widget.message.mine)
                        Text(
                          'You invited them',
                          style: TextStyle(color: faded, fontSize: 13),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(40),
                              backgroundColor: joined
                                  ? scheme.surface
                                  : scheme.primary,
                              foregroundColor: joined
                                  ? scheme.primary
                                  : scheme.onPrimary,
                            ),
                            onPressed: busy
                                ? null
                                : joined
                                ? () => Navigator.pushNamed(
                                    context,
                                    '/dashboard/communities/community',
                                    arguments: {'id': id},
                                  )
                                : join,
                            child: Text(joined ? 'Open' : 'Join'),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                widget.footer,
              ],
            ),
          ),
        );
      },
    );
  }
}
