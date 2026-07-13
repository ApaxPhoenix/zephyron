import 'package:flutter/material.dart';
import 'package:zephyron/dashboard/chats/index.dart';
import 'package:zephyron/dashboard/stories.dart';
import 'package:zephyron/enums.dart';

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
    pages = PageController(initialPage: screen.index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: PageView(
        controller: pages,
        onPageChanged: (index) {
          if (index < 0 || index >= Menu.values.length) return;
          if (mounted) {
            setState(() => screen = Menu.values[index]);
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
          pages.animateToPage(
            selected,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
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
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }
}
