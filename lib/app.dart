import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/app_shell.dart';

class HabitLoopApp extends ConsumerStatefulWidget {
  const HabitLoopApp({super.key});

  @override
  ConsumerState<HabitLoopApp> createState() => _HabitLoopAppState();
}

class _HabitLoopAppState extends ConsumerState<HabitLoopApp>
    with WidgetsBindingObserver {
  StreamSubscription<NotificationResponse>? _reminderTaps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final notifications = NotificationService.instance;
    _reminderTaps = notifications.responses.listen(_onReminderResponse);
    final launch = notifications.launchResponse;
    if (launch != null) {
      notifications.launchResponse = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onReminderResponse(launch),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderTaps?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tops up the rolling reminder window and catches day rollovers.
    if (state == AppLifecycleState.resumed) {
      ref.read(habitsProvider.notifier).refreshReminders();
    }
  }

  Future<void> _onReminderResponse(NotificationResponse response) async {
    final habitId = response.payload;
    if (habitId == null) return;
    if (response.actionId == NotificationService.markDoneActionId) {
      final marked = await ref
          .read(habitsProvider.notifier)
          .markDoneFromReminder(habitId);
      if (marked) ref.read(soundServiceProvider).playCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Habit Loop',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}
