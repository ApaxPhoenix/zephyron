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
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/theme.dart';
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

    expect(find.text('On Your Node'), findsOneWidget);
    expect(find.text('Circuits'), findsNWidgets(2));
    expect(find.text('Bridges'), findsOneWidget);
    expect(find.text('Alice Moreau'), findsOneWidget);
    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.textContaining('Joined your node'), findsNWidgets(2));
    expect(
      find.text('Circuits appear once Tor has bootstrapped.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Use Bridges'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Use Bridges'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
}
