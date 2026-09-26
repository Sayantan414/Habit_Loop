import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'core/providers.dart';
import 'core/services/notification_service.dart';
import 'core/services/widget_service.dart';
import 'core/theme/app_theme.dart';
import 'features/habit_detail/habit_detail_screen.dart';
import 'features/shell/app_shell.dart';

class HabitLoopApp extends ConsumerStatefulWidget {
  const HabitLoopApp({super.key});

  @override
  ConsumerState<HabitLoopApp> createState() => _HabitLoopAppState();
}

class _HabitLoopAppState extends ConsumerState<HabitLoopApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<NotificationResponse>? _reminderTaps;
  StreamSubscription<Uri?>? _widgetTaps;

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

    _widgetTaps = HomeWidget.widgetClicked.listen(_onWidgetTap);
    HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
      if (uri == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onWidgetTap(uri));
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderTaps?.cancel();
    _widgetTaps?.cancel();
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

  /// Routes a home screen widget tap: back to the shell root, onto the right
  /// tab, and — for a habit row — straight into that habit's detail screen.
  void _onWidgetTap(Uri? uri) {
    final link = WidgetLink.parse(uri);
    final navigator = _navigatorKey.currentState;
    if (link == null || navigator == null) return;

    navigator.popUntil((route) => route.isFirst);
    final tab = link is TodoLink ? 1 : 0;
    ref.read(shellTabRequestProvider.notifier).state = ShellTabRequest(tab);

    if (link is HabitLink) {
      final exists = ref.read(habitsProvider).any((h) => h.id == link.habitId);
      if (!exists) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => HabitDetailScreen(habitId: link.habitId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Habit Loop',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}
