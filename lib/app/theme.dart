import 'package:flutter/material.dart';

/// Billy App Theme tokens and configuration.
/// Design philosophy:
/// - BLACK + WHITE + TYPOGRAPHY + LINES
/// - Highly editorial, brutalist, minimal and intentional
/// - No gradients, no soft multi-layer drop shadows, no bright accent colors
abstract class BillyTheme {
  // --- Color Palette ---
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color grayDark = Color(0xFF222222);
  static const Color grayMedium = Color(0xFF757575);
  static const Color grayLight = Color(0xFFE5E5E5);
  static const Color grayExtraLight = Color(0xFFF6F6F6);

  // Background and Surface
  static const Color background = white;
  static const Color surface = white;
  static const Color textPrimary = black;
  static const Color textSecondary = grayMedium;
  static const Color border = black;
  static const Color borderSubtle = grayLight;

  // --- Spacing Tokens ---
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space48 = 48.0;
  static const double space64 = 64.0;

  // --- Border Widths ---
  static const double borderWidthThin = 1.0;
  static const double borderWidthMedium = 1.5;
  static const double borderWidthBold = 2.0;

  // --- Typography ---
  static const TextStyle brandHeader = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w800,
    letterSpacing: 4.0,
    color: textPrimary,
    height: 1.0,
  );

  static const TextStyle heroHeadline = TextStyle(
    fontSize: 48.0,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.5,
    color: textPrimary,
    height: 0.95,
  );

  static const TextStyle heroHeadlineCompact = TextStyle(
    fontSize: 38.0,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.0,
    color: textPrimary,
    height: 1.0,
  );

  static const TextStyle bodySubhead = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.5,
    color: textSecondary,
    height: 1.4,
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w800,
    letterSpacing: 3.0,
    color: white,
    height: 1.0,
  );

  static const TextStyle footerText = TextStyle(
    fontSize: 10.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
    color: textSecondary,
  );

  /// Centralized ThemeData for Billy the Viewer
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      primaryColor: black,
      splashColor: Colors.transparent,
      highlightColor: grayLight.withValues(alpha: 0.2),
      fontFamily: null, // System modern sans-serif
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: black,
        onPrimary: white,
        secondary: black,
        onSecondary: white,
        error: black,
        onError: white,
        surface: surface,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: black,
          foregroundColor: white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: space32,
            vertical: space24,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: black,
          side: const BorderSide(color: black, width: borderWidthMedium),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: space32,
            vertical: space24,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: black,
        thickness: borderWidthThin,
        space: borderWidthThin,
      ),
    );
  }
}
