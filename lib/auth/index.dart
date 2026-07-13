import 'package:flutter/material.dart';
import 'package:zephyron/auth/login.dart';
import 'package:zephyron/auth/signup.dart';
import 'dart:developer' as developer;

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => AuthScreenState();
}

class AuthScreenState extends State<AuthScreen> {
  final PageController controller = PageController(initialPage: 0);
  int index = 0;
  late List<Widget> items;

  @override
  void initState() {
    super.initState();
    try {
      items = [
        Builder(builder: (BuildContext context) => const LogInPage()),
        Builder(builder: (BuildContext context) => const SignUpPage()),
      ];
    } catch (error) {
      developer.log(
        'Error initializing items in initState: $error',
        name: 'AuthScreen.initState',
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
        body: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (DragEndDetails details) {
                  try {
                    if (details.primaryVelocity! > 0 && index > 0) {
                      controller.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else if (details.primaryVelocity! < 0 &&
                        index < items.length - 1) {
                      controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  } catch (error) {
                    developer.log(
                      'Error handling horizontal drag gesture: $error',
                      name: 'AuthScreen.drag',
                      error: error,
                      stackTrace: StackTrace.current,
                    );
                  }
                },
                child: PageView(
                  controller: controller,
                  onPageChanged: (i) {
                    try {
                      setState(() => index = i);
                    } catch (error) {
                      developer.log(
                        'Error changing page: $error',
                        name: 'AuthScreen.page',
                        error: error,
                        stackTrace: StackTrace.current,
                      );
                    }
                  },
                  children: items,
                ),
              ),
            ),
            Container(
              margin: EdgeInsets.symmetric(
                vertical:
                    (MediaQuery.of(context).viewPadding.top > 0 ||
                        MediaQuery.of(context).viewPadding.bottom > 0)
                    ? 20.0
                    : 0.0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  items.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    width: i == index ? 34.0 : 10.0,
                    height: 11.0,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.circular(5.0),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } catch (error) {
      developer.log(
        'Error building widget: $error',
        name: 'AuthScreen.build',
        error: error,
        stackTrace: StackTrace.current,
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      controller.dispose();
      super.dispose();
    } catch (error) {
      developer.log(
        'Error during dispose: $error',
        stackTrace: StackTrace.current,
        name: 'AuthScreen.dispose',
        error: error,
      );
    }
  }
}
