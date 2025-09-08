import 'package:flutter/material.dart';
import 'dart:developer' as developer;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('image_path'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color.fromRGBO(17, 17, 34, 1.0)],
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).size.height * 0.08,
                ),
                child: Image.asset('image_path', width: 100, height: 100),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Lorem Ipsum Dolor Sit Amet',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12.0),
                      const Text(
                        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam eget felis euismod, consectetur nisi at, eleifend mauris. Praesent venenatis ultrices odio, quis tincidunt enim gravida in. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Donec eget lobortis tortor. Mauris vulputate justo eget turpis sagittis, vel scelerisque magna vestibulum.',
                        style: TextStyle(
                          color: Color.fromRGBO(255, 255, 255, 0.8),
                        ),
                      ),
                      const SizedBox(height: 24.0),
                      ElevatedButton(
                        onPressed: () {
                          try {
                            Navigator.pushNamed(context, '/auth');
                          } catch (error, stackTrace) {
                            developer.log(
                              'Failed to navigate to authentication screen',
                              error: error,
                              stackTrace: stackTrace,
                              name: 'SplashScreen.navigation',
                            );
                          }
                        },
                        child: const Text('Continue'),
                      ),
                      const SizedBox(height: 12.0),
                      ElevatedButton(
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(
                            Colors.transparent,
                          ),
                          side: WidgetStateProperty.all(
                            const BorderSide(color: Colors.white, width: 2),
                          ),
                        ),
                        onPressed: () {
                          try {
                            Navigator.pushReplacementNamed(
                              context,
                              '/network', // SWITCH BACK TO /network/middleware
                            );
                          } catch (error, stackTrace) {
                            developer.log(
                              'Failed to navigate to map screen',
                              error: error,
                              stackTrace: stackTrace,
                              name: 'SplashScreen.navigation',
                            );
                          }
                        },
                        child: const Text('Decentralized Network'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } catch (error) {
      developer.log(
        'Failed to build SplashScreen widget',
        error: error,
        stackTrace: StackTrace.current,
        name: 'SplashScreen.build',
      );
      return const SizedBox.shrink();
    }
  }
}
