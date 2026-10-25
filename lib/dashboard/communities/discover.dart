import 'package:flutter/material.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/listing.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/catalog.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/section.dart';
import 'package:zephyron/widgets/sheet.dart';
import 'package:zephyron/widgets/stamp.dart';

/// Browses the people and communities that chose to be listed, as far as
/// their listings have travelled between trustees' phones.
class DiscoverPage extends StatefulWidget {
  final Shelf shelf;

  const DiscoverPage({super.key, this.shelf = Shelf.community});

  @override
  State<DiscoverPage> createState() => DiscoverPageState();
}

class DiscoverPageState extends State<DiscoverPage>
    with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.shelf == Shelf.person ? 1 : 0,
  );
  final TextEditingController search = TextEditingController();

  Catalog get catalog => Catalog.instance;
  Courier get courier => Courier.instance;
  Mesh get mesh => Mesh.instance;

  @override
  void dispose() {
    tabs.dispose();
    search.dispose();
    super.dispose();
  }

  String title(Listing listing) =>
      listing.name.isNotEmpty ? listing.name : listing.subject.substring(0, 10);

  /// Shows a listing in full, with what can be done about it.
  Future<void> details(Listing listing) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final community = listing.shelf == Shelf.community;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) {
        var busy = false;
        return StatefulBuilder(
          builder: (sheet, refresh) {
            final theme = Theme.of(sheet);
            final scheme = theme.colorScheme;
            final joined = mesh.communities[listing.subject];
            final trustee = courier.roster[listing.author]?.trusted == true;

            Future<void> act() async {
              if (community) {
                if (joined == null) {
                  refresh(() => busy = true);
                  final made = await catalog.join(listing);
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet);
                  if (made == null) return;
                  navigator.pushNamed(
                    '/dashboard/communities/community',
                    arguments: {'id': made.id},
                  );
                } else {
                  Navigator.pop(sheet);
                  navigator.pushNamed(
                    '/dashboard/communities/community',
                    arguments: {'id': joined.id},
                  );
                }
                return;
              }
              if (!trustee) {
                await courier.add(listing.author, listing.name);
                messenger.showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text('${title(listing)} is now a trustee'),
                  ),
                );
              }
              if (!sheet.mounted) return;
              Navigator.pop(sheet);
              navigator.pushNamed(
                '/dashboard/chats/message',
                arguments: {'id': listing.author, 'name': title(listing)},
              );
            }

            final details = community
                ? '${listing.members} ${listing.members == 1 ? 'member' : 'members'} when listed · Founded by ${courier.roster[listing.author]?.label ?? listing.author.substring(0, 10)}'
                : listing.author;
            final note = community
                ? joined != null
                      ? 'You are a member.'
                      : 'Joining takes a few seconds of work on this phone, which keeps bots out. Members will see your name and picture.'
                : trustee
                ? 'Already one of your trustees.'
                : 'Adding them makes them your trustee: they can message you and see your profile, and they get a request to add you back.';
            final action = community
                ? joined != null
                      ? 'Open'
                      : 'Join'
                : trustee
                ? 'Message'
                : 'Add as Trustee';

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Sheets.grabber(sheet),
                    const SizedBox(height: 8),
                    community
                        ? Crest(
                            label: listing.name,
                            image: listing.picture,
                            size: 72,
                          )
                        : Avatar(
                            label: title(listing),
                            image: listing.picture,
                            size: 72,
                          ),
                    const SizedBox(height: 14),
                    Text(
                      title(listing),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (listing.about.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        listing.about,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      details,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFamily: community ? null : 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Listed ${brief(listing.time)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      note,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: busy ? null : act,
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(action),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                      onPressed: busy
                          ? null
                          : () {
                              catalog.hide(listing);
                              Navigator.pop(sheet);
                            },
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: const Text('Hide and Stop Passing Along'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget tile(Listing listing) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final community = listing.shelf == Shelf.community;
    final known = community
        ? mesh.communities.containsKey(listing.subject)
        : courier.roster[listing.author]?.trusted == true;
    return ListTile(
      key: ValueKey(listing.id),
      onTap: () => details(listing),
      leading: community
          ? Crest(label: listing.name, image: listing.picture)
          : Avatar(label: title(listing), image: listing.picture),
      title: Text(title(listing), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        listing.about.isNotEmpty
            ? listing.about
            : community
            ? '${listing.members} ${listing.members == 1 ? 'member' : 'members'}'
            : listing.author.substring(0, 16),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: known
          ? Text(
              community ? 'Joined' : 'Trustee',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
              ),
            )
          : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
    );
  }

  Widget shelf(Shelf which) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = search.text.trim().toLowerCase();
    final all = catalog.browse(which);
    final shown = all
        .where(
          (item) =>
              query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              item.about.toLowerCase().contains(query),
        )
        .toList();
    final people = which == Shelf.person;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        TextField(
          controller: search,
          decoration: InputDecoration(
            hintText: people ? 'Search people…' : 'Search communities…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: search.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: scheme.onSurfaceVariant),
                    onPressed: () => setState(search.clear),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        Heading(
          people ? 'Listed People' : 'Listed Communities',
          count: shown.length,
          description: people
              ? 'People who asked to be found. Their listings reach you through your trustees\' phones.'
              : 'Communities their founders opened to anyone. What is said in them is effectively public.',
        ),
        if (all.isEmpty)
          Vacant(
            icon: people ? Icons.person_search_outlined : Icons.travel_explore,
            text:
                'Nothing listed has reached this phone yet. Listings travel between trustees\' phones, so more turn up as your trustees connect.',
          )
        else if (shown.isEmpty)
          Vacant(
            icon: Icons.search_off,
            text: 'Nothing matches "${search.text}".',
          )
        else
          Group(indent: 76, children: shown.map(tile).toList()),
        const SizedBox(height: 20),
        if (people)
          Group(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.travel_explore),
                title: const Text('List Me Here'),
                subtitle: const Text(
                  'Anyone the listing reaches sees your name, bio, picture and discovery key',
                ),
                value: courier.prefs.listed,
                onChanged: (value) {
                  final next = Preferences.fromJson(courier.prefs.toJson())
                    ..listed = value;
                  courier.configure(next);
                },
              ),
            ],
          )
        else
          Text(
            'Founders can list a community from its page.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        bottom: TabBar(
          controller: tabs,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Communities'),
            Tab(text: 'People'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([catalog, mesh, courier]),
        builder: (context, _) => TabBarView(
          controller: tabs,
          children: [shelf(Shelf.community), shelf(Shelf.person)],
        ),
      ),
    );
  }
}
