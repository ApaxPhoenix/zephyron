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

  static ThemeData baseTheme(BuildContext context, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'SF Pro',
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
        ),
        displayMedium: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
        ),
        displaySmall: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
        ),
        titleLarge: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
        ),
        titleMedium: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
        ),
        titleSmall: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w400),
        labelLarge: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
        ),
        labelMedium: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
        ),
        labelSmall: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48.0),
          backgroundColor: brand100,
          foregroundColor: neutral000,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          elevation: 0.0,
          textStyle: const TextStyle(
            fontFamily: 'SF Pro',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand100,
          elevation: 0.0,
          textStyle: const TextStyle(
            fontFamily: 'SF Pro',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand100,
          side: const BorderSide(color: brand100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          textStyle: const TextStyle(
            fontFamily: 'SF Pro',
            fontWeight: FontWeight.w500,
          ),
        ),
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
          return states.contains(WidgetState.selected) ? brand100 : neutral100;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand100,
        linearTrackColor: neutral100,
        circularTrackColor: neutral100,
      ),
      iconTheme: IconThemeData(color: brand100),
      chipTheme: ChipThemeData(
        backgroundColor: brightness == Brightness.light
            ? neutral050
            : neutral850,
        selectedColor: brand100.withValues(
          alpha: brightness == Brightness.light ? 0.15 : 0.3,
        ),
        labelStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
          color: brightness == Brightness.light ? neutral900 : neutral000,
          fontSize: 12.0,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
          color: brand100,
          fontSize: 12.0,
        ),
        side: BorderSide(
          color: brightness == Brightness.light
              ? neutral300
              : neutral700.withValues(alpha: 0.5),
          width: 1.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        showCheckmark: false,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        tileColor: Colors.transparent,
        selectedTileColor: brand100.withValues(
          alpha: brightness == Brightness.light ? 0.15 : 0.25,
        ),
        iconColor: brightness == Brightness.light
            ? neutral700
            : neutral000.withValues(alpha: 0.7),
        textColor: brightness == Brightness.light ? neutral900 : neutral000,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: brightness == Brightness.light
            ? neutral000
            : neutral850,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
        ),
        elevation: 8.0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: brand100,
        unselectedLabelColor: brightness == Brightness.light
            ? neutral700
            : neutral000.withValues(alpha: 0.6),
        indicatorColor: brand100,
        labelStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w600,
          fontSize: 12.0,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
          fontSize: 12.0,
        ),
      ),
    );
  }

  static ThemeData lightTheme(BuildContext context) {
    return baseTheme(context, Brightness.light).copyWith(
      scaffoldBackgroundColor: neutral000,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brand100,
        brightness: Brightness.light,
        primary: brand100,
        secondary: brand200,
        tertiary: neutral100,
        error: error500,
        surface: neutral000,
        onSurface: neutral900,
        onPrimary: neutral000,
        onSecondary: neutral000,
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: brand100.withValues(alpha: 0.3),
        cursorColor: brand100,
        selectionHandleColor: brand100,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: neutral000,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: neutral300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: neutral300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: brand100, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: error500),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: error500, width: 2.0),
        ),
        hintStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
          color: neutral500,
        ),
        labelStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
          color: neutral500,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: neutral000,
        foregroundColor: neutral900,
        elevation: 0.0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
          color: neutral900,
          fontSize: 20.0,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: neutral000,
        elevation: 0.0,
        indicatorColor: brand100.withValues(alpha: 0.2),
        labelType: NavigationRailLabelType.all,
        selectedIconTheme: IconThemeData(color: brand100),
        unselectedIconTheme: IconThemeData(color: neutral700),
        selectedLabelTextStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
          color: brand100,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
          color: neutral700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: neutral000,
        elevation: 0.0,
        indicatorColor: brand100.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontFamily: 'SF Pro',
            fontWeight: FontWeight.w500,
            color: neutral700,
          ),
        ),
        iconTheme: WidgetStateProperty.all(IconThemeData(color: brand100)),
      ),
    );
  }

  static ThemeData darkTheme(BuildContext context) {
    return baseTheme(context, Brightness.dark).copyWith(
      scaffoldBackgroundColor: neutral800,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brand100,
        brightness: Brightness.dark,
        primary: brand100,
        secondary: brand200,
        tertiary: neutral100,
        error: error500,
        surface: neutral850,
        onSurface: neutral000,
        onPrimary: neutral000,
        onSecondary: neutral000,
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: brand100.withValues(alpha: 0.4),
        cursorColor: brand100,
        selectionHandleColor: brand100,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: neutral850,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: neutral700.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: neutral700.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: brand100, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: error500),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: error500, width: 2.0),
        ),
        hintStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
          color: neutral000.withValues(alpha: 0.5),
        ),
        labelStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
          color: neutral000.withValues(alpha: 0.7),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: neutral800,
        foregroundColor: neutral000,
        elevation: 0.0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
          color: neutral000,
          fontSize: 20.0,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: neutral850,
        elevation: 0.0,
        indicatorColor: brand100.withValues(alpha: 0.3),
        labelType: NavigationRailLabelType.all,
        selectedIconTheme: IconThemeData(color: brand100),
        unselectedIconTheme: IconThemeData(
          color: neutral000.withValues(alpha: 0.6),
        ),
        selectedLabelTextStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w500,
          color: brand100,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: 'SF Pro',
          fontWeight: FontWeight.w400,
          color: neutral000.withValues(alpha: 0.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        indicatorColor: brand100.withValues(alpha: 0.3),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontFamily: 'SF Pro',
            fontWeight: FontWeight.w500,
            color: neutral000.withValues(alpha: 0.7),
          ),
        ),
        iconTheme: WidgetStateProperty.all(IconThemeData(color: brand100)),
      ),
    );
  }
}
