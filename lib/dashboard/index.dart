import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/index.dart';
import 'package:zephyron/dashboard/chats/stories.dart';
import 'package:zephyron/enums.dart';
import 'dart:developer' as developer;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  Menu screen = Menu.chats;
  late PageController pages;

  @override
  void initState() {
    super.initState();
    try {
      pages = PageController(initialPage: screen.index);
    } catch (error) {
      developer.log(
        'Unexpected structural fault during layout controller initialization: $error',
        name: 'DashboardScreen.setup',
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: PageView(
          controller: pages,
          onPageChanged: (index) {
            try {
              if (index < 0 || index >= Menu.values.length) return;
              if (mounted) {
                setState(() => screen = Menu.values[index]);
              }
            } catch (error) {
              developer.log(
                'Failed to sync state with active view index: $error',
                name: 'DashboardScreen.navigation',
                error: error,
                stackTrace: StackTrace.current,
              );
            }
          },
          children: const [
            ChatsPage(key: PageStorageKey('chats')),
            StoriesPage(key: PageStorageKey('stories')),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: screen.index,
          onDestinationSelected: (selected) {
            try {
              pages.animateToPage(
                selected,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            } catch (error) {
              developer.log(
                'Failed to route container target tab destination: $error',
                name: 'DashboardScreen.navigation',
                error: error,
                stackTrace: StackTrace.current,
              );
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(Icons.style),
              label: 'Stories',
            ),
          ],
        ),
      );
    } catch (error) {
      developer.log(
        'Failed to render master dashboard tab layout matrix: $error',
        name: 'DashboardScreen.build',
        error: error,
        stackTrace: StackTrace.current,
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      pages.dispose();
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to cleanly terminate long-lived view controller resources: $error',
        name: 'DashboardScreen.dispose',
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }
}
