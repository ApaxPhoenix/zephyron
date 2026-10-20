import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/auth/index.dart';
import 'package:zephyron/theme.dart';

void main() {
  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Builder(
        builder: (context) => MaterialApp(
          theme: Pallete.lightTheme(context),
          home: const AuthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('registration is the first screen and starts locked', (
    tester,
  ) async {
    await show(tester);

    expect(find.text('Create your identity'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Name this identity'), findsOneWidget);
    expect(find.text('Your recovery phrase'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    final create = find.widgetWithText(ElevatedButton, 'Create identity');
    await tester.scrollUntilVisible(
      create,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<ElevatedButton>(create).onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(create).onPressed, isNotNull);
  });

  testWidgets('registration explains what is wrong with a passphrase', (
    tester,
  ) async {
    await show(tester);

    await tester.enterText(find.byType(TextFormField).at(1), 'short');
    await tester.pumpAndSettle();
    expect(find.text('Use at least 12 characters'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'longenoughpass');
    await tester.pumpAndSettle();
    expect(find.text('Add an uppercase letter'), findsOneWidget);
  });

  testWidgets('the unlock screen is one tap away', (tester) async {
    await show(tester);

    final link = find.text('Already have an identity? Unlock it');
    await tester.scrollUntilVisible(
      link,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Create your first identity'), findsOneWidget);

    await tester.tap(find.text('Create your first identity'));
    await tester.pumpAndSettle();
    expect(find.text('Create your identity'), findsOneWidget);
  });
}
