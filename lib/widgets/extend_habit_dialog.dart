import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme/app_theme.dart';
import '../data/models/habit.dart';

/// Opens a dialog allowing the user to extend a completed (or active) habit challenge.
Future<void> showExtendHabitDialog(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
) async {
  int additionalDays = 21;
  final customController = TextEditingController(text: '21');
  bool isCustom = false;

  final success = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        final p = AppPalette.of(ctx);
        final theme = Theme.of(ctx);
        final color = AppAccents.of(ctx, habit.colorValue);
        final presets = [7, 14, 21, 30];

        return AlertDialog(
          backgroundColor: p.isDark ? p.surface : p.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          ),
          title: Row(
            children: [
              Icon(Icons.more_time_rounded, color: color),
              const SizedBox(width: 10),
              Text(
                'Extend Challenge',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add extra days to "${habit.title}" and keep your momentum going!',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppTokens.space4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final days in presets)
                      FilterChip(
                        label: Text('+$days Days'),
                        selected: !isCustom && additionalDays == days,
                        selectedColor: color.withValues(alpha: 0.2),
                        checkmarkColor: color,
                        onSelected: (_) {
                          setState(() {
                            isCustom = false;
                            additionalDays = days;
                          });
                        },
                      ),
                    FilterChip(
                      label: const Text('Custom'),
                      selected: isCustom,
                      selectedColor: color.withValues(alpha: 0.2),
                      checkmarkColor: color,
                      onSelected: (_) {
                        setState(() {
                          isCustom = true;
                        });
                      },
                    ),
                  ],
                ),
                if (isCustom) ...[
                  const SizedBox(height: AppTokens.space3),
                  TextField(
                    controller: customController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Number of extra days (1–365)',
                      prefixIcon: Icon(Icons.add_rounded, size: 18),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: () async {
                int add = additionalDays;
                if (isCustom) {
                  final parsed = int.tryParse(customController.text.trim());
                  if (parsed == null || parsed < 1 || parsed > 365) return;
                  add = parsed;
                }
                habit.totalDays += add;
                await ref.read(habitsProvider.notifier).updateHabit(habit);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Extend Challenge'),
            ),
          ],
        );
      },
    ),
  );

  if (success == true && context.mounted) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Challenge extended! "${habit.title}" is back on your Today dashboard.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
