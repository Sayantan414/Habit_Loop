import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'pressable.dart';

/// The app's primary surface.
///
/// Dark mode renders true glassmorphism — a translucent white gradient over
/// the midnight canvas with a 1px light rim and a deep ambient shadow. Light
/// mode swaps to a solid porcelain card with a soft elevated shadow, because
/// frosted glass over a near-white background reads as mud.
///
/// Real backdrop blur is reserved for pinned chrome (see [GlassBlur]); list
/// cards simulate it, since a `BackdropFilter` per row is expensive to scroll.
///
/// Shadows are neutral elevation only. Emphasis comes from rim color and
/// weight — nothing in this app emits a colored glow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = AppTokens.radiusLg,
    this.onTap,
    this.onLongPress,
    this.accent,
    this.highlighted = false,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Tints the rim — pass the habit's accent to color the card.
  final Color? accent;

  /// Draws the rim in [accent] at full strength (used for "done today").
  final bool highlighted;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final tint = accent ?? p.accent;
    final border = BorderRadius.circular(radius);

    final decoration = BoxDecoration(
      borderRadius: border,
      color: p.isDark ? null : p.surface,
      gradient: p.isDark
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.surfaceGlassHi, p.surfaceGlass],
            )
          : null,
      border: Border.all(
        color: highlighted ? tint.withValues(alpha: 0.55) : p.stroke,
        width: highlighted ? 1.4 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: p.shadow,
          blurRadius: p.isDark ? 28 : 20,
          offset: const Offset(0, 10),
          spreadRadius: p.isDark ? -8 : -6,
        ),
      ],
    );

    final body = DecoratedBox(
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: border,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: border,
          splashColor: tint.withValues(alpha: 0.08),
          highlightColor: tint.withValues(alpha: 0.04),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    final wrapped = onTap == null && onLongPress == null
        ? body
        : Pressable(onTap: onTap, onLongPress: onLongPress, child: body);

    return margin == null ? wrapped : Padding(padding: margin!, child: wrapped);
  }
}

/// Real frosted glass — blurs whatever scrolls beneath it.
///
/// Reserved for pinned chrome (the floating nav bar, sticky headers) where one
/// blur layer is cheap and the depth cue actually matters.
class GlassBlur extends StatelessWidget {
  const GlassBlur({
    super.key,
    required this.child,
    this.radius = AppTokens.radiusPill,
    this.sigma = 22,
  });

  final Widget child;
  final double radius;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}

/// Small pill used for streaks, counts, day ranges and status.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.icon,
    this.emoji,
    this.color,
    this.strong = false,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final String? emoji;
  final Color? color;

  /// Solid fill instead of a tinted wash.
  final bool strong;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final tint = color ?? p.accent;
    final fg = strong ? (p.isDark ? p.canvas : Colors.white) : tint;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: strong ? tint : tint.withValues(alpha: p.isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: strong
            ? null
            : Border.all(color: tint.withValues(alpha: p.isDark ? 0.3 : 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null) ...[
            Text(emoji!, style: TextStyle(fontSize: dense ? 10 : 11)),
            const SizedBox(width: 4),
          ] else if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg,
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w700,
              fontFeatures: AppTypography.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section label with an optional count badge and trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.color,
  });

  final String title;
  final int? count;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final tint = color ?? p.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space3),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: p.textTertiary),
          ),
          if (count != null) ...[
            const SizedBox(width: AppTokens.space2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: p.isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tint,
                  letterSpacing: 0,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
