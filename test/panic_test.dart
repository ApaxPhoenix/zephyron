import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/auth/panic.dart';
import 'package:zephyron/theme.dart';

void main() {
  testWidgets('the panic countdown can be cancelled before it erases', (
    tester,
  ) async {
    var erased = false;
    await tester.pumpWidget(
      Builder(
        builder: (context) => MaterialApp(
          theme: Pallete.lightTheme(context),
          routes: {
            '/': (context) => Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/panic'),
                  child: const Text('open'),
                ),
              ),
            ),
            '/panic': (context) => const PanicPage(),
            '/auth': (context) {
              erased = true;
              return const SizedBox();
            },
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Erasing everything'), findsOneWidget);
    expect(find.text('${PanicPage.grace}'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('${PanicPage.grace - 1}'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(PanicPage), findsNothing);

    await tester.pump(const Duration(seconds: PanicPage.grace + 2));
    expect(erased, isFalse);
  });
}
