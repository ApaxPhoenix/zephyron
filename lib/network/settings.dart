import 'package:flutter/material.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/state.dart';
import 'dart:developer' as developer;

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => NetworkSettingsPageState();
}

class NetworkSettingsPageState extends State<NetworkSettingsPage> {
  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        backgroundColor: Pallete.neutral000,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: Pallete.neutral900,
              size: 24,
            ),
            onPressed: () {
              try {
                Navigator.of(context).pop();
              } catch (error) {
                developer.log(
                  'Navigation pop error: $error',
                  name: 'NetworkSettingsPage.pop',
                  error: error,
                );
              }
            },
          ),
        ),
        body: SafeArea(
          child: ValueListenableBuilder(
            valueListenable: notifier,
            builder: (context, settings, child) {
              try {
                String appearance = 'light';
                if (settings.appearance == Appearance.dark) appearance = 'dark';
                if (settings.appearance == Appearance.grayscale) {
                  appearance = 'grayscale';
                }

                String speed = '60 FPS';
                if (settings.fps == 120) speed = 'Max performance';
                if (settings.fps == 30) speed = '30 FPS (Power save)';

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Pallete.neutral900,
                            ),
                      ),
                      const SizedBox(height: 32),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Map performance & quality',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Pallete.neutral700,
                          ),
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: appearance,
                        dropdownColor: Pallete.neutral050,
                        style: TextStyle(color: Pallete.neutral900),
                        decoration: InputDecoration(
                          labelText: 'Appearance mode',
                          labelStyle: TextStyle(color: Pallete.neutral500),
                          prefixIcon: const Icon(
                            Icons.my_location,
                            color: Pallete.neutral900,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Pallete.neutral300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Pallete.brand200),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'light',
                            child: Text('Light'),
                          ),
                          DropdownMenuItem(value: 'dark', child: Text('Dark')),
                          DropdownMenuItem(
                            value: 'grayscale',
                            child: Text('Grayscale'),
                          ),
                        ],
                        onChanged: (value) {
                          try {
                            Appearance selected = Appearance.light;
                            if (value == 'dark') selected = Appearance.dark;
                            if (value == 'grayscale')
                              selected = Appearance.grayscale;
                            notifier.value = settings.copyWith(
                              appearance: selected,
                            );
                          } catch (error) {
                            developer.log(
                              'Appearance configuration change error: $error',
                              name: 'NetworkSettingsPage.appearanceChanged',
                              error: error,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: speed,
                        dropdownColor: Pallete.neutral050,
                        style: TextStyle(color: Pallete.neutral900),
                        decoration: InputDecoration(
                          labelText: 'Rendering speed',
                          labelStyle: TextStyle(color: Pallete.neutral500),
                          prefixIcon: const Icon(
                            Icons.speed,
                            color: Pallete.neutral900,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Pallete.neutral300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Pallete.brand200),
                          ),
                        ),
                        items:
                            ['Max performance', '60 FPS', '30 FPS (Power save)']
                                .map(
                                  (label) => DropdownMenuItem(
                                    value: label,
                                    child: Text(label),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          try {
                            int target = 60;
                            if (value == 'Max performance') target = 120;
                            if (value == '30 FPS (Power save)') target = 30;
                            notifier.value = settings.copyWith(fps: target);
                          } catch (error) {
                            developer.log(
                              'Rendering speed configuration change error: $error',
                              name: 'NetworkSettingsPage.speedChanged',
                              error: error,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Cache size limit',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Pallete.neutral900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Slider(
                        value: settings.cache,
                        min: 100,
                        max: 2000,
                        divisions: 19,
                        label: '${settings.cache.toInt()} MB',
                        activeColor: Pallete.brand100,
                        inactiveColor: Pallete.neutral100,
                        onChanged: (value) {
                          try {
                            notifier.value = settings.copyWith(cache: value);
                          } catch (error) {
                            developer.log(
                              'Cache allocation configuration change error: $error',
                              name: 'NetworkSettingsPage.cacheChanged',
                              error: error,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'App settings',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Pallete.neutral700,
                          ),
                        ),
                      ),
                      Item(
                        icon: Icons.wb_sunny_outlined,
                        title: 'Appearance',
                        onTap: () {},
                      ),
                      Item(
                        icon: Icons.storage_outlined,
                        title: 'Clear cache data',
                        onTap: () {},
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Support',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Pallete.neutral700,
                          ),
                        ),
                      ),
                      Item(
                        icon: Icons.help_outline,
                        title: 'Help center',
                        onTap: () {},
                      ),
                      Item(
                        icon: Icons.info_outline,
                        title: 'About',
                        onTap: () {},
                      ),
                    ],
                  ),
                );
              } catch (error) {
                developer.log(
                  'ValueListenableBuilder view assembly error: $error',
                  name: 'NetworkSettingsPage.builder',
                  error: error,
                );
                return const SizedBox.shrink();
              }
            },
          ),
        ),
      );
    } catch (error) {
      developer.log(
        'Build layout execution error: $error',
        name: 'NetworkSettingsPage.build',
        error: error,
      );
      return const SizedBox.shrink();
    }
  }
}

class Item extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const Item({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
        onTap: () {
          try {
            onTap();
          } catch (error) {
            developer.log(
              'Item click callback processing failure: $error',
              name: 'Item.onTap',
              error: error,
            );
          }
        },
        leading: Icon(icon, color: Pallete.neutral900, size: 24),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Pallete.neutral900),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Pallete.neutral500,
          size: 20,
        ),
      );
    } catch (error) {
      developer.log(
        'Item construction processing error: $error',
        name: 'Item.build',
        error: error,
      );
      return const SizedBox.shrink();
    }
  }
}
