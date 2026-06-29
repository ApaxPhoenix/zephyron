import 'package:flutter/material.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/section.dart';

/// Starts a private group chat with chosen trustees.
class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => GroupPageState();
}

class GroupPageState extends State<GroupPage> {
  final TextEditingController name = TextEditingController();
  final TextEditingController search = TextEditingController();
  final Set<String> chosen = {};
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (name.text.trim().isEmpty || chosen.isEmpty) return;
    setState(() => busy = true);
    final navigator = Navigator.of(context);
    try {
      final group = await Mesh.instance.create(name: name.text, group: true);
      for (final peer in chosen) {
        await Mesh.instance.invite(group, peer);
      }
      navigator.pushReplacementNamed(
        '/dashboard/communities/channel',
        arguments: {'community': group.id, 'channel': group.general},
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = search.text.trim().toLowerCase();
    final trustees =
        Courier.instance.roster.values
            .where((item) => item.trusted)
            .where(
              (item) =>
                  query.isEmpty || item.label.toLowerCase().contains(query),
            )
            .toList()
          ..sort((alpha, beta) => alpha.label.compareTo(beta.label));
    final ready = name.text.trim().isNotEmpty && chosen.isNotEmpty && !busy;

    return Scaffold(
      appBar: AppBar(title: const Text('New Group')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              Crest(label: name.text.isEmpty ? '?' : name.text, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: Community.names,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Group name',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A private chat for the people you pick. It never shows up in discovery, and anyone in it can invite others or vote someone out.',
            style: theme.textTheme.bodySmall,
          ),
          Heading('Add Trustees', count: chosen.length),
          TextField(
            controller: search,
            decoration: const InputDecoration(
              hintText: 'Search trustees…',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (trustees.isEmpty)
            const Vacant(
              icon: Icons.group_add_outlined,
              text: 'Add trustees first, then you can put them in a group.',
            )
          else
            Group(
              indent: 76,
              children: [
                for (final trustee in trustees)
                  CheckboxListTile(
                    value: chosen.contains(trustee.address),
                    onChanged: (on) => setState(() {
                      if (on == true) {
                        chosen.add(trustee.address);
                      } else {
                        chosen.remove(trustee.address);
                      }
                    }),
                    secondary: Portrait(address: trustee.address, size: 40),
                    title: Text(trustee.label),
                    controlAffinity: ListTileControlAffinity.trailing,
                  ),
              ],
            ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: ready ? create : null,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    chosen.isEmpty
                        ? 'Create Group'
                        : 'Create Group with ${chosen.length}',
                  ),
          ),
          if (chosen.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Each person gets an end-to-end encrypted invitation in your chat with them.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
