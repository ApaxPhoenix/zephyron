import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Pallete {
  static const royal = Color.fromRGBO(48, 94, 231, 1);
  static const azure = Color.fromRGBO(58, 118, 240, 1);
  static const white = Color.fromRGBO(255, 255, 255, 1);
  static const snow = Color.fromRGBO(248, 248, 248, 1);
  static const mist = Color.fromRGBO(229, 229, 229, 1);
  static const silver = Color.fromRGBO(200, 200, 200, 1);
  static const slate = Color.fromRGBO(122, 122, 122, 1);
  static const ash = Color.fromRGBO(92, 92, 92, 1);
  static const charcoal = Color.fromRGBO(42, 42, 42, 1);
  static const coal = Color.fromRGBO(26, 26, 26, 1);
  static const ink = Color.fromRGBO(26, 26, 26, 1);
  static const crimson = Color.fromRGBO(229, 62, 62, 1);
  static const emerald = Color.fromRGBO(56, 161, 105, 1);
  static const amber = Color.fromRGBO(214, 158, 46, 1);

  /// Space between screen edges, app bars and content.
  static const double gutter = 20.0;

  static const String sans = 'Geist';
  static const String mono = 'GeistMono';

  static ThemeData compose(BuildContext context, Brightness brightness) {
    final light = brightness == Brightness.light;
    final background = light ? white : charcoal;
    final surface = light ? white : coal;
    final text = light ? ink : white;
    final muted = light ? ash : white.withValues(alpha: 0.7);
    final faint = light ? slate : white.withValues(alpha: 0.5);
    final border = light ? silver : ash.withValues(alpha: 0.5);
    final hairline = light ? mist : ash.withValues(alpha: 0.5);

    final scheme = ColorScheme.fromSeed(
      seedColor: royal,
      brightness: brightness,
      primary: royal,
      secondary: azure,
      tertiary: amber,
      tertiaryContainer: amber.withValues(alpha: light ? 0.15 : 0.25),
      onTertiaryContainer: amber,
      error: crimson,
      surface: surface,
      onSurface: text,
      onPrimary: white,
      onSecondary: white,
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
        actionsIconTheme: const IconThemeData(color: royal),
      ),
      iconTheme: const IconThemeData(color: royal),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48.0),
          backgroundColor: royal,
          foregroundColor: white,
          shape: rounded,
          elevation: 0.0,
          textStyle: type(14, FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64.0, 48.0),
          backgroundColor: royal,
          foregroundColor: white,
          shape: rounded,
          textStyle: type(14, FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: royal,
          elevation: 0.0,
          textStyle: type(14, FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64.0, 48.0),
          foregroundColor: royal,
          side: const BorderSide(color: royal),
          shape: rounded,
          textStyle: type(14, FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: light ? white : coal,
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: const BorderSide(color: royal, width: 2.0),
        ),
        errorBorder: outline.copyWith(
          borderSide: const BorderSide(color: crimson),
        ),
        focusedErrorBorder: outline.copyWith(
          borderSide: const BorderSide(color: crimson, width: 2.0),
        ),
        hintStyle: type(14, FontWeight.w400).copyWith(color: faint),
        labelStyle: type(14, FontWeight.w400).copyWith(color: muted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? royal : mist;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? royal.withValues(alpha: 0.4)
              : mist.withValues(alpha: 0.4);
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? royal
              : Colors.transparent;
        }),
        side: const BorderSide(color: royal, width: 2.0),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? royal : silver;
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: royal,
        linearTrackColor: mist,
        circularTrackColor: mist,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: light ? snow : coal,
        selectedColor: royal.withValues(alpha: light ? 0.15 : 0.3),
        labelStyle: type(12, FontWeight.w500),
        secondaryLabelStyle: type(12, FontWeight.w500).copyWith(color: royal),
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
        selectedTileColor: royal.withValues(alpha: light ? 0.15 : 0.25),
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
        backgroundColor: royal,
        textColor: white,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: royal,
        unselectedLabelColor: muted,
        indicatorColor: royal,
        labelStyle: type(12, FontWeight.w600),
        unselectedLabelStyle: type(12, FontWeight.w500),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: royal.withValues(alpha: light ? 0.3 : 0.4),
        cursorColor: royal,
        selectionHandleColor: royal,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        elevation: 0.0,
        indicatorColor: royal.withValues(alpha: light ? 0.2 : 0.3),
        labelType: NavigationRailLabelType.all,
        selectedIconTheme: const IconThemeData(color: royal),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: type(
          12,
          FontWeight.w500,
        ).copyWith(color: royal),
        unselectedLabelTextStyle: type(
          12,
          FontWeight.w400,
        ).copyWith(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0.0,
        indicatorColor: royal.withValues(alpha: light ? 0.2 : 0.3),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => type(12, FontWeight.w500).copyWith(
            color: states.contains(WidgetState.selected) ? royal : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? royal : muted,
          ),
        ),
      ),
    );
  }

  /// A solid round button. The theme tints icons brand blue, so a filled
  /// button has to say its icon is white or it vanishes into its fill.
  static ButtonStyle solid(ColorScheme scheme) => IconButton.styleFrom(
    backgroundColor: scheme.primary,
    foregroundColor: scheme.onPrimary,
    disabledBackgroundColor: scheme.surfaceContainerHigh,
    disabledForegroundColor: scheme.onSurfaceVariant,
  );

  static ThemeData day(BuildContext context) {
    return compose(context, Brightness.light);
  }

  static ThemeData night(BuildContext context) {
    return compose(context, Brightness.dark);
  }
}
