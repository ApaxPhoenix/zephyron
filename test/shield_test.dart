import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/shield.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('screen security is on unless someone turns it off', () {
    expect(Preferences().shield, isTrue);
    expect(Preferences.fromJson({}).shield, isTrue);
    final off = Preferences(shield: false);
    expect(Preferences.fromJson(off.toJson()).shield, isFalse);
  });

  test('the native side is told to secure the window', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Shield.link, (call) async {
          calls.add(call);
          return null;
        });
    await Shield.apply(false);
    await Shield.apply(true);
    expect(calls.map((call) => call.method), ['shield', 'shield']);
    expect(calls.map((call) => call.arguments), [false, true]);
  });

  testWidgets('the curtain hides the app while it is in the background', (
    tester,
  ) async {
    final enabled = ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Curtain(
          enabled: enabled,
          child: const Scaffold(body: Text('secret chat')),
        ),
      ),
    );
    expect(find.byIcon(Icons.shield_outlined), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

    enabled.value = false;
    await tester.pump();
    expect(find.byIcon(Icons.shield_outlined), findsNothing);

    enabled.value = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
  });
}
