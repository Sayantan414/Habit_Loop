import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The ambient canvas behind every screen.
///
/// A quiet three-stop vertical wash — slightly lifted at the top, settling
/// darker (or cooler, in light mode) at the bottom. Deliberately achromatic:
/// no accent-tinted light bleed, so large empty areas read as calm rather than
/// lit from somewhere off-screen.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.canvasTop, p.canvas, p.canvasBottom],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: child,
    );
  }
}
