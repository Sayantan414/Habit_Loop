import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user preferences (theme, sound, widget) to SharedPreferences.
class SettingsService {
  SettingsService(this._prefs);

  static const _themeModeKey = 'theme_mode';
  static const _soundEnabledKey = 'sound_enabled';
  static const _vibrationEnabledKey = 'vibration_enabled';
  static const _vibrationModeKey = 'vibration_mode';
  static const _notificationSoundKey = 'notification_sound';
  static const _notificationSoundEnabledKey = 'notification_sound_enabled';

  final SharedPreferences _prefs;

  static Future<SettingsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  ThemeMode getThemeMode() {
    final value = _prefs.getString(_themeModeKey);
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeModeKey, mode.name);
  }

  bool getSoundEnabled() => _prefs.getBool(_soundEnabledKey) ?? true;

  Future<void> setSoundEnabled(bool enabled) async {
    await _prefs.setBool(_soundEnabledKey, enabled);
  }

  bool getVibrationEnabled() => _prefs.getBool(_vibrationEnabledKey) ?? true;

  Future<void> setVibrationEnabled(bool enabled) async {
    await _prefs.setBool(_vibrationEnabledKey, enabled);
  }

  String getVibrationMode() => _prefs.getString(_vibrationModeKey) ?? 'subtle';

  Future<void> setVibrationMode(String mode) async {
    await _prefs.setString(_vibrationModeKey, mode);
  }

  bool getNotificationSoundEnabled() =>
      _prefs.getBool(_notificationSoundEnabledKey) ?? true;

  Future<void> setNotificationSoundEnabled(bool enabled) async {
    await _prefs.setBool(_notificationSoundEnabledKey, enabled);
  }

  String getNotificationSound() =>
      _prefs.getString(_notificationSoundKey) ?? 'chime';

  Future<void> setNotificationSound(String sound) async {
    await _prefs.setString(_notificationSoundKey, sound);
  }
}
