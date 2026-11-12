import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/usage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/habit.dart';
import '../../widgets/app_background.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/reminder_times_picker.dart';
import 'app_picker_screen.dart';

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

class _AddHabitScreenState extends ConsumerState<AddHabitScreen>
    with WidgetsBindingObserver {
  static const _buildPresets = <({int days, String label})>[
    (days: 21, label: 'Form it'),
    (days: 30, label: 'One month'),
    (days: 60, label: 'Automatic'),
  ];

  static const _quitPresets = <({int days, String label})>[
    (days: 7, label: 'One week'),
    (days: 21, label: 'Break it'),
    (days: 30, label: 'One month'),
  ];

  List<({int days, String label})> get _presets =>
      _isBad ? _quitPresets : _buildPresets;

  final _titleController = TextEditingController();
  final _customDaysController = TextEditingController();
  /// Quit habits only: measure minutes on [_screenApps] automatically,
  /// slipping on days over the limit typed into [_screenLimitController].
  bool _trackScreenTime = false;
  List<InstalledApp> _screenApps = [];
  final _screenLimitController = TextEditingController(text: '45');

  /// Whether Usage access is on; re-checked when the user comes back from
  /// system settings.
  bool _usageAllowed = false;

  /// True while the title is the one generated from the screen-time apps
  /// and limit, so it keeps following them until the user types their own.
  bool _autoTitle = false;

  int _days = 21;
  bool _customDays = false;
  bool _isFixed = false;
  bool _isBad = false;
  bool _isStrict = false;
  DateTime _startDate = DateTime.now();
  int _accentIndex = 0;
  List<int> _reminderTimes = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUsageAccess();
    _titleController.addListener(() => setState(() {}));

    if (widget.habit != null) {
      final h = widget.habit!;
      _titleController.text = h.title;
      _isFixed = h.isFixed;
      _isBad = h.isBad;
      _isStrict = h.isStrict;
      if (h.isScreenTimeHabit) {
        _trackScreenTime = true;
        _screenLimitController.text = '${h.screenTimeLimit}';
        // Package names stand in until the real app names load.
        _screenApps = [
          for (final pkg in h.screenTimeApps)
            InstalledApp(packageName: pkg, label: pkg),
        ];
        _loadScreenAppLabels(h.screenTimeApps);
      }
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
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _customDaysController.dispose();
    _screenLimitController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkUsageAccess();
  }

  Future<void> _checkUsageAccess() async {
    final allowed = await UsageService.hasPermission().catchError(
      (Object _) => false,
    );
    if (mounted && allowed != _usageAllowed) {
      setState(() => _usageAllowed = allowed);
    }
  }

  Future<void> _loadScreenAppLabels(List<String> packages) async {
    final List<InstalledApp> installed;
    try {
      installed = await UsageService.installedApps();
    } on PlatformException {
      return;
    }
    final labels = {for (final a in installed) a.packageName: a.label};
    if (!mounted) return;
    setState(() {
      _screenApps = [
        for (final pkg in packages)
          InstalledApp(packageName: pkg, label: labels[pkg] ?? pkg),
      ];
    });
  }

  int? get _screenLimit {
    final parsed = int.tryParse(_screenLimitController.text.trim());
    if (parsed == null || parsed < 1 || parsed > 1440) return null;
    return parsed;
  }

  String _screenTitle(int limit) {
    final names = _screenApps.map((a) => a.label).toList();
    final apps = switch (names.length) {
      0 => 'Screen time',
      1 => names[0],
      2 => '${names[0]} + ${names[1]}',
      _ => '${names[0]} + ${names.length - 1} more',
    };
    return '$apps under $limit min';
  }

  /// Rewrites a generated title after the apps or limit change.
  void _followScreenTitle() {
    final limit = _screenLimit;
    if (_autoTitle && limit != null) {
      _titleController.text = _screenTitle(limit);
    }
  }

  void _setTrackScreenTime(bool on) {
    _trackScreenTime = on;
    _error = null;
    if (on && _titleController.text.trim().isEmpty) {
      _titleController.text = _screenTitle(_screenLimit ?? 45);
      _autoTitle = true;
    } else if (!on && _autoTitle) {
      _titleController.clear();
      _autoTitle = false;
    }
  }

  void _setScreenLimit(int minutes) {
    setState(() {
      _error = null;
      _screenLimitController.text = '$minutes';
      _followScreenTitle();
    });
  }

  void _onScreenLimitChanged(String _) {
    setState(() {
      _error = null;
      _followScreenTitle();
    });
  }

  Future<void> _pickScreenApps() async {
    final picked = await AppPickerScreen.push(
      context,
      selected: {for (final a in _screenApps) a.packageName},
    );
    if (picked == null || !mounted) return;
    setState(() {
      _error = null;
      _screenApps = picked;
      _followScreenTitle();
    });
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

  /// Only offered while creating: flipping an existing habit would reinterpret
  /// its check-ins as slips (or the other way round).
  void _setBad(bool isBad) {
    if (isBad == _isBad) return;
    setState(() {
      _isBad = isBad;
      if (!isBad) _isStrict = false;
      if (!isBad && _trackScreenTime) _setTrackScreenTime(false);
      if (!_customDays) _days = _presets.first.days;
      _error = null;
    });
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
    final trackScreen = _isBad && _trackScreenTime;
    final screenLimit = trackScreen ? _screenLimit : null;
    if (trackScreen) {
      if (_screenApps.isEmpty) {
        setState(() => _error = 'Choose at least one app to limit.');
        return;
      }
      if (screenLimit == null) {
        setState(
          () => _error = 'Enter a daily limit between 1 and 1440 minutes.',
        );
        return;
      }
      if (!_usageAllowed) {
        setState(
          () => _error = 'Allow usage access so Habit Loop can see your '
              'screen time.',
        );
        return;
      }
    }
    final screenApps = trackScreen
        ? [for (final a in _screenApps) a.packageName]
        : <String>[];

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
      h.isStrict = _isBad && _isStrict;
      h.screenTimeLimit = screenLimit;
      h.screenTimeApps = screenApps;
      // Quit habits have no reminders.
      h.reminderTimes = _isBad ? [] : (_reminderTimes.toList()..sort());

      await ref.read(habitsProvider.notifier).updateHabit(h);
      if (!_isBad && _reminderTimes.isNotEmpty || trackScreen) {
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
            reminderTimes: _isBad ? const [] : _reminderTimes,
            isBad: _isBad,
            isStrict: _isStrict,
            screenTimeLimit: screenLimit,
            screenTimeApps: screenApps,
          );
      // Screen-time habits need notifications for their "min left" alerts.
      if (!_isBad && _reminderTimes.isNotEmpty || trackScreen) {
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
                      isBad: _isBad,
                      isStrict: _isStrict,
                    ),
                    const SizedBox(height: AppTokens.space6),

                    if (widget.habit == null) ...[
                      _FieldLabel('Habit type'),
                      Row(
                        children: [
                          Expanded(
                            child: _ModeTile(
                              title: 'Build',
                              icon: Icons.trending_up_rounded,
                              selected: !_isBad,
                              color: color,
                              onTap: () => _setBad(false),
                            ),
                          ),
                          const SizedBox(width: AppTokens.space2),
                          Expanded(
                            child: _ModeTile(
                              title: 'Quit',
                              icon: Icons.block_rounded,
                              selected: _isBad,
                              color: color,
                              onTap: () => _setBad(true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.space5),
                    ],

                    if (_isBad &&
                        UsageService.isSupported &&
                        (widget.habit == null || _trackScreenTime)) ...[
                      _FieldLabel('Track automatically'),
                      _ScreenTimeTrackingCard(
                        color: color,
                        enabled: _trackScreenTime,
                        // An existing habit can't switch its slips between
                        // manual and automatic; only the apps and limit can
                        // change.
                        canToggle: widget.habit == null,
                        usageAllowed: _usageAllowed,
                        apps: _screenApps,
                        limitController: _screenLimitController,
                        onToggle: (on) =>
                            setState(() => _setTrackScreenTime(on)),
                        onAllowUsage: UsageService.openSettings,
                        onPickApps: _pickScreenApps,
                        onLimitPreset: _setScreenLimit,
                        onLimitChanged: _onScreenLimitChanged,
                      ),
                      const SizedBox(height: AppTokens.space5),
                    ],

                    _FieldLabel('Habit title'),
                    TextField(
                      controller: _titleController,
                      onChanged: (_) => _autoTitle = false,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      style: theme.textTheme.titleMedium,
                      decoration: InputDecoration(
                        hintText: _isBad
                            ? 'e.g. No cigarettes, No junk food'
                            : 'e.g. Read 20 pages, Morning run',
                        prefixIcon: Icon(
                          Icons.edit_rounded,
                          size: 19,
                          color: p.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTokens.space5),

                    _FieldLabel(_isBad ? 'If you slip' : 'Habit mode'),
                    Row(
                      children: [
                        Expanded(
                          child: _ModeTile(
                            title: _isBad ? 'Extended' : 'Extended Mode',
                            icon: Icons.all_inclusive_rounded,
                            selected: !_isFixed && !_isStrict,
                            color: color,
                            onTap: () => setState(() {
                              _isFixed = false;
                              _isStrict = false;
                            }),
                          ),
                        ),
                        const SizedBox(width: AppTokens.space2),
                        Expanded(
                          child: _ModeTile(
                            title: _isBad ? 'Fixed' : 'Fixed Mode',
                            icon: Icons.timer_rounded,
                            selected: _isFixed && !_isStrict,
                            color: color,
                            onTap: () => setState(() {
                              _isFixed = true;
                              _isStrict = false;
                            }),
                          ),
                        ),
                        if (_isBad) ...[
                          const SizedBox(width: AppTokens.space2),
                          Expanded(
                            child: _ModeTile(
                              title: 'Strict',
                              icon: Icons.restart_alt_rounded,
                              selected: _isStrict,
                              color: color,
                              onTap: () => setState(() {
                                _isFixed = false;
                                _isStrict = true;
                              }),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_isBad) ...[
                      const SizedBox(height: AppTokens.space2),
                      Text(
                        _isStrict
                            ? 'A slip restarts your clean count. You need every day in a row.'
                            : _isFixed
                            ? 'Slips are recorded, and the challenge ends on schedule.'
                            : 'Each slip adds one day to the end. Your progress is kept.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
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

                    if (!_isBad &&
                        NotificationService.instance.isSupported) ...[
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

/// "Limit my screen time" option on a Quit habit: a switch, the apps to
/// measure and the daily minutes. Days over the limit become slips
/// automatically.
class _ScreenTimeTrackingCard extends StatelessWidget {
  const _ScreenTimeTrackingCard({
    required this.color,
    required this.enabled,
    required this.canToggle,
    required this.usageAllowed,
    required this.apps,
    required this.limitController,
    required this.onToggle,
    required this.onAllowUsage,
    required this.onPickApps,
    required this.onLimitPreset,
    required this.onLimitChanged,
  });

  static const _presets = [15, 30, 45, 60];

  final Color color;
  final bool enabled;
  final bool canToggle;
  final bool usageAllowed;
  final List<InstalledApp> apps;
  final TextEditingController limitController;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAllowUsage;
  final VoidCallback onPickApps;
  final ValueChanged<int> onLimitPreset;
  final ValueChanged<String> onLimitChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final limit = int.tryParse(limitController.text.trim());

    return GlassCard(
      accent: color,
      highlighted: enabled,
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_bottom_rounded, color: color),
              const SizedBox(width: AppTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Screen time', style: theme.textTheme.titleSmall),
                    Text(
                      'Uses your phone’s usage stats — no need to log slips',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (canToggle) Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled) ...[
            if (!usageAllowed) ...[
              const SizedBox(height: AppTokens.space4),
              Container(
                padding: const EdgeInsets.all(AppTokens.space3),
                decoration: BoxDecoration(
                  color: p.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  border: Border.all(color: p.warning.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Turn on Usage access for Habit Loop so it can see how '
                      'long you spend in each app. It can’t see what’s on '
                      'your screen.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space2),
                    OutlinedButton.icon(
                      onPressed: onAllowUsage,
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: const Text('Allow usage access'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppTokens.space4),
            Text('Apps', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTokens.space2),
            Wrap(
              spacing: AppTokens.space2,
              runSpacing: AppTokens.space2,
              children: [
                for (final app in apps)
                  Chip(
                    avatar: AppIcon(packageName: app.packageName, size: 20),
                    label: Text(app.label),
                    visualDensity: VisualDensity.compact,
                  ),
                ActionChip(
                  avatar: Icon(
                    apps.isEmpty ? Icons.add_rounded : Icons.edit_rounded,
                    size: 18,
                  ),
                  label: Text(apps.isEmpty ? 'Choose apps' : 'Change'),
                  onPressed: onPickApps,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppTokens.space4),
            Text('Daily limit', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTokens.space2),
            Wrap(
              spacing: AppTokens.space2,
              children: [
                for (final minutes in _presets)
                  ChoiceChip(
                    label: Text('$minutes min'),
                    selected: limit == minutes,
                    onSelected: (_) => onLimitPreset(minutes),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.space3),
            TextField(
              controller: limitController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              onChanged: onLimitChanged,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                labelText: 'Max minutes per day',
                suffixText: 'min',
                prefixIcon: Icon(Icons.flag_rounded, size: 19),
              ),
            ),
            const SizedBox(height: AppTokens.space2),
            Text(
              'Any day you spend longer than this across these apps is '
              'logged as a slip.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: p.textSecondary,
              ),
            ),
          ],
        ],
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
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String title;
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? color : p.textTertiary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? color : p.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
    required this.isBad,
    required this.isStrict,
  });

  final String title;
  final int days;
  final Color color;
  final DateTime startDate;
  final bool isFixed;
  final bool isBad;
  final bool isStrict;

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
                  title.isEmpty
                      ? (isBad ? 'The habit you\'re quitting' : 'Your new habit')
                      : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: title.isEmpty ? p.textTertiary : p.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isBad
                      ? '$days clean days · ${isStrict ? 'Strict' : isFixed ? 'Fixed' : 'Extended'} · starts ${DateFormat.MMMd().format(startDate)}'
                      : '$days days · ${isFixed ? 'Fixed duration' : 'Extended duration'} · starts ${DateFormat.MMMd().format(startDate)}',
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
            child: Icon(
              isBad ? Icons.block_rounded : Icons.add_rounded,
              color: color,
              size: 22,
            ),
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
