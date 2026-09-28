import 'package:flutter/material.dart';
import 'package:zephyron/splash.dart';
import 'package:zephyron/auth/index.dart';
import 'package:zephyron/auth/panic.dart';
import 'package:zephyron/dashboard/index.dart';
import 'package:zephyron/dashboard/chats/call.dart';
import 'package:zephyron/dashboard/chats/group.dart';
import 'package:zephyron/dashboard/chats/message.dart';
import 'package:zephyron/dashboard/communities/channel.dart';
import 'package:zephyron/dashboard/communities/community.dart';
import 'package:zephyron/dashboard/communities/create.dart';
import 'package:zephyron/dashboard/communities/discover.dart';
import 'package:zephyron/dashboard/peers/node.dart';
import 'package:zephyron/dashboard/vault/duress.dart';
import 'package:zephyron/dashboard/vault/profile.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/network/index.dart';
import 'package:zephyron/network/middleware.dart';

final Map<String, WidgetBuilder> routes = {
  '/': (context) => const Splash(),
  '/auth': (context) => const Auth(),
  '/panic': (context) => const Panic(),
  '/dashboard': (context) => const Dashboard(),
  '/dashboard/chats/message': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return Conversation(
      id: arguments?['id'] as String?,
      title: arguments?['name'] as String? ?? arguments?['title'] as String?,
    );
  },
  '/dashboard/peers/node': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return Node(
      id: arguments?['id'] as String?,
      name: arguments?['name'] as String? ?? arguments?['title'] as String?,
    );
  },
  '/dashboard/chats/group': (context) => const Huddle(),
  '/dashboard/chats/call': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return Call(peer: arguments?['peer'] as String?);
  },
  '/dashboard/communities/create': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return Creation(id: arguments?['id'] as String?);
  },
  '/dashboard/communities/community': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return Hub(id: arguments?['id'] as String?);
  },
  '/dashboard/communities/channel': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return Board(
      community: arguments?['community'] as String?,
      channel: arguments?['channel'] as String?,
    );
  },
  '/dashboard/communities/discover': (context) {
    final arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return Discover(
      shelf: arguments?['shelf'] == Shelf.person.name
          ? Shelf.person
          : Shelf.community,
    );
  },
  '/dashboard/settings/profile': (context) => const Persona(),
  '/dashboard/settings/duress': (context) => const Decoy(),
  '/network': (context) => const Network(),
  '/network/middleware': (context) => const Middleware(),
};
