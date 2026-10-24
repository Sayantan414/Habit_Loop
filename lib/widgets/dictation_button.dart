import 'package:flutter/material.dart';

import '../core/services/speech_service.dart';
import '../core/theme/app_theme.dart';
import 'pressable.dart';

/// Language chip plus mic button for voice dictation.
///
/// The mic is a quiet glass circle at rest and turns solid with a slow
/// breathing ring while listening, so it's obvious the mic is live.
class DictationControls extends StatelessWidget {
  const DictationControls({
    super.key,
    required this.isListening,
    required this.localeId,
    required this.onMicTap,
    required this.onLocaleTap,
    this.onLocaleLongPress,
  });

  final bool isListening;
  final String localeId;
  final VoidCallback onMicTap;
  final VoidCallback onLocaleTap;

  /// Shows which speech recognizer is in use, for troubleshooting.
  final VoidCallback? onLocaleLongPress;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pressable(
          onTap: onLocaleTap,
          onLongPress: onLocaleLongPress,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              color: p.isDark ? p.surfaceGlassHi : p.surfaceHigh,
              border: Border.all(color: p.stroke),
            ),
            child: Text(
              dictationLocales[localeId] ?? localeId,
              style: theme.textTheme.labelMedium?.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.space2),
        Semantics(
          button: true,
          label: isListening ? 'Stop dictation' : 'Start dictation',
          child: Pressable(
            onTap: onMicTap,
            child: _MicCircle(isListening: isListening),
          ),
        ),
      ],
    );
  }
}

class _MicCircle extends StatefulWidget {
  const _MicCircle({required this.isListening});

  final bool isListening;

  @override
  State<_MicCircle> createState() => _MicCircleState();
}

class _MicCircleState extends State<_MicCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isListening) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_MicCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isListening && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final live = widget.isListening;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: live
                ? p.danger
                : (p.isDark ? p.surfaceGlassHi : p.surface),
            border: Border.all(color: live ? p.danger : p.stroke),
            boxShadow: [
              if (live)
                BoxShadow(
                  color: p.danger.withValues(alpha: 0.35),
                  blurRadius: 4 + 10 * _pulse.value,
                  spreadRadius: 1 + 3 * _pulse.value,
                ),
            ],
          ),
          child: child,
        );
      },
      child: AnimatedSwitcher(
        duration: AppTokens.fast,
        child: Icon(
          live ? Icons.stop_rounded : Icons.mic_none_rounded,
          key: ValueKey(live),
          size: 20,
          color: live ? Colors.white : p.textPrimary,
        ),
      ),
    );
  }
}
