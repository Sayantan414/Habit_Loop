import 'package:flutter/material.dart';

/// Raw brand values for the Habit Loop design system.
///
/// Nothing in the UI should reference these directly — read the resolved
/// tokens from [AppPalette.of] instead, so every widget stays theme aware.
abstract final class AppColors {
  // ---------------------------------------------------------------- dark mode
  /// Midnight canvas. Deep enough to read as "OLED black" while keeping the
  /// slate-blue cast that holds the accent hues vivid without any bloom.
  static const darkCanvas = Color(0xFF0F172A);
  static const darkCanvasTop = Color(0xFF131E36);
  static const darkCanvasBottom = Color(0xFF080D19);
  static const darkSurface = Color(0xFF16213A);
  static const darkSurfaceHigh = Color(0xFF1E2B47);
  static const darkStroke = Color(0x1AFFFFFF); // white @ 10%
  static const darkStrokeStrong = Color(0x33FFFFFF); // white @ 20%
  static const darkTextPrimary = Color(0xFFF1F5F9);
  static const darkTextSecondary = Color(0xFF94A3B8);
  static const darkTextTertiary = Color(0xFF64748B);

  static const darkAccent = Color(0xFF06B6D4); // eye-comfortable cyan
  static const darkAccentAlt = Color(0xFF8B5CF6); // eye-comfortable violet
  static const darkSuccess = Color(0xFF10B981); // eye-comfortable emerald
  static const darkWarning = Color(0xFFF59E0B); // eye-comfortable amber
  static const darkDanger = Color(0xFFF43F5E); // eye-comfortable rose

  // --------------------------------------------------------------- light mode
  /// Porcelain canvas — warm enough not to glare, cool enough to stay crisp.
  static const lightCanvas = Color(0xFFF8FAFC);
  static const lightCanvasTop = Color(0xFFFFFFFF);
  static const lightCanvasBottom = Color(0xFFEEF2F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceHigh = Color(0xFFF1F5F9);
  static const lightStroke = Color(0xFFE2E8F0);
  static const lightStrokeStrong = Color(0xFFCBD5E1);
  static const lightTextPrimary = Color(0xFF0F172A);
  static const lightTextSecondary = Color(0xFF475569);
  static const lightTextTertiary = Color(0xFF94A3B8);

  static const lightAccent = Color(0xFF0891B2); // deep cyan
  static const lightAccentAlt = Color(0xFF7C3AED); // deep violet
  static const lightSuccess = Color(0xFF059669); // deep emerald
  static const lightWarning = Color(0xFFD97706); // deep amber
  static const lightDanger = Color(0xFFE11D48); // deep rose
}

/// A habit accent, expressed once per theme so the same habit reads as a
/// bright hue on midnight and a solid, high-contrast one on porcelain.
@immutable
class AccentSwatch {
  const AccentSwatch(this.name, this.light, this.dark);

  final String name;
  final Color light;
  final Color dark;

  /// The value persisted on [Habit.colorValue]. The dark tone is the
  /// canonical id so existing exports stay stable across theme changes.
  int get id => dark.toARGB32();
}

abstract final class AppAccents {
  static const swatches = <AccentSwatch>[
    AccentSwatch('Cyan', Color(0xFF0891B2), Color(0xFF06B6D4)),
    AccentSwatch('Emerald', Color(0xFF059669), Color(0xFF10B981)),
    AccentSwatch('Violet', Color(0xFF7C3AED), Color(0xFF8B5CF6)),
    AccentSwatch('Amber', Color(0xFFD97706), Color(0xFFF59E0B)),
    AccentSwatch('Rose', Color(0xFFE11D48), Color(0xFFF43F5E)),
    AccentSwatch('Sky', Color(0xFF2563EB), Color(0xFF3B82F6)),
    AccentSwatch('Lime', Color(0xFF65A30D), Color(0xFF84CC16)),
    AccentSwatch('Orange', Color(0xFFEA580C), Color(0xFFF97316)),
  ];

  /// Maps a stored ARGB value onto the tone that belongs to [brightness].
  ///
  /// Habits created before the palette existed keep working: an unknown value
  /// is nudged lighter on midnight and deeper on porcelain so contrast holds.
  static Color resolve(int stored, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    for (final swatch in swatches) {
      if (swatch.dark.toARGB32() == stored || swatch.light.toARGB32() == stored) {
        return isDark ? swatch.dark : swatch.light;
      }
    }
    final raw = Color(stored);
    return isDark
        ? Color.lerp(raw, Colors.white, 0.18) ?? raw
        : Color.lerp(raw, Colors.black, 0.12) ?? raw;
  }

  static Color of(BuildContext context, int stored) =>
      resolve(stored, Theme.of(context).brightness);
}

/// Every semantic color the app draws with, resolved for the active theme.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.isDark,
    required this.canvas,
    required this.canvasTop,
    required this.canvasBottom,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceGlass,
    required this.surfaceGlassHi,
    required this.navGlass,
    required this.stroke,
    required this.strokeStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentAlt,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
  });

  final bool isDark;

  /// Page background, plus the two stops of the ambient wash behind it.
  final Color canvas;
  final Color canvasTop;
  final Color canvasBottom;

  /// Opaque card fills.
  final Color surface;
  final Color surfaceHigh;

  /// Translucent glass fills — [surfaceGlassHi] is the top of the gradient.
  final Color surfaceGlass;
  final Color surfaceGlassHi;

  /// Fill behind the floating bottom navigation bar (sits over a blur).
  final Color navGlass;

  final Color stroke;
  final Color strokeStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color accent;
  final Color accentAlt;
  final Color success;
  final Color warning;
  final Color danger;

  /// Base shadow color — already carries its own opacity.
  final Color shadow;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? dark;

  static const dark = AppPalette(
    isDark: true,
    canvas: AppColors.darkCanvas,
    canvasTop: AppColors.darkCanvasTop,
    canvasBottom: AppColors.darkCanvasBottom,
    surface: AppColors.darkSurface,
    surfaceHigh: AppColors.darkSurfaceHigh,
    surfaceGlass: Color(0x0DFFFFFF), // white @ 5%
    surfaceGlassHi: Color(0x1AFFFFFF), // white @ 10%
    navGlass: Color(0xCC16213A),
    stroke: AppColors.darkStroke,
    strokeStrong: AppColors.darkStrokeStrong,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    accent: AppColors.darkAccent,
    accentAlt: AppColors.darkAccentAlt,
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    danger: AppColors.darkDanger,
    shadow: Color(0x66000000),
  );

  static const light = AppPalette(
    isDark: false,
    canvas: AppColors.lightCanvas,
    canvasTop: AppColors.lightCanvasTop,
    canvasBottom: AppColors.lightCanvasBottom,
    surface: AppColors.lightSurface,
    surfaceHigh: AppColors.lightSurfaceHigh,
    surfaceGlass: Color(0xF2FFFFFF),
    surfaceGlassHi: Color(0xFFFFFFFF),
    navGlass: Color(0xF2FFFFFF),
    stroke: AppColors.lightStroke,
    strokeStrong: AppColors.lightStrokeStrong,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    accent: AppColors.lightAccent,
    accentAlt: AppColors.lightAccentAlt,
    success: AppColors.lightSuccess,
    warning: AppColors.lightWarning,
    danger: AppColors.lightDanger,
    shadow: Color(0x140F172A),
  );

  @override
  AppPalette copyWith({Color? accent, Color? canvas}) {
    return AppPalette(
      isDark: isDark,
      canvas: canvas ?? this.canvas,
      canvasTop: canvasTop,
      canvasBottom: canvasBottom,
      surface: surface,
      surfaceHigh: surfaceHigh,
      surfaceGlass: surfaceGlass,
      surfaceGlassHi: surfaceGlassHi,
      navGlass: navGlass,
      stroke: stroke,
      strokeStrong: strokeStrong,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textTertiary: textTertiary,
      accent: accent ?? this.accent,
      accentAlt: accentAlt,
      success: success,
      warning: warning,
      danger: danger,
      shadow: shadow,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return AppPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      canvas: c(canvas, other.canvas),
      canvasTop: c(canvasTop, other.canvasTop),
      canvasBottom: c(canvasBottom, other.canvasBottom),
      surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      surfaceGlass: c(surfaceGlass, other.surfaceGlass),
      surfaceGlassHi: c(surfaceGlassHi, other.surfaceGlassHi),
      navGlass: c(navGlass, other.navGlass),
      stroke: c(stroke, other.stroke),
      strokeStrong: c(strokeStrong, other.strokeStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      accent: c(accent, other.accent),
      accentAlt: c(accentAlt, other.accentAlt),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      shadow: c(shadow, other.shadow),
    );
  }
}
