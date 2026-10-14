import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:zephyron/auth/login.dart';
import 'package:zephyron/auth/signup.dart';
import 'package:zephyron/sql/session.dart';

class Auth extends StatefulWidget {
  const Auth({super.key});

  @override
  State<Auth> createState() => _Auth();
}

class _Auth extends State<Auth> {
  final PageController controller = PageController(initialPage: 0);
  int index = 0;

  @override
  void initState() {
    super.initState();
    // A phone that already has an identity, such as one just locked, opens
    // on the unlock page rather than registration.
    Session.sessions().then((roster) {
      if (roster.isNotEmpty && mounted && controller.hasClients) {
        controller.jumpToPage(1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      Signup(
        unlock: () => (controller.animateToPage(
          1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )),
      ),
      Login(
        register: () => (controller.animateToPage(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )),
      ),
    ];

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
                      'Failed to route screen swipe gesture navigation: $error',
                      name: 'Auth.gesture',
                      error: error,
                      stackTrace: StackTrace.current,
                    );
                  }
                },
                child: PageView(
                  controller: controller,
                  onPageChanged: (page) {
                    try {
                      setState(() => index = page);
                    } catch (error) {
                      developer.log(
                        'Failed to sync state with active view index: $error',
                        name: 'Auth.navigation',
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
                  (dot) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    width: dot == index ? 34.0 : 10.0,
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
        'Failed to render master authentication container interface: $error',
        name: 'Auth.build',
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
        'Failed to cleanly release screen controller resources: $error',
        stackTrace: StackTrace.current,
        name: 'Auth.dispose',
        error: error,
      );
    }
  }
}
