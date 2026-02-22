import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Pallete {
  static const brand100 = Color.fromRGBO(48, 94, 231, 1);
  static const brand200 = Color.fromRGBO(58, 118, 240, 1);
  static const neutral000 = Color.fromRGBO(255, 255, 255, 1);
  static const neutral050 = Color.fromRGBO(248, 248, 248, 1);
  static const neutral100 = Color.fromRGBO(229, 229, 229, 1);
  static const neutral300 = Color.fromRGBO(200, 200, 200, 1);
  static const neutral500 = Color.fromRGBO(122, 122, 122, 1);
  static const neutral700 = Color.fromRGBO(92, 92, 92, 1);
  static const neutral800 = Color.fromRGBO(42, 42, 42, 1);
  static const neutral850 = Color.fromRGBO(26, 26, 26, 1);
  static const neutral900 = Color.fromRGBO(26, 26, 26, 1);
  static const error500 = Color.fromRGBO(229, 62, 62, 1);
  static const success500 = Color.fromRGBO(56, 161, 105, 1);
  static const warning500 = Color.fromRGBO(214, 158, 46, 1);

  /// Space between screen edges, app bars and content.
  static const double gutter = 20.0;

  static const String sans = 'Geist';
  static const String mono = 'GeistMono';

  static ThemeData baseTheme(BuildContext context, Brightness brightness) {
    final light = brightness == Brightness.light;
    final background = light ? neutral000 : neutral800;
    final surface = light ? neutral000 : neutral850;
    final text = light ? neutral900 : neutral000;
    final muted = light ? neutral700 : neutral000.withValues(alpha: 0.7);
    final faint = light ? neutral500 : neutral000.withValues(alpha: 0.5);
    final border = light ? neutral300 : neutral700.withValues(alpha: 0.5);
    final hairline = light ? neutral100 : neutral700.withValues(alpha: 0.5);

    final scheme = ColorScheme.fromSeed(
      seedColor: brand100,
      brightness: brightness,
      primary: brand100,
      secondary: brand200,
      tertiary: warning500,
      tertiaryContainer: warning500.withValues(alpha: light ? 0.15 : 0.25),
      onTertiaryContainer: warning500,
      error: error500,
      surface: surface,
      onSurface: text,
      onPrimary: neutral000,
      onSecondary: neutral000,
      outline: border,
      outlineVariant: hairline,
    );

    TextStyle type(double size, FontWeight weight) {
      return TextStyle(
        fontFamily: sans,
        fontSize: size,
        fontWeight: weight,
        color: text,
      );
    }

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12.0),
    );
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.0),
      borderSide: BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: sans,
      scaffoldBackgroundColor: background,
      dividerColor: hairline,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: TextTheme(
        displayLarge: type(57, FontWeight.w400),
        displayMedium: type(45, FontWeight.w400),
        displaySmall: type(36, FontWeight.w400),
        headlineLarge: type(32, FontWeight.w500),
        headlineMedium: type(28, FontWeight.w500),
        headlineSmall: type(24, FontWeight.w500),
        titleLarge: type(22, FontWeight.w500),
        titleMedium: type(16, FontWeight.w500),
        titleSmall: type(14, FontWeight.w500),
        bodyLarge: type(16, FontWeight.w400),
        bodyMedium: type(14, FontWeight.w400),
        bodySmall: type(12, FontWeight.w400).copyWith(color: muted),
        labelLarge: type(14, FontWeight.w500),
        labelMedium: type(12, FontWeight.w500),
        labelSmall: type(11, FontWeight.w500).copyWith(color: muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: hairline)),
        titleTextStyle: type(20.0, FontWeight.w600),
        iconTheme: IconThemeData(color: text),
        actionsIconTheme: const IconThemeData(color: brand100),
      ),
      iconTheme: const IconThemeData(color: brand100),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48.0),
          backgroundColor: brand100,
          foregroundColor: neutral000,
          shape: rounded,
          elevation: 0.0,
          textStyle: type(14, FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64.0, 48.0),
          backgroundColor: brand100,
          foregroundColor: neutral000,
          shape: rounded,
          textStyle: type(14, FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand100,
          elevation: 0.0,
          textStyle: type(14, FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64.0, 48.0),
          foregroundColor: brand100,
          side: const BorderSide(color: brand100),
          shape: rounded,
          textStyle: type(14, FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: light ? neutral000 : neutral850,
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: const BorderSide(color: brand100, width: 2.0),
        ),
        errorBorder: outline.copyWith(
          borderSide: const BorderSide(color: error500),
        ),
        focusedErrorBorder: outline.copyWith(
          borderSide: const BorderSide(color: error500, width: 2.0),
        ),
        hintStyle: type(14, FontWeight.w400).copyWith(color: faint),
        labelStyle: type(14, FontWeight.w400).copyWith(color: muted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? brand100 : neutral100;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? brand100.withValues(alpha: 0.4)
              : neutral100.withValues(alpha: 0.4);
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? brand100
              : Colors.transparent;
        }),
        side: const BorderSide(color: brand100, width: 2.0),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? brand100 : neutral300;
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brand100,
        linearTrackColor: neutral100,
        circularTrackColor: neutral100,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: light ? neutral050 : neutral850,
        selectedColor: brand100.withValues(alpha: light ? 0.15 : 0.3),
        labelStyle: type(12, FontWeight.w500),
        secondaryLabelStyle: type(
          12,
          FontWeight.w500,
        ).copyWith(color: brand100),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        showCheckmark: false,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: gutter),
        minVerticalPadding: 10.0,
        titleTextStyle: type(15, FontWeight.w500),
        subtitleTextStyle: type(13, FontWeight.w400).copyWith(color: muted),
        selectedTileColor: brand100.withValues(alpha: light ? 0.15 : 0.25),
        iconColor: muted,
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: hairline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0.0,
        modalElevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
          side: BorderSide(color: hairline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: hairline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: brand100,
        textColor: neutral000,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: brand100,
        unselectedLabelColor: muted,
        indicatorColor: brand100,
        labelStyle: type(12, FontWeight.w600),
        unselectedLabelStyle: type(12, FontWeight.w500),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: brand100.withValues(alpha: light ? 0.3 : 0.4),
        cursorColor: brand100,
        selectionHandleColor: brand100,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        elevation: 0.0,
        indicatorColor: brand100.withValues(alpha: light ? 0.2 : 0.3),
        labelType: NavigationRailLabelType.all,
        selectedIconTheme: const IconThemeData(color: brand100),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: type(
          12,
          FontWeight.w500,
        ).copyWith(color: brand100),
        unselectedLabelTextStyle: type(
          12,
          FontWeight.w400,
        ).copyWith(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0.0,
        indicatorColor: brand100.withValues(alpha: light ? 0.2 : 0.3),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => type(12, FontWeight.w500).copyWith(
            color: states.contains(WidgetState.selected) ? brand100 : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? brand100 : muted,
          ),
        ),
      ),
    );
  }

  static ThemeData lightTheme(BuildContext context) {
    return baseTheme(context, Brightness.light);
  }

  static ThemeData darkTheme(BuildContext context) {
    return baseTheme(context, Brightness.dark);
  }
}
