import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/habit.dart';
import '../../widgets/app_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/reminder_times_picker.dart';

/// SCREEN 3 — Create or edit a habit.
class AddHabitScreen extends ConsumerStatefulWidget {
  const AddHabitScreen({super.key, this.habit});

  final Habit? habit;

  static Future<void> push(BuildContext context, {Habit? habit}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => AddHabitScreen(habit: habit)),
    );
  }

  @override
  ConsumerState<AddHabitScreen> createState() => _AddHabitScreenState();
}

/// Backward-compatible wrapper so any existing call pushes the full screen page.
abstract final class AddHabitSheet {
  static Future<void> show(BuildContext context, {Habit? habit}) {
    return AddHabitScreen.push(context, habit: habit);
  }
}

class _AddHabitScreenState extends ConsumerState<AddHabitScreen> {
  static const _presets = <({int days, String label})>[
    (days: 21, label: 'Form it'),
    (days: 30, label: 'One month'),
    (days: 60, label: 'Automatic'),
  ];

  final _titleController = TextEditingController();
  final _customDaysController = TextEditingController();

  int _days = 21;
  bool _customDays = false;
  bool _isFixed = false;
  DateTime _startDate = DateTime.now();
  int _accentIndex = 0;
  List<int> _reminderTimes = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));

    if (widget.habit != null) {
      final h = widget.habit!;
      _titleController.text = h.title;
      _isFixed = h.isFixed;
      _startDate = h.startDate;
      _reminderTimes = List<int>.from(h.reminderTimes);

      final matchIndex = AppAccents.swatches.indexWhere(
        (s) =>
            s.id == h.colorValue ||
            s.dark.toARGB32() == h.colorValue ||
            s.light.toARGB32() == h.colorValue,
      );
      if (matchIndex != -1) {
        _accentIndex = matchIndex;
      }

      if (_presets.any((p) => p.days == h.totalDays)) {
        _days = h.totalDays;
        _customDays = false;
      } else {
        _days = h.totalDays;
        _customDays = true;
        _customDaysController.text = h.totalDays.toString();
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  AccentSwatch get _swatch => AppAccents.swatches[_accentIndex];

  Color _accentColor(BuildContext context) =>
      AppAccents.resolve(_swatch.id, Theme.of(context).brightness);

  int? get _resolvedDays {
    if (!_customDays) return _days;
    final parsed = int.tryParse(_customDaysController.text.trim());
    if (parsed == null || parsed < 1 || parsed > 365) return null;
    return parsed;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final days = _resolvedDays;

    if (title.isEmpty) {
      setState(() => _error = 'Give your habit a name.');
      return;
    }
    if (days == null) {
      setState(
        () => _error = 'Enter a challenge length between 1 and 365 days.',
      );
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    HapticFeedback.mediumImpact();

    if (widget.habit != null) {
      final h = widget.habit!;
      h.title = title;
      h.totalDays = days;
      h.startDate = _startDate;
      h.colorValue = _swatch.id;
      h.isFixed = _isFixed;
      h.reminderTimes = _reminderTimes.toList()..sort();

      await ref.read(habitsProvider.notifier).updateHabit(h);
      if (_reminderTimes.isNotEmpty) {
        await NotificationService.instance.requestPermissions();
        await NotificationService.instance.syncAll(ref.read(habitsProvider));
      } else {
        await NotificationService.instance.clearToday(h);
      }
    } else {
      await ref
          .read(habitsProvider.notifier)
          .addHabit(
            title: title,
            totalDays: days,
            startDate: _startDate,
            colorValue: _swatch.id,
            isFixed: _isFixed,
            reminderTimes: _reminderTimes,
          );
      if (_reminderTimes.isNotEmpty) {
        await NotificationService.instance.requestPermissions();
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final color = _accentColor(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              _HeaderBar(color: color, isEditing: widget.habit != null),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.gutter,
                    AppTokens.space3,
                    AppTokens.gutter,
                    AppTokens.space6,
                  ),
                  children: [
                    // Live preview.
                    _PreviewCard(
                      title: _titleController.text.trim(),
                      days: _resolvedDays ?? _days,
                      color: color,
                      startDate: _startDate,
                      isFixed: _isFixed,
                    ),
                    const SizedBox(height: AppTokens.space6),

                    _FieldLabel('Habit title'),
                    TextField(
                      controller: _titleController,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      style: theme.textTheme.titleMedium,
                      decoration: InputDecoration(
                        hintText: 'e.g. Read 20 pages, Morning run',
                        prefixIcon: Icon(
                          Icons.edit_rounded,
                          size: 19,
                          color: p.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTokens.space5),

                    _FieldLabel('Habit mode'),
                    _ModeTile(
                      title: 'Extended Mode',
                      subtitle:
                          'Missing a day extends total target by +1 day until finished.',
                      icon: Icons.all_inclusive_rounded,
                      selected: !_isFixed,
                      color: color,
                      onTap: () => setState(() => _isFixed = false),
                    ),
                    const SizedBox(height: AppTokens.space2),
                    _ModeTile(
                      title: 'Fixed Mode',
                      subtitle:
                          'Strict timeline duration. Timeline does not extend on missed days.',
                      icon: Icons.timer_rounded,
                      selected: _isFixed,
                      color: color,
                      onTap: () => setState(() => _isFixed = true),
                    ),
                    const SizedBox(height: AppTokens.space5),

                    _FieldLabel('Challenge length'),
                    Row(
                      children: [
                        for (final preset in _presets) ...[
                          Expanded(
                            child: _PresetChip(
                              days: preset.days,
                              caption: preset.label,
                              selected: !_customDays && _days == preset.days,
                              color: color,
                              onTap: () => setState(() {
                                _customDays = false;
                                _days = preset.days;
                                _error = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: AppTokens.space2),
                        ],
                        _CustomDaysChip(
                          selected: _customDays,
                          color: color,
                          onTap: () => setState(() {
                            _customDays = true;
                            _error = null;
                          }),
                        ),
                      ],
                    ),
                    if (_customDays) ...[
                      const SizedBox(height: AppTokens.space3),
                      TextField(
                        controller: _customDaysController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        onChanged: (_) => setState(() => _error = null),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: const InputDecoration(
                          hintText: 'Custom number of days (1–365)',
                          prefixIcon: Icon(Icons.tag_rounded, size: 19),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppTokens.space5),

                    _FieldLabel('Start date'),
                    Pressable(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.space4,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: p.isDark
                              ? p.surfaceHigh.withValues(alpha: 0.6)
                              : p.surfaceHigh,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                          border: Border.all(color: p.stroke),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              size: 19,
                              color: color,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              DateFormat.yMMMEd().format(_startDate),
                              style: theme.textTheme.titleMedium,
                            ),
                            const Spacer(),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: p.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTokens.space5),

                    if (NotificationService.instance.isSupported) ...[
                      _FieldLabel('Daily reminders'),
                      ReminderTimesPicker(
                        times: _reminderTimes,
                        color: color,
                        onChanged: (times) =>
                            setState(() => _reminderTimes = times),
                      ),
                      const SizedBox(height: AppTokens.space5),
                    ],

                    _FieldLabel('Accent color'),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (var i = 0; i < AppAccents.swatches.length; i++)
                          _ColorDot(
                            color: AppAccents.resolve(
                              AppAccents.swatches[i].id,
                              theme.brightness,
                            ),
                            label: AppAccents.swatches[i].name,
                            selected: i == _accentIndex,
                            onTap: () => setState(() => _accentIndex = i),
                          ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppTokens.space4),
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: p.danger,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: p.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Bottom Create / Save CTA.
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.gutter,
                  AppTokens.space3,
                  AppTokens.gutter,
                  AppTokens.space4,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.stroke)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: color),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            widget.habit != null
                                ? Icons.save_rounded
                                : Icons.auto_awesome_rounded,
                            size: 19,
                          ),
                    label: Text(
                      _saving
                          ? (widget.habit != null ? 'Saving…' : 'Creating…')
                          : (widget.habit != null
                              ? 'Save changes'
                              : 'Create habit'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.color, required this.isEditing});

  final Color color;
  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.gutter,
        vertical: AppTokens.space2,
      ),
      child: Row(
        children: [
          Pressable(
            onTap: () => Navigator.of(context).pop(),
            scale: 0.9,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.isDark ? p.surfaceHigh : p.surface,
                border: Border.all(color: p.stroke),
              ),
              child: Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: p.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            isEditing ? 'Edit habit' : 'New habit',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space2),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppPalette.of(context).textTertiary,
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTokens.base,
        curve: AppTokens.emphasized,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: p.isDark ? 0.18 : 0.12)
              : (p.isDark ? p.surfaceHigh.withValues(alpha: 0.5) : p.surface),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: selected ? color : p.stroke,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? color : p.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? color : p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.title,
    required this.days,
    required this.color,
    required this.startDate,
    required this.isFixed,
  });

  final String title;
  final int days;
  final Color color;
  final DateTime startDate;
  final bool isFixed;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return GlassCard(
      accent: color,
      highlighted: true,
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'Your new habit' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: title.isEmpty ? p.textTertiary : p.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$days days · ${isFixed ? 'Fixed duration' : 'Extended duration'} · starts ${DateFormat.MMMd().format(startDate)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: p.isDark ? 0.16 : 0.12),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
            ),
            child: Icon(Icons.add_rounded, color: color, size: 22),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.days,
    required this.caption,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final int days;
  final String caption;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTokens.base,
        curve: AppTokens.emphasized,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: p.isDark ? 0.18 : 0.12)
              : (p.isDark ? p.surfaceHigh.withValues(alpha: 0.5) : p.surface),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: selected ? color : p.stroke,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              '$days',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: selected ? color : p.textPrimary,
                fontFeatures: AppTypography.tabular,
              ),
            ),
            Text(
              caption,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? color : p.textTertiary,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomDaysChip extends StatelessWidget {
  const _CustomDaysChip({
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTokens.base,
        width: 54,
        height: 62,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: p.isDark ? 0.18 : 0.12)
              : (p.isDark ? p.surfaceHigh.withValues(alpha: 0.5) : p.surface),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: selected ? color : p.stroke,
            width: selected ? 1.6 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.tune_rounded,
          color: selected ? color : p.textTertiary,
          size: 22,
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return Tooltip(
      message: label,
      child: Pressable(
        onTap: onTap,
        scale: 0.88,
        child: AnimatedContainer(
          duration: AppTokens.base,
          curve: AppTokens.springy,
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: p.isDark ? p.canvas : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
