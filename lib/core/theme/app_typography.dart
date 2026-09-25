import 'package:flutter/material.dart';

/// Type system: Outfit for display/headings (geometric, confident), Inter for
/// UI and body copy (tall x-height, excellent at 12–15px on device).
abstract final class AppTypography {
  static const display = 'Outfit';
  static const text = 'Inter';

  /// Tabular figures keep counters and percentages from jittering as they
  /// animate. Outfit ships proportional digits, so numerals that tick get
  /// this feature applied explicitly.
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];

  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
  }) {
    return TextTheme(
      // Display — Outfit, hero numbers and celebration headlines.
      displayLarge: TextStyle(
        fontFamily: display,
        fontSize: 40,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        color: primary,
      ),
      displayMedium: TextStyle(
        fontFamily: display,
        fontSize: 32,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: primary,
      ),
      displaySmall: TextStyle(
        fontFamily: display,
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: primary,
      ),

      // Headline — Outfit, screen and section titles.
      headlineLarge: TextStyle(
        fontFamily: display,
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontFamily: display,
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontFamily: display,
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: primary,
      ),

      // Title — Inter, card titles and list rows.
      titleLarge: TextStyle(
        fontFamily: text,
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontFamily: text,
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontFamily: text,
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: primary,
      ),

      // Body — Inter.
      bodyLarge: TextStyle(
        fontFamily: text,
        fontSize: 16,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontFamily: text,
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      bodySmall: TextStyle(
        fontFamily: text,
        fontSize: 12.5,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),

      // Label — Inter, chips, buttons, overlines.
      labelLarge: TextStyle(
        fontFamily: text,
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontFamily: text,
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: secondary,
      ),
      labelSmall: TextStyle(
        fontFamily: text,
        fontSize: 10.5,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: secondary,
      ),
    );
  }
}

/// Geometry, motion and elevation constants shared by every screen.
abstract final class AppTokens {
  // Spacing scale (4pt base).
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space8 = 32.0;

  /// Horizontal gutter used by every scrollable screen.
  static const gutter = 20.0;

  /// Bottom padding that keeps content clear of the floating nav bar.
  static const navClearance = 118.0;

  // Corner radii.
  static const radiusSm = 12.0;
  static const radiusMd = 18.0;
  static const radiusLg = 24.0;
  static const radiusXl = 32.0;
  static const radiusPill = 999.0;

  // Motion.
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const celebrate = Duration(milliseconds: 1600);

  static const emphasized = Curves.easeOutCubic;
  static const springy = Curves.easeOutBack;
}
