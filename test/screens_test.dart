import 'dart:convert';
import 'package:zephyron/widgets/avatar.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/dashboard/chats/index.dart';
import 'package:zephyron/dashboard/chats/message.dart';
import 'package:zephyron/dashboard/peers/index.dart';
import 'package:zephyron/dashboard/peers/node.dart';
import 'package:zephyron/dashboard/relays/index.dart';
import 'package:zephyron/dashboard/vault/index.dart';
import 'package:zephyron/dashboard/vault/profile.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/services/mesh.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/widgets/section.dart';
import 'package:zephyron/dashboard/communities/community.dart';
import 'package:zephyron/dashboard/communities/discover.dart';
import 'package:zephyron/services/catalog.dart';
import 'package:zephyron/services/ratchet.dart';
import 'package:zephyron/sql/ledger.dart';
import 'package:zephyron/dashboard/chats/call.dart';
import 'package:zephyron/dashboard/communities/channel.dart';
import 'package:zephyron/services/stage.dart';
import 'support.dart';

void main() {
  final courier = Courier.instance;
  final dana = Identity.fromInput('dana test seed phrase');

  late Wire known;
  late Wire stranger;

  setUpAll(() async {
    await unlock();
    known = await Wire.open();
    stranger = await Wire.open();
  });

  tearDownAll(() async {
    await known.close();
    await stranger.close();
  });

  setUp(() {
    reset();
    courier.reach.value = Reach.online;
    courier.me = Profile(name: 'Bob Stone', mood: 'testing');
    final now = DateTime.now();
    courier.roster
      ..[alice.address] = Trustee(
        address: alice.address,
        alias: 'Alice Moreau',
        mood: 'reviewing',
        pinned: true,
      )
      ..[carol.address] = Trustee(address: carol.address, trust: Trust.stranger)
      ..[dana.address] = Trustee(
        address: dana.address,
        alias: 'Dana',
        trust: Trust.blocked,
      );
    courier.threads[alice.address] = [
      Message(
        id: 'a1',
        peer: alice.address,
        mine: false,
        text: 'Did the build land?',
        time: now.subtract(const Duration(minutes: 10)),
        status: Status.read,
      ),
      Message(
        id: 'a2',
        peer: alice.address,
        mine: true,
        text: 'Yes, all green',
        time: now.subtract(const Duration(minutes: 5)),
        status: Status.delivered,
      ),
    ];
    courier.threads[carol.address] = [
      Message(
        id: 'c1',
        peer: carol.address,
        mine: false,
        text: 'found your key on the forum',
        time: now.subtract(const Duration(minutes: 1)),
        status: Status.delivered,
      ),
    ];
    courier.presence[alice.address] = Presence()
      ..seen = now
      ..latency = 840;
  });

  Future<void> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Builder(
        builder: (context) =>
            MaterialApp(theme: Pallete.lightTheme(context), home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('chats list orders, filters and searches conversations', (
    tester,
  ) async {
    await show(tester, const ChatsPage());

    expect(find.text('Alice Moreau'), findsOneWidget);
    expect(find.text('Yes, all green'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Dana'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Unread'));
    await tester.pumpAndSettle();
    expect(find.text('Alice Moreau'), findsNothing);
    expect(find.text('found your key on the forum'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.enterText(find.byType(TextField), 'alice');
    await tester.pumpAndSettle();
    expect(find.text('Alice Moreau'), findsOneWidget);
    expect(find.text('found your key on the forum'), findsNothing);
  });

  testWidgets('chats list welcomes a new identity', (tester) async {
    courier.roster.clear();
    courier.threads.clear();
    await show(tester, const ChatsPage());
    expect(find.text('No Conversations Yet'), findsOneWidget);
    expect(find.text('Start New Chat'), findsOneWidget);
  });

  testWidgets('conversation shows bubbles, receipts and presence', (
    tester,
  ) async {
    await show(tester, MessagePage(id: alice.address));

    expect(find.text('Did the build land?'), findsOneWidget);
    expect(find.text('Yes, all green'), findsOneWidget);
    expect(find.text('online · 840 ms'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.text('Message request'), findsNothing);
  });

  testWidgets('a stranger thread offers accept and block', (tester) async {
    await show(tester, MessagePage(id: carol.address));
    expect(find.text('Message request'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
  });

  testWidgets('trustees are grouped and blocked keys stay folded', (
    tester,
  ) async {
    await show(tester, const PeersPage());

    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(3));
    expect(find.text('Dana'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('Dana'), findsOneWidget);
  });

  testWidgets('a peer profile shows trust, key and safety code', (
    tester,
  ) async {
    await show(tester, NodePage(id: carol.address));

    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Discovery Key'), findsOneWidget);
    expect(find.text('Safety Code'), findsOneWidget);
    final code = Courier.safety(bob.address, carol.address);
    expect(find.textContaining(code.first), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Add as Trustee'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Add as Trustee'), findsOneWidget);
  });

  testWidgets('settings reflect the profile and preferences', (tester) async {
    await show(tester, const VaultPage());

    expect(find.text('Bob Stone'), findsOneWidget);
    expect(find.text('testing'), findsOneWidget);
    expect(find.text('Read Receipts'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byTooltip('Lock Vault'), findsNothing);

    await tester.tap(find.text(Availability.available.label));
    await tester.pumpAndSettle();
    expect(find.text('Set Status'), findsOneWidget);
    for (final state in Availability.values) {
      expect(find.byKey(ValueKey('status:${state.name}')), findsOneWidget);
    }
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Lock Vault'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(OutlinedButton, 'Lock Vault'), findsOneWidget);
  });

  testWidgets('profile editor updates the avatar as you type', (tester) async {
    await show(tester, const ProfilePage());

    expect(find.text('BS'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Zed');
    await tester.pumpAndSettle();
    expect(find.text('Z'), findsOneWidget);
    expect(find.text('Save Profile'), findsOneWidget);
  });

  testWidgets('network lists who is on your node', (tester) async {
    final channels = courier.live.toList();
    expect(channels, hasLength(2));
    channels.first.peer = alice.address;
    channels.last.peer = null;
    await show(tester, const RelaysPage());

    expect(find.widgetWithText(Tab, 'Overview'), findsOneWidget);
    expect(find.text('At a Glance'), findsOneWidget);
    expect(find.text('Alice Moreau'), findsNothing);

    await tester.tap(find.text('On Your Node'));
    await tester.pumpAndSettle();
    expect(find.text('Alice Moreau'), findsOneWidget);
    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.textContaining('Joined your node'), findsNWidgets(2));
    expect(find.byType(Pager), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'Circuits'));
    await tester.pumpAndSettle();
    expect(
      find.text('Circuits appear once Tor has bootstrapped.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(Tab, 'Bridges'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Bridges'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('banners fill their frame, with or without a picture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Cover(
                key: const ValueKey('picture'),
                banner: Uint8List.fromList(List.filled(64, 1)),
                height: 120,
              ),
              const Cover(key: ValueKey('plain'), banner: null, height: 120),
            ],
          ),
        ),
      ),
    );
    final width = tester.getSize(find.byType(Scaffold)).width;
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('picture')),
          matching: find.byType(Image),
        ),
      ),
      Size(width, 120),
    );
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('plain')),
          matching: find.byType(DecoratedBox),
        ),
      ),
      Size(width, 120),
    );
  });

  testWidgets('voice notes and videos show their length', (tester) async {
    final now = DateTime.now();
    courier.threads[alice.address] = [
      Message(
        id: 'v1',
        peer: alice.address,
        mine: false,
        kind: Kind.voice,
        text: '',
        time: now,
        status: Status.delivered,
        meta: {'duration': 67000, 'size': 2000, 'name': 'voice.m4a'},
      ),
      Message(
        id: 'v2',
        peer: alice.address,
        mine: true,
        kind: Kind.video,
        text: 'the view',
        time: now,
        status: Status.delivered,
        meta: {
          'duration': 9000,
          'size': 2 * 1024 * 1024,
          'width': 1280,
          'height': 720,
          'name': 'clip.mp4',
        },
      ),
    ];
    await show(tester, MessagePage(id: alice.address));
    expect(find.text('1:07'), findsOneWidget);
    expect(find.text('0:09 · 2.0 MB'), findsOneWidget);
    expect(find.text('the view'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('the composer offers a microphone until you type', (
    tester,
  ) async {
    await show(tester, MessagePage(id: alice.address));
    expect(find.byTooltip('Record voice message'), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.byTooltip('Record voice message'), findsNothing);
  });

  testWidgets('groups sit with chats and have their own filter', (
    tester,
  ) async {
    late Community group;
    await tester.runAsync(() async {
      await Mesh.instance.start();
      group = await Mesh.instance.create(name: 'Weekend Hikers', group: true);
      await Mesh.instance.say(group, group.general, 'Trail at 8?');
    });
    await show(tester, const ChatsPage());
    expect(find.text('Weekend Hikers'), findsOneWidget);
    expect(find.textContaining('Trail at 8?'), findsOneWidget);
    expect(find.text('Alice Moreau'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Groups'));
    await tester.pumpAndSettle();
    expect(find.text('Weekend Hikers'), findsOneWidget);
    expect(find.text('Alice Moreau'), findsNothing);
    await tester.runAsync(() => Mesh.instance.leave(group.id));
  });

  testWidgets('discover lists people and communities, and hides on request', (
    tester,
  ) async {
    final catalog = Catalog.instance;
    await tester.runAsync(() async {
      await Mesh.instance.start();
      await catalog.start();
      await catalog.renewing;
      Future<void> list(
        Identity who,
        Shelf shelf,
        String subject,
        String name, {
        Map<String, dynamic> invitation = const {},
      }) async {
        become(who);
        final frame = await catalog.compose(
          shelf,
          subject,
          name: name,
          about: 'About $name',
          invitation: invitation,
        );
        become(bob);
        await catalog.accept(Catalog.check(frame)!);
      }

      await list(carol, Shelf.person, carol.address, 'Carol Reyes');
      await list(
        alice,
        Shelf.community,
        Courier.token(),
        'Open Mic',
        invitation: {
          'key': base64.encode(Ratchet.random(32)),
          'keys': <String, String>{},
          'created': DateTime.now().millisecondsSinceEpoch,
        },
      );
    });
    await show(tester, const DiscoverPage());
    expect(find.text('Open Mic'), findsOneWidget);
    expect(find.text('About Open Mic'), findsOneWidget);

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(find.text('Carol Reyes'), findsOneWidget);
    expect(find.text('List Me Here'), findsOneWidget);

    await tester.tap(find.text('Carol Reyes'));
    await tester.pumpAndSettle();
    expect(find.text('Add as Trustee'), findsOneWidget);
    await tester.tap(find.text('Hide and Stop Passing Along'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Carol Reyes'), findsNothing);

    await tester.runAsync(() async {
      for (final id in catalog.listings.keys.toList()) {
        await Ledger.unlist(id);
      }
      await Ledger.remove('catalog');
      await catalog.start();
    });
  });

  testWidgets('a founder can list their community in discover', (tester) async {
    late Community community;
    await tester.runAsync(() async {
      await Mesh.instance.start();
      community = await Mesh.instance.create(name: 'Night Shift');
    });
    await show(tester, CommunityPage(id: community.id));
    await tester.scrollUntilVisible(
      find.text('List in Discover'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Off. Only people you invite can join'), findsOneWidget);
    await tester.runAsync(() => Mesh.instance.leave(community.id));
  });

  testWidgets('an incoming call offers to accept or decline', (tester) async {
    Stage.instance.ringing = Ring(
      from: alice.address,
      id: 'call',
      secret: Uint8List(32),
    );
    await show(tester, const CallPage());
    expect(find.text('Alice Moreau'), findsOneWidget);
    expect(find.text('Incoming voice call'), findsOneWidget);
    expect(find.byTooltip('Accept'), findsOneWidget);
    expect(find.byTooltip('Decline'), findsOneWidget);
    Stage.instance.reset();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('calls show in the chat, and trustees can be called', (
    tester,
  ) async {
    courier.threads[alice.address]!.add(
      Message(
        id: 'call1',
        peer: alice.address,
        mine: false,
        kind: Kind.call,
        text: '',
        time: DateTime.now(),
        status: Status.read,
        meta: {'duration': 65000},
      ),
    );
    await show(tester, MessagePage(id: alice.address));
    expect(find.text('Voice call · 1:05'), findsOneWidget);
    expect(find.byTooltip('Voice Call'), findsOneWidget);
  });

  testWidgets('a group chat can start a call', (tester) async {
    late Community group;
    await tester.runAsync(() async {
      await Mesh.instance.start();
      group = await Mesh.instance.create(name: 'Family', group: true);
    });
    await show(
      tester,
      ChannelPage(community: group.id, channel: group.general),
    );
    expect(find.byTooltip('Group Call'), findsOneWidget);
    await tester.runAsync(() => Mesh.instance.leave(group.id));
  });
}
