import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Animated circular progress ring.
///
/// The arc is one solid accent — no hue travelling around the sweep. The value
/// animates from wherever it was, so checking a habit in makes the ring travel
/// rather than jump: the single most satisfying motion in the app.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 108,
    this.stroke = 11,
    this.color,
    this.trackColor,
    this.child,
    this.duration = AppTokens.slow,
  });

  /// 0..1.
  final double value;
  final double size;
  final double stroke;

  /// Arc color. Defaults to the theme accent.
  final Color? color;
  final Color? trackColor;
  final Widget? child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final arc = color ?? p.accent;

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: duration,
        curve: AppTokens.emphasized,
        builder: (context, animated, _) {
          return CustomPaint(
            painter: _RingPainter(
              value: animated,
              stroke: stroke,
              color: arc,
              track: trackColor ??
                  (p.isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : p.strokeStrong.withValues(alpha: 0.45)),
            ),
            child: Center(child: child),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.color,
    required this.track,
  });

  final double value;
  final double stroke;
  final Color color;
  final Color track;

  static const _start = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    if (value <= 0) return;
    final sweepAngle = 2 * math.pi * value;

    canvas.drawArc(
      arcRect,
      _start,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      old.track != track ||
      old.color != color;
}

/// Slim progress bar used inside habit cards — a solid accent fill over a
/// neutral track.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
    this.trackColor,
  });

  final double value;
  final Color color;
  final double height;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final track = trackColor ??
        (p.isDark
            ? Colors.white.withValues(alpha: 0.08)
            : color.withValues(alpha: 0.12));

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
              duration: AppTokens.slow,
              curve: AppTokens.emphasized,
              builder: (context, animated, _) => FractionallySizedBox(
                widthFactor: animated == 0 ? 0.0001 : animated,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
