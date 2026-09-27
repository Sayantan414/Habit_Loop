import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/habit.dart';
import '../theme/app_colors.dart';

/// Schedules the daily habit reminders the user picks per habit.
///
/// Reminders are scheduled as one-shot notifications for the next
/// [_daysAhead] days rather than as open-ended repeating alarms, so that a
/// habit which is already checked off today (or has finished its challenge)
/// simply has no reminder queued. Every habit change re-runs [syncAll], and
/// app start / resume tops the window back up.
///
/// Android only for now; every call no-ops elsewhere, so it's always safe to
/// call from shared app code (same approach as WidgetService).
class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  static const markDoneActionId = 'mark_done';

  static const _daysAhead = 7;
  static const _legacyChannelIds = ['habit_reminders', 'habit_reminders_v2'];
  static const _channelName = 'Habit reminders';
  static const _channelDescription =
      'Reminders at the times you picked for each habit.';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _responses = StreamController<NotificationResponse>.broadcast();

  bool _ready = false;
  List<Habit> _lastHabits = const [];
  Future<void> _syncQueue = Future.value();

  bool _vibrationEnabled = true;
  String _vibrationMode = 'subtle';
  bool _notificationSoundEnabled = true;
  String _notificationSound = 'chime';

  String get _currentChannelId =>
      'habit_reminders_${_notificationSound}_${_vibrationMode}_${_notificationSoundEnabled}_$_vibrationEnabled';

  /// The notification (or its action button) that cold-started the app, if any.
  NotificationResponse? launchResponse;

  /// Taps and action presses on reminders while the app is running.
  Stream<NotificationResponse> get responses => _responses.stream;

  bool get isSupported => Platform.isAndroid;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  void updateVibration({required bool enabled, required String mode}) {
    _vibrationEnabled = enabled;
    _vibrationMode = mode;
    if (_ready) {
      _createChannel();
      syncAll(_lastHabits);
    }
  }

  void updateSound({required bool enabled, required String sound}) {
    _notificationSoundEnabled = enabled;
    _notificationSound = sound;
    if (_ready) {
      _createChannel();
      syncAll(_lastHabits);
    }
  }

  Int64List? _getVibrationPatternFor(String mode) {
    if (!_vibrationEnabled) return null;
    switch (mode) {
      case 'pulse':
        return Int64List.fromList([0, 150, 100, 150, 400, 150, 100, 150]);
      case 'strong':
        return Int64List.fromList([0, 400, 200, 400]);
      case 'subtle':
      default:
        return Int64List.fromList([0, 100, 100, 100]);
    }
  }

  Int64List? _getVibrationPattern() => _getVibrationPatternFor(_vibrationMode);

  AndroidNotificationSound? _getSoundFor(String soundKey) {
    if (!_notificationSoundEnabled) return null;
    switch (soundKey) {
      case 'chime':
        return const RawResourceAndroidNotificationSound('habit_chime');
      case 'bell':
        return const RawResourceAndroidNotificationSound('habit_bell');
      case 'zen':
        return const RawResourceAndroidNotificationSound('habit_zen');
      case 'system':
      default:
        return null;
    }
  }

  AndroidNotificationSound? _getNotificationSound() =>
      _getSoundFor(_notificationSound);

  Future<void> showPreviewNotification({
    String? sound,
    String? vibrationMode,
  }) async {
    if (!isSupported || !_ready) return;
    final targetSound = sound ?? _notificationSound;
    final targetVibeMode = vibrationMode ?? _vibrationMode;
    final previewChannelId =
        'habit_preview_${targetSound}_${targetVibeMode}_${_notificationSoundEnabled}_$_vibrationEnabled';

    final android = _android;
    if (android != null) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          previewChannelId,
          'Sound Preview ($targetSound)',
          description: 'Preview of selected notification sound',
          importance: Importance.max,
          sound: _getSoundFor(targetSound),
          enableVibration: _vibrationEnabled,
          vibrationPattern: _getVibrationPatternFor(targetVibeMode),
          playSound: _notificationSoundEnabled,
        ),
      );

      await _plugin.show(
        id: 888888,
        title: 'Habit Loop',
        body: 'Previewing ${targetSound[0].toUpperCase()}${targetSound.substring(1)} notification sound',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            previewChannelId,
            'Sound Preview ($targetSound)',
            importance: Importance.max,
            priority: Priority.max,
            sound: _getSoundFor(targetSound),
            enableVibration: _vibrationEnabled,
            vibrationPattern: _getVibrationPatternFor(targetVibeMode),
            playSound: _notificationSoundEnabled,
            icon: 'ic_stat_habit',
          ),
        ),
      );
    }
  }

  Future<void> _createChannel() async {
    final android = _android;
    if (android == null) return;
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _currentChannelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        sound: _getNotificationSound(),
        enableVibration: _vibrationEnabled,
        vibrationPattern: _getVibrationPattern(),
      ),
    );
  }

  Future<void> init() async {
    if (!isSupported || _ready) return;
    try {
      await _initTimeZone();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_habit'),
        ),
        onDidReceiveNotificationResponse: _responses.add,
      );
      for (final id in _legacyChannelIds) {
        await _android?.deleteNotificationChannel(channelId: id);
      }
      await _createChannel();
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        launchResponse = launch!.notificationResponse;
      }
      _ready = true;
    } catch (e) {
      debugPrint('NotificationService init failed: $e');
    }
  }

  Future<void> _initTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Unknown zone name: fall back to any zone with the device's offset so
      // reminders still land at the right wall-clock time today.
      final offset = DateTime.now().timeZoneOffset;
      final match = tz.timeZoneDatabase.locations.values.firstWhere(
        (l) => l.currentTimeZone.offset == offset,
        orElse: () => tz.UTC,
      );
      tz.setLocalLocation(match);
    }
  }

  /// Asks for notification permission, plus exact-alarm access so reminders
  /// fire on the minute. Returns false if notifications stay blocked.
  Future<bool> requestPermissions() async {
    if (!_ready) return false;
    final android = _android;
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission() ?? false;
    if (granted && !(await android.canScheduleExactNotifications() ?? false)) {
      await android.requestExactAlarmsPermission();
    }
    if (granted) await syncAll(_lastHabits);
    return granted;
  }

  /// Re-plans every reminder for [habits]. Calls are queued so overlapping
  /// syncs (e.g. rapid check-ins) can't interleave cancel/schedule steps.
  Future<void> syncAll(List<Habit> habits) {
    _lastHabits = habits;
    _syncQueue = _syncQueue.then((_) => _syncAll(habits)).catchError((
      Object e,
    ) {
      debugPrint('NotificationService sync failed: $e');
    });
    return _syncQueue;
  }

  /// Removes any of [habit]'s reminders already sitting in the tray today.
  Future<void> clearToday(Habit habit) async {
    if (!_ready) return;
    final now = tz.TZDateTime.now(tz.local);
    for (final minute in habit.reminderTimes) {
      await _plugin.cancel(id: _idFor(habit.id, now, minute));
    }
  }

  Future<void> _syncAll(List<Habit> habits) async {
    if (!_ready) return;

    for (final request in await _plugin.pendingNotificationRequests()) {
      await _plugin.cancel(id: request.id);
    }

    final now = tz.TZDateTime.now(tz.local);
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    for (final habit in habits) {
      if (habit.reminderTimes.isEmpty) continue;

      // Checked off (or slipped) today: drop today's reminders, including
      // ones already shown.
      if (habit.isCompletedToday || habit.isSlippedToday) {
        await clearToday(habit);
      }

      for (var offset = 0; offset < _daysAhead; offset++) {
        final day = DateTime(now.year, now.month, now.day + offset);
        if (!_remindsOn(habit, day, isToday: offset == 0)) continue;

        final dayNumber = habit.dayNumberFor(day);
        final times = habit.reminderTimes.toList()..sort();
        for (var i = 0; i < times.length; i++) {
          final minute = times[i];
          final at = tz.TZDateTime(
            tz.local,
            day.year,
            day.month,
            day.day,
            minute ~/ 60,
            minute % 60,
          );
          if (!at.isAfter(now)) continue;

          final message = _message(habit, dayNumber, i);
          await _plugin.zonedSchedule(
            id: _idFor(habit.id, day, minute),
            scheduledDate: at,
            title: message.title,
            body: message.body,
            payload: habit.id,
            androidScheduleMode: mode,
            notificationDetails: _details(habit, message),
          );
        }
      }
    }
  }

  bool _remindsOn(Habit habit, DateTime day, {required bool isToday}) {
    if (habit.archived || habit.isFinished || habit.isPaused) return false;
    if (isToday && (habit.isCompletedToday || habit.isSlippedToday)) {
      return false;
    }
    final dayNumber = habit.dayNumberFor(day);
    if (dayNumber < 1) return false;
    // Extended habits run every day until the target count is reached, so
    // only Fixed ones have a hard last day.
    if (habit.isBad) return dayNumber <= habit.effectiveTotalDays;
    return !habit.isFixed || dayNumber <= habit.totalDays;
  }

  ({String title, String body, String summary}) _message(
    Habit habit,
    int dayNumber,
    int slot,
  ) {
    if (habit.isBad) return _quitMessage(habit, dayNumber, slot);

    final summary = habit.isFixed
        ? 'Day $dayNumber of ${habit.totalDays}'
        : 'Day $dayNumber · ${habit.totalDays}-day loop';

    final lastDay = habit.isFixed && dayNumber == habit.totalDays;
    if (lastDay) {
      return (
        title: 'Final day: ${habit.title}',
        body: 'Last check-in of the challenge. Finish the loop strong.',
        summary: summary,
      );
    }

    const lines = [
      'A few minutes now keeps your loop unbroken.',
      'Small steps, every day. Check it off once it\'s done.',
      'Consistency beats intensity. One check-in at a time.',
      'Future you will thank you for this one.',
    ];
    return (
      title: 'Time for ${habit.title}',
      body: lines[(dayNumber + slot) % lines.length],
      summary: summary,
    );
  }

  /// Encouragement rather than a to-do: there is nothing to check off, and
  /// the user only needs to open the app if they slipped.
  ({String title, String body, String summary}) _quitMessage(
    Habit habit,
    int dayNumber,
    int slot,
  ) {
    final summary = 'Day $dayNumber of ${habit.effectiveTotalDays}';
    // Assumes no slips between now and [dayNumber]; re-synced on every change.
    final clean = habit.currentStreak + (dayNumber - habit.todayDayNumber);

    const lines = [
      "Cravings pass. You've got this.",
      'Every clean day makes the next one easier.',
      'Only open the app if you slipped — otherwise, keep going.',
      'One day at a time. Today counts.',
    ];
    return (
      title: clean > 0
          ? '${habit.title}: $clean ${clean == 1 ? 'day' : 'days'} clean'
          : 'Stay strong: ${habit.title}',
      body: lines[(dayNumber + slot) % lines.length],
      summary: summary,
    );
  }

  NotificationDetails _details(
    Habit habit,
    ({String title, String body, String summary}) message,
  ) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _currentChannelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        icon: 'ic_stat_habit',
        color: AppAccents.resolve(habit.colorValue, Brightness.light),
        sound: _getNotificationSound(),
        enableVibration: _vibrationEnabled,
        vibrationPattern: _getVibrationPattern(),
        subText: message.summary,
        ticker: message.title,
        styleInformation: BigTextStyleInformation(
          message.body,
          contentTitle: message.title,
          summaryText: message.summary,
        ),
        actions: habit.isBad
            ? null
            : const [
                AndroidNotificationAction(
                  markDoneActionId,
                  'Mark as done',
                  showsUserInterface: true,
                ),
              ],
      ),
    );
  }

  /// Stable id per (habit, calendar day, time) so re-syncing replaces rather
  /// than duplicates, and today's shown reminder can be cleared by id.
  static int _idFor(String habitId, DateTime day, int minute) {
    final key = '$habitId|${day.year}-${day.month}-${day.day}|$minute';
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}
