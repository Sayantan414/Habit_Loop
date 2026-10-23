import 'dart:io';

import 'package:flutter/services.dart';

/// Talks to the native reels counter (ReelsCounterService / ReelsChannel).
///
/// Counting happens entirely in the Android accessibility service; this class
/// only reads what it stored and updates which apps it listens to. Every
/// call no-ops on platforms other than Android.
class ReelsService {
  static const _channel = MethodChannel('habitloop/reels');

  static bool get isSupported => Platform.isAndroid;

  /// Whether the user has turned the service on in Accessibility settings.
  static Future<bool> isServiceEnabled() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;
  }

  static Future<void> openAccessibilitySettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openAccessibilitySettings');
  }

  /// The subset of [packages] installed on this device.
  static Future<Set<String>> installedApps(List<String> packages) async {
    if (!isSupported) return {};
    final result = await _channel.invokeListMethod<String>(
      'installedApps',
      {'packages': packages},
    );
    return result?.toSet() ?? {};
  }

  static Future<Set<String>> selectedApps() async {
    if (!isSupported) return {};
    final result = await _channel.invokeListMethod<String>('getSelectedApps');
    return result?.toSet() ?? {};
  }

  static Future<void> setSelectedApps(Set<String> packages) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'setSelectedApps',
      {'packages': packages.toList()},
    );
  }

  /// `{ 'yyyy-MM-dd': { package: count } }` for the last [days] days.
  static Future<Map<String, Map<String, int>>> counts({int days = 7}) async {
    if (!isSupported) return {};
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'getCounts',
      {'days': days},
    );
    if (raw == null) return {};
    return raw.map(
      (day, apps) => MapEntry(day, Map<String, int>.from(apps as Map)),
    );
  }

  /// Daily target of the running reels habit, so the service can alert the
  /// moment it's passed; 0 = no reels habit.
  static Future<void> setHabitTarget(int target) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setHabitTarget', {'target': target});
  }

  /// Reels in a row before the doomscrolling reminder; 0 = off.
  static Future<int> remindEvery() async {
    if (!isSupported) return 0;
    return await _channel.invokeMethod<int>('getRemindEvery') ?? 0;
  }

  static Future<void> setRemindEvery(int reels) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setRemindEvery', {'reels': reels});
  }

  /// Distinct scroll containers the service has seen, newest first.
  static Future<List<String>> detectionLog() async {
    if (!isSupported) return [];
    return await _channel.invokeListMethod<String>('getDetectionLog') ?? [];
  }

  static Future<void> clearDetectionLog() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('clearDetectionLog');
  }
}
