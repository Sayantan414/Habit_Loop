import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'manage_habits_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final soundEnabled = ref.watch(soundEnabledProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Habits & Routines'),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Manage Habits'),
            subtitle: const Text('Edit titles, target days, color themes, or delete habits'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ManageHabitsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('System')),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) {
                ref.read(themeModeProvider.notifier).setThemeMode(selection.first);
              },
            ),
          ),
          const SizedBox(height: 8),
          _SectionHeader('Sound & haptics'),
          SwitchListTile(
            title: const Text('Check-in sound'),
            subtitle: const Text('Play a sound and vibration when you check off a habit'),
            value: soundEnabled,
            onChanged: (value) => ref.read(soundEnabledProvider.notifier).setEnabled(value),
          ),
          const SizedBox(height: 8),
          _SectionHeader('Data Backup & Restore (JSON)'),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Export JSON Backup File'),
            subtitle: const Text('Save full app backup (Habits, To-Dos & Notes) to Habit Loop > Backup'),
            onTap: () async {
              try {
                final backupService = ref.read(backupServiceProvider);
                final savedPath = await ref.read(habitsProvider.notifier).exportBackupToFile(backupService);
                if (savedPath != null && context.mounted) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                          SizedBox(width: 10),
                          Text('Backup Saved!'),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your backup JSON file has been saved to:'),
                          const SizedBox(height: 8),
                          SelectableText(
                            savedPath,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Keep this file safe in Habit Loop / Backup. It contains all your habits and to-do list items!',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: savedPath));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('File path copied to clipboard')),
                            );
                          },
                          child: const Text('Copy Path'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save file: $e')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('Import JSON Backup File'),
            subtitle: const Text('Pick a backup .json file to restore all habits and to-dos'),
            onTap: () async {
              try {
                final backupService = ref.read(backupServiceProvider);
                final autoFiles = await backupService.getAvailableBackupFiles();

                if (autoFiles.isNotEmpty && context.mounted) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.history_rounded, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Select Backup File'),
                        ],
                      ),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Found backup files in Habit Loop / Backup:',
                              style: TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            Flexible(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: autoFiles.length,
                                itemBuilder: (context, i) {
                                  final file = autoFiles[i];
                                  final basename = file.path.split(RegExp(r'[/\\]')).last;
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: const Icon(Icons.insert_drive_file_outlined),
                                      title: Text(basename, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      trailing: TextButton(
                                        child: const Text('Restore'),
                                        onPressed: () async {
                                          final content = await backupService.readJsonFromFile(file);
                                          if (content != null && content.isNotEmpty) {
                                            await ref.read(habitsProvider.notifier).importJson(content);
                                            if (ctx.mounted) Navigator.pop(ctx);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('🎉 Habits & To-Dos restored successfully!'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    ),
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
                            final restored = await ref.read(habitsProvider.notifier).importBackupFromFile(backupService);
                            if (restored && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🎉 Habits & To-Dos restored successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          child: const Text('Browse File Manager...'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  );
                } else {
                  final restored = await ref.read(habitsProvider.notifier).importBackupFromFile(backupService);
                  if (restored && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🎉 Habits & To-Dos restored successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to import backup file: $e')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: const Text('View & Copy Raw JSON'),
            subtitle: const Text('Inspect raw JSON data or copy to clipboard manually'),
            onTap: () {
              final jsonStr = ref.read(habitsProvider.notifier).exportJson();
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Full App Data (JSON)'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        jsonStr,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: jsonStr));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('JSON data copied to clipboard!')),
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
            },
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Habit Loop · build your streaks, one day at a time.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
      ),
    );
  }
}
