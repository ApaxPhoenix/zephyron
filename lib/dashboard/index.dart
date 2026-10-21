import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/index.dart';
import 'package:zephyron/dashboard/communities/index.dart';
import 'package:zephyron/dashboard/peers/index.dart';
import 'package:zephyron/dashboard/relays/index.dart';
import 'package:zephyron/dashboard/vault/index.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/sql/session.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'dart:developer' as developer;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  Menu screen = Menu.chats;
  StreamSubscription<void>? expiry;
  StreamSubscription<Message>? arrivals;

  @override
  void initState() {
    super.initState();

    final identity = Session.user;
    if (identity == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => relock());
      return;
    }

    try {
      Courier.instance.start(identity);
      expiry = Session.expired.stream.listen((_) => relock());
      arrivals = Courier.instance.arrivals.stream.listen((message) {
        final courier = Courier.instance;
        if (!mounted || !courier.prefs.banners) return;
        if (courier.me.availability == Availability.busy) return;
        final trustee = courier.roster[message.peer];
        final name = trustee?.label ?? 'New message';
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Row(
              children: [
                Portrait(address: message.peer, size: 32, presence: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        message.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => Navigator.of(context).pushNamed(
                '/dashboard/chats/message',
                arguments: {'id': message.peer},
              ),
            ),
          ),
        );
      });
    } catch (error) {
      developer.log(
        'Failed to start the messaging courier for the unlocked identity',
        name: 'DashboardScreen.setup',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  Future<void> relock() async {
    await Courier.instance.stop();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const pages = [
      ChatsPage(),
      CommunitiesPage(),
      PeersPage(),
      RelaysPage(),
      VaultPage(),
    ];
    final calm = MediaQuery.disableAnimationsOf(context);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (Session.active) Session.touch();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        // Pages scroll underneath the frosted navigation bar.
        extendBody: true,
        body: Stack(
          children: [
            for (final item in Menu.values)
              AnimatedOpacity(
                opacity: item == screen ? 1.0 : 0.0,
                duration: Duration(milliseconds: calm ? 0 : 180),
                curve: Curves.easeOut,
                child: AnimatedSlide(
                  offset: item == screen
                      ? Offset.zero
                      : const Offset(0.0, 0.015),
                  duration: Duration(milliseconds: calm ? 0 : 220),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: item != screen,
                    child: TickerMode(
                      enabled: item == screen,
                      child: pages[item.index],
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: Courier.instance,
          builder: (context, _) {
            final unread = Courier.instance.roster.values
                .where((item) => !item.archived && !item.blocked)
                .fold(
                  0,
                  (total, item) =>
                      total + Courier.instance.unread(item.address),
                );
            final requests = Courier.instance.roster.values
                .where((item) => item.stranger)
                .length;
            return ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: NavigationBar(
                    backgroundColor: scheme.surface.withValues(alpha: 0.72),
                    selectedIndex: screen.index,
                    onDestinationSelected: (index) =>
                        setState(() => screen = Menu.values[index]),
                    destinations: [
                      NavigationDestination(
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text(unread > 99 ? '99+' : '$unread'),
                          child: const Icon(Icons.chat_bubble_outline),
                        ),
                        selectedIcon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text(unread > 99 ? '99+' : '$unread'),
                          child: const Icon(Icons.chat_bubble),
                        ),
                        label: 'Chats',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.diversity_3_outlined),
                        selectedIcon: Icon(Icons.diversity_3),
                        label: 'Communities',
                      ),
                      NavigationDestination(
                        icon: Badge(
                          isLabelVisible: requests > 0,
                          label: Text('$requests'),
                          child: const Icon(Icons.people_outline),
                        ),
                        selectedIcon: Badge(
                          isLabelVisible: requests > 0,
                          label: Text('$requests'),
                          child: const Icon(Icons.people),
                        ),
                        label: 'Trustees',
                      ),
                      NavigationDestination(
                        icon: Badge(
                          isLabelVisible: Courier.instance.live.isNotEmpty,
                          label: Text('${Courier.instance.live.length}'),
                          child: const Icon(Icons.hub_outlined),
                        ),
                        selectedIcon: const Icon(Icons.hub),
                        label: 'Network',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: 'Settings',
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    expiry?.cancel();
    arrivals?.cancel();
    super.dispose();
  }
}
