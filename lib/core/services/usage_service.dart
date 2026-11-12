import 'dart:io';

import 'package:flutter/services.dart';

import '../../data/models/habit.dart';

/// A launchable app the user can pick for a screen-time habit.
class InstalledApp {
  const InstalledApp({required this.packageName, required this.label});

  final String packageName;
  final String label;
}

/// Talks to the native usage bridge (UsageChannel).
///
/// Foreground time comes from Android's UsageStatsManager and needs the
/// Usage access permission, which the user turns on in system settings.
/// Every call no-ops on platforms other than Android.
class UsageService {
  static const _channel = MethodChannel('habitloop/usage');

  static bool get isSupported => Platform.isAndroid;

  /// Whether the user has turned on Usage access for Habit Loop.
  static Future<bool> hasPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  }

  static Future<void> openSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openSettings');
  }

  /// Every launchable app except Habit Loop, sorted by name.
  static Future<List<InstalledApp>> installedApps() async {
    if (!isSupported) return [];
    final raw = await _channel.invokeListMethod<Map>('installedApps') ?? [];
    return raw
        .map(
          (app) => InstalledApp(
            packageName: app['package'] as String,
            label: app['label'] as String,
          ),
        )
        .toList();
  }

  /// The app's launcher icon as PNG bytes, or null if it isn't installed.
  static Future<Uint8List?> appIcon(String packageName) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<Uint8List>('appIcon', {
      'package': packageName,
    });
  }

  /// Hands the running screen-time [habits] to the native alerts, which
  /// post "10 / 5 / 1 minutes left" while Habit Loop is closed. An empty
  /// list stops them.
  static Future<void> setAlertLimits(Iterable<Habit> habits) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setAlertLimits', {
      'limits': [
        for (final h in habits)
          {
            'id': h.id,
            'title': h.title,
            'limit': h.screenTimeLimit,
            'apps': h.screenTimeApps,
          },
      ],
    });
  }

  /// `{ 'yyyy-MM-dd': { package: minutes } }` for [packages] over the last
  /// [days] days, today included. Days with no usage are left out.
  ///
  /// Throws a [PlatformException] (code `no_permission`) when Usage access is
  /// off, so callers can tell "no permission" apart from "no usage".
  static Future<Map<String, Map<String, int>>> dailyUsage(
    Iterable<String> packages, {
    int days = 7,
  }) async {
    if (!isSupported || packages.isEmpty) return {};
    final raw = await _channel.invokeMapMethod<String, dynamic>('dailyUsage', {
      'packages': packages.toList(),
      'days': days,
    });
    if (raw == null) return {};
    return raw.map(
      (day, apps) => MapEntry(day, Map<String, int>.from(apps as Map)),
    );
  }
}
