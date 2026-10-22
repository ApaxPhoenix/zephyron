import 'package:flutter/material.dart';
import 'package:zephyron/splash.dart';
import 'package:zephyron/auth/index.dart';
import 'package:zephyron/auth/panic.dart';
import 'package:zephyron/dashboard/index.dart';
import 'package:zephyron/dashboard/chats/group.dart';
import 'package:zephyron/dashboard/chats/message.dart';
import 'package:zephyron/dashboard/communities/channel.dart';
import 'package:zephyron/dashboard/communities/community.dart';
import 'package:zephyron/dashboard/communities/create.dart';
import 'package:zephyron/dashboard/peers/node.dart';
import 'package:zephyron/dashboard/vault/duress.dart';
import 'package:zephyron/dashboard/vault/profile.dart';
import 'package:zephyron/network/index.dart';
import 'package:zephyron/network/middleware.dart';

final Map<String, WidgetBuilder> routes = {
  '/': (context) => const SplashScreen(),
  '/auth': (context) => const AuthScreen(),
  '/panic': (context) => const PanicPage(),
  '/dashboard': (context) => const DashboardScreen(),
  '/dashboard/chats/message': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return MessagePage(
      id: arguments?['id'] as String?,
      title: arguments?['name'] as String? ?? arguments?['title'] as String?,
    );
  },
  '/dashboard/peers/node': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return NodePage(
      id: arguments?['id'] as String?,
      name: arguments?['name'] as String? ?? arguments?['title'] as String?,
    );
  },
  '/dashboard/chats/group': (context) => const GroupPage(),
  '/dashboard/communities/create': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return CreatePage(id: arguments?['id'] as String?);
  },
  '/dashboard/communities/community': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return CommunityPage(id: arguments?['id'] as String?);
  },
  '/dashboard/communities/channel': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return ChannelPage(
      community: arguments?['community'] as String?,
      channel: arguments?['channel'] as String?,
    );
  },
  '/dashboard/settings/profile': (context) => const ProfilePage(),
  '/dashboard/settings/duress': (context) => const DuressPage(),
  '/network': (context) => const NetworkScreen(),
  '/network/middleware': (context) => const NetworkMiddlewareScreen(),
};
