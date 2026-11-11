import 'package:flutter/material.dart';

abstract final class VioraColors {
  static const violet = Color(0xFF7B61FF);
  static const violetSoft = Color(0xFFA99BFF);
  static const cyan = Color(0xFF3EE7E0);
  static const pink = Color(0xFFFF6FD8);
  static const danger = Color(0xFFFF5C7A);

  static const ink = Color(0xFF07070D);
  static const surface = Color(0xFF11111B);
  static const surfaceHigh = Color(0xFF1B1B2A);
  static const outline = Color(0xFF2A2A3D);
  static const text = Color(0xFFEDEBFF);
  static const muted = Color(0xFF9D9BB8);

  static const paper = Color(0xFFF6F5FB);
  static const paperHigh = Color(0xFFFFFFFF);
  static const paperHighest = Color(0xFFEDEBF6);
  static const outlineLight = Color(0xFFDCD8EA);
  static const inkText = Color(0xFF15131F);
  static const inkMuted = Color(0xFF5E5A75);

  static const userBubble = LinearGradient(
    colors: [Color(0xFF7B61FF), Color(0xFF5B45E0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: VioraColors.violet,
    onPrimary: Colors.white,
    secondary: VioraColors.cyan,
    onSecondary: VioraColors.ink,
    tertiary: VioraColors.pink,
    onTertiary: Colors.white,
    error: VioraColors.danger,
    onError: Colors.white,
    surface: dark ? VioraColors.ink : VioraColors.paper,
    onSurface: dark ? VioraColors.text : VioraColors.inkText,
    onSurfaceVariant: dark ? VioraColors.muted : VioraColors.inkMuted,
    surfaceContainer: dark ? VioraColors.surface : VioraColors.paperHigh,
    surfaceContainerHigh: dark ? VioraColors.surfaceHigh : VioraColors.paperHighest,
    outline: dark ? VioraColors.outline : VioraColors.outlineLight,
    outlineVariant: dark ? VioraColors.outline : VioraColors.outlineLight,
  );

  TextStyle display(double size, [FontWeight weight = FontWeight.w700]) => TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontSize: size,
        fontWeight: weight,
        height: 1.15,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: scheme.surface,
  );

  // Component styles below replace (not merge) the text theme, so each names
  // its font; otherwise web falls back to Roboto, which isn't bundled.
  final radius = BorderRadius.circular(18);
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: display(34),
      headlineMedium: display(28),
      headlineSmall: display(22),
      titleLarge: display(20, FontWeight.w500),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: display(20, FontWeight.w500),
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: scheme.outline)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      hintStyle: TextStyle(fontFamily: 'Inter', color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      side: BorderSide(color: scheme.outline),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(fontFamily: 'Inter', color: scheme.onSurface, fontWeight: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? VioraColors.surfaceHigh : VioraColors.inkText,
      contentTextStyle: const TextStyle(fontFamily: 'Inter', color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outline, space: 1),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
