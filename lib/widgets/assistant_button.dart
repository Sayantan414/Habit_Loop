import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/assistant/assistant_screen.dart';
import 'pressable.dart';

/// The ✦ in the Today, To-Do and Notes headers that opens the assistant.
class AssistantButton extends StatelessWidget {
  const AssistantButton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return Semantics(
      button: true,
      label: 'Assistant',
      child: Pressable(
        onTap: () => AssistantScreen.open(context),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.isDark ? p.surfaceGlassHi : p.surface,
            border: Border.all(color: p.stroke),
          ),
          child: Icon(Icons.auto_awesome_rounded, size: 19, color: p.accentAlt),
        ),
      ),
    );
  }
}
