import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// One-shot celebration burst, drawn straight into the app overlay.
///
/// Hand-rolled rather than pulled from a package so it can borrow the theme's
/// accent colors and stay a single `CustomPaint` — ~90 rectangles on one
/// ticker, removed from the tree the moment it finishes.
abstract final class Confetti {
  static bool _running = false;

  static void burst(BuildContext context, {List<Color>? colors}) {
    if (_running) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final p = AppPalette.of(context);
    final palette = colors ??
        [p.accent, p.accentAlt, p.success, p.warning, p.danger];

    _running = true;
    HapticFeedback.mediumImpact();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: _ConfettiLayer(
          colors: palette,
          onDone: () {
            entry.remove();
            _running = false;
          },
        ),
      ),
    );
    overlay.insert(entry);
  }
}

class _ConfettiLayer extends StatefulWidget {
  const _ConfettiLayer({required this.colors, required this.onDone});

  final List<Color> colors;
  final VoidCallback onDone;

  @override
  State<_ConfettiLayer> createState() => _ConfettiLayerState();
}

class _ConfettiLayerState extends State<_ConfettiLayer>
    with SingleTickerProviderStateMixin {
  static const _count = 90;

  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final random = math.Random();
    _particles = List.generate(
      _count,
      (i) => _Particle.random(random, widget.colors[i % widget.colors.length]),
    );
    _controller = AnimationController(
      vsync: this,
      duration: AppTokens.celebrate,
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(
          particles: _particles,
          animation: _controller,
        ),
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.vx,
    required this.vy,
    required this.size,
    required this.spin,
    required this.color,
    required this.delay,
  });

  /// Horizontal launch position as a fraction of screen width.
  final double x;
  final double vx;
  final double vy;
  final double size;
  final double spin;
  final Color color;
  final double delay;

  factory _Particle.random(math.Random r, Color color) {
    return _Particle(
      // Launch from a wide band across the upper third of the screen.
      x: 0.08 + r.nextDouble() * 0.84,
      vx: (r.nextDouble() - 0.5) * 0.55,
      vy: 0.35 + r.nextDouble() * 0.55,
      size: 5 + r.nextDouble() * 7,
      spin: (r.nextDouble() - 0.5) * 14,
      color: color,
      delay: r.nextDouble() * 0.22,
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.animation})
      : super(repaint: animation);

  final List<_Particle> particles;
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (final particle in particles) {
      final t = ((animation.value - particle.delay) / (1 - particle.delay))
          .clamp(0.0, 1.0);
      if (t <= 0) continue;

      // Launch upward, then fall under gravity.
      final dy = (-particle.vy * t + 1.35 * t * t) * size.height;
      final dx = particle.vx * t * size.width;
      final opacity = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);

      final cx = particle.x * size.width + dx;
      final cy = size.height * 0.32 + dy;
      if (cy > size.height + 40) continue;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(particle.spin * t);
      paint.color = particle.color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size,
            height: particle.size * 1.7,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => false;
}
