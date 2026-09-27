import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass_card.dart';

/// SUB-SCREEN — Notification Sound & Vibration Settings.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    final vibrationEnabled = ref.watch(vibrationEnabledProvider);
    final vibrationMode = ref.watch(vibrationModeProvider);
    final soundEnabled = ref.watch(notificationSoundEnabledProvider);
    final notificationSound = ref.watch(notificationSoundProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Sound & Vibration'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.gutter),
          children: [
            // ------------------------------------------------ Vibration Card
            Text('Vibration', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTokens.space2),
            GlassCard(
              padding: const EdgeInsets.all(AppTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.vibration_rounded,
                          color: p.accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vibration',
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              'Vibrate on habit reminder alerts',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: vibrationEnabled,
                        onChanged: (val) async {
                          HapticFeedback.selectionClick();
                          await ref
                              .read(vibrationEnabledProvider.notifier)
                              .setEnabled(val);
                          if (val) {
                            await HapticFeedback.vibrate();
                            await NotificationService.instance
                                .showPreviewNotification(
                                  sound: notificationSound,
                                  vibrationMode: vibrationMode,
                                );
                          }
                        },
                      ),
                    ],
                  ),
                  if (vibrationEnabled) ...[
                    const SizedBox(height: AppTokens.space4),
                    const Divider(height: 1),
                    const SizedBox(height: AppTokens.space4),
                    Text(
                      'Vibration Pattern (Tap to test)',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space3),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: 'subtle',
                            label: Text('Subtle'),
                            icon: Icon(Icons.graphic_eq_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: 'pulse',
                            label: Text('Pulse'),
                            icon: Icon(Icons.waves_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: 'strong',
                            label: Text('Strong'),
                            icon: Icon(Icons.bolt_rounded, size: 16),
                          ),
                        ],
                        selected: {vibrationMode},
                        onSelectionChanged: (selection) async {
                          final mode = selection.first;
                          await ref
                              .read(vibrationModeProvider.notifier)
                              .setMode(mode);

                          // Trigger live vibration pattern feedback
                          if (mode == 'subtle') {
                            await HapticFeedback.vibrate();
                          } else if (mode == 'pulse') {
                            await HapticFeedback.vibrate();
                            await Future<void>.delayed(
                              const Duration(milliseconds: 150),
                            );
                            await HapticFeedback.vibrate();
                          } else if (mode == 'strong') {
                            await HapticFeedback.vibrate();
                            await Future<void>.delayed(
                              const Duration(milliseconds: 150),
                            );
                            await HapticFeedback.vibrate();
                            await Future<void>.delayed(
                              const Duration(milliseconds: 150),
                            );
                            await HapticFeedback.vibrate();
                          }

                          await NotificationService.instance
                              .showPreviewNotification(
                                sound: notificationSound,
                                vibrationMode: mode,
                              );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppTokens.space6),

            // ------------------------------------------------ Notification Sound Card
            Text('Notification Sound', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTokens.space2),
            GlassCard(
              padding: const EdgeInsets.all(AppTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: p.accentAlt.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.notifications_active_rounded,
                          color: p.accentAlt,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notification Sound',
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              'Play sound on habit reminders',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: soundEnabled,
                        onChanged: (val) async {
                          HapticFeedback.selectionClick();
                          await ref
                              .read(notificationSoundEnabledProvider.notifier)
                              .setEnabled(val);
                          if (val) {
                            await NotificationService.instance
                                .showPreviewNotification(
                                  sound: notificationSound,
                                  vibrationMode: vibrationMode,
                                );
                          }
                        },
                      ),
                    ],
                  ),
                  if (soundEnabled) ...[
                    const SizedBox(height: AppTokens.space4),
                    const Divider(height: 1),
                    const SizedBox(height: AppTokens.space4),
                    Text(
                      'Global Sound (Tap to test sound)',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space3),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: 'chime',
                            label: Text('Chime'),
                            icon: Icon(Icons.music_note_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: 'bell',
                            label: Text('Bell'),
                            icon: Icon(
                              Icons.notifications_none_rounded,
                              size: 16,
                            ),
                          ),
                          ButtonSegment(
                            value: 'zen',
                            label: Text('Zen'),
                            icon: Icon(Icons.spa_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: 'system',
                            label: Text('System'),
                            icon: Icon(
                              Icons.settings_system_daydream_rounded,
                              size: 16,
                            ),
                          ),
                        ],
                        selected: {notificationSound},
                        onSelectionChanged: (selection) async {
                          final selectedSound = selection.first;
                          HapticFeedback.selectionClick();
                          await ref
                              .read(notificationSoundProvider.notifier)
                              .setSound(selectedSound);
                          await NotificationService.instance
                              .showPreviewNotification(
                                sound: selectedSound,
                                vibrationMode: vibrationMode,
                              );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
