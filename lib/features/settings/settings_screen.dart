import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import 'manage_habits_screen.dart';

/// SCREEN 6 — Settings and data backup.
///
/// Grouped glass panels instead of a flat list: appearance, feedback, habits,
/// then the data tools. Destructive-adjacent actions (import, raw JSON) are
/// last and visually cooler than the rest.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.gutter,
          AppTokens.space2,
          AppTokens.gutter,
          AppTokens.navClearance,
        ),
        children: [
          Text('Settings', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 2),
          Text('Make the loop yours.', style: theme.textTheme.bodySmall),
          const SizedBox(height: AppTokens.space5),

          const SectionHeader(title: 'Appearance'),
          GlassCard(
            padding: const EdgeInsets.all(AppTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _RowIcon(icon: Icons.palette_rounded, color: p.accentAlt),
                    const SizedBox(width: AppTokens.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Theme', style: theme.textTheme.titleMedium),
                          Text(
                            'Midnight glass or porcelain light.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.space4),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_rounded, size: 17),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_rounded, size: 17),
                        label: Text('Dark'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_rounded, size: 17),
                        label: Text('System'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (selection) {
                      HapticFeedback.selectionClick();
                      ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(selection.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space5),



          const SectionHeader(title: 'Habits'),
          GlassCard(
            padding: EdgeInsets.zero,
            child: _SettingsRow(
              icon: Icons.tune_rounded,
              color: p.accent,
              title: 'Manage habits',
              subtitle: 'Rename, retarget, recolor or delete',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManageHabitsScreen()),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.space5),

          const SectionHeader(title: 'Data backup & restore'),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsRow(
                  icon: Icons.ios_share_rounded,
                  color: p.success,
                  title: 'Export JSON file',
                  subtitle: 'Habits, to-dos and notes → Habit Loop / Backup',
                  onTap: () => _export(context, ref),
                ),
                _Divider(),
                _SettingsRow(
                  icon: Icons.download_rounded,
                  color: p.accent,
                  title: 'Import JSON file',
                  subtitle: 'Restore everything from a backup file',
                  onTap: () => _import(context, ref),
                ),
                _Divider(),
                _SettingsRow(
                  icon: Icons.data_object_rounded,
                  color: p.textSecondary,
                  title: 'View raw JSON',
                  subtitle: 'Inspect or copy the data by hand',
                  onTap: () => _viewRaw(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space6),

          Center(
            child: Column(
              children: [
                Icon(Icons.loop_rounded, size: 22, color: p.textTertiary),
                const SizedBox(height: AppTokens.space2),
                Text(
                  'Habit Loop',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: p.textSecondary),
                ),
                Text(
                  'Build your streaks, one day at a time.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- data tools

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final backupService = ref.read(backupServiceProvider);
      final savedPath =
          await ref.read(habitsProvider.notifier).exportBackupToFile(backupService);
      if (savedPath == null || !context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: AppPalette.of(ctx).success, size: 22),
              const SizedBox(width: 10),
              const Text('Backup saved'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your backup file was written to:'),
              const SizedBox(height: AppTokens.space2),
              SelectableText(
                savedPath,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppPalette.of(ctx).textPrimary,
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: savedPath));
                messenger.showSnackBar(
                  const SnackBar(content: Text('File path copied')),
                );
              },
              child: const Text('Copy path'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final backupService = ref.read(backupServiceProvider);
      final files = await backupService.getAvailableBackupFiles();

      if (files.isEmpty) {
        final restored = await ref
            .read(habitsProvider.notifier)
            .importBackupFromFile(backupService);
        if (restored) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Backup restored 🎉')),
          );
        }
        return;
      }

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select a backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Found in Habit Loop / Backup:',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: AppTokens.space3),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (context, i) {
                      final file = files[i];
                      final name = file.path.split(RegExp(r'[/\\]')).last;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.description_outlined,
                          color: AppPalette.of(ctx).accent,
                        ),
                        title: Text(
                          name,
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                        trailing: const Text('Restore'),
                        onTap: () async {
                          final content =
                              await backupService.readJsonFromFile(file);
                          if (content == null || content.isEmpty) return;
                          await ref
                              .read(habitsProvider.notifier)
                              .importJson(content);
                          if (ctx.mounted) Navigator.pop(ctx);
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Backup restored 🎉')),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final restored = await ref
                    .read(habitsProvider.notifier)
                    .importBackupFromFile(backupService);
                if (restored) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Backup restored 🎉')),
                  );
                }
              },
              child: const Text('Browse files…'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  void _viewRaw(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    final jsonStr = ref.read(habitsProvider.notifier).exportJson();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raw data'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonStr,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.45,
                color: AppPalette.of(ctx).textSecondary,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(ctx);
              messenger.showSnackBar(
                const SnackBar(content: Text('JSON copied to clipboard')),
              );
            },
            child: const Text('Copy JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space4),
        child: Row(
          children: [
            _RowIcon(icon: icon, color: color),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 1),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: p.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space4),
      child: Divider(height: 1, color: AppPalette.of(context).stroke),
    );
  }
}
