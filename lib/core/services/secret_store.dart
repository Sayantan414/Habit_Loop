import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API keys the user pastes in Settings, encrypted with the Android Keystore.
///
/// They never leave the phone except in requests to their own service, and
/// are not part of the JSON backup. A key that can't be decrypted after a
/// phone restore is simply dropped, and the user pastes it again.
class SecretStore {
  SecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _geminiKey = 'gemini_api_key';

  /// From the short-lived Groq Whisper mode; removed on first read.
  static const _legacyGroqKey = 'groq_api_key';

  final FlutterSecureStorage _storage;

  Future<String?> geminiApiKey() async {
    await _storage.delete(key: _legacyGroqKey);
    final key = await _storage.read(key: _geminiKey);
    return key == null || key.isEmpty ? null : key;
  }

  Future<void> setGeminiApiKey(String key) =>
      _storage.write(key: _geminiKey, value: key);

  Future<void> deleteGeminiApiKey() => _storage.delete(key: _geminiKey);
}
