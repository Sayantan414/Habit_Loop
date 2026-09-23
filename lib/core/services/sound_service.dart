import 'package:flutter/services.dart';

/// Plays short system feedback sounds for habit check-ins.
///
/// Uses the platform's built-in system sounds rather than bundled audio
/// assets, so it works the same on Android and Windows with no extra files.
class SoundService {
  SoundService({required bool enabled}) : _enabled = enabled;

  bool _enabled;

  void setEnabled(bool enabled) => _enabled = enabled;

  Future<void> playCheck() async {
    if (!_enabled) return;
    await SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  Future<void> playAllDone() async {
    if (!_enabled) return;
    await SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();
  }
}
