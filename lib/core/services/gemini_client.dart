import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Why a Gemini request failed. [code] is one of `gemini_auth`,
/// `gemini_quota`, `gemini_network` or `gemini_server`.
class GeminiException implements Exception {
  const GeminiException(this.code, {this.retryAfter});

  final String code;

  /// How long Google asked us to wait (rate limits only).
  final Duration? retryAfter;

  @override
  String toString() => 'GeminiException($code)';
}

/// The Gemini API on the free tier, with the user's own key.
class GeminiClient {
  GeminiClient({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  static const host = 'https://generativelanguage.googleapis.com';
  static final _models = Uri.parse('$host/v1beta/models');

  static const _timeout = Duration(seconds: 60);

  final String apiKey;
  final http.Client _client;

  Map<String, String> get _auth => {'x-goog-api-key': apiKey};

  /// True if Google accepts the key; throws [GeminiException] when it
  /// can't tell (no internet, Google down).
  Future<bool> checkKey() async {
    try {
      await _send(http.Request('GET', _models)..headers.addAll(_auth));
      return true;
    } on GeminiException catch (e) {
      if (e.code == 'gemini_auth') return false;
      rethrow;
    }
  }

  void close() => _client.close();

  /// Sends [request]; any non-2xx answer becomes a [GeminiException].
  Future<http.Response> _send(http.BaseRequest request) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const GeminiException('gemini_network');
    } on http.ClientException {
      throw const GeminiException('gemini_network');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw failureFor(response);
  }

  /// Maps an error response to a [GeminiException].
  static GeminiException failureFor(http.Response response) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    switch (response.statusCode) {
      case 401:
      case 403:
        return const GeminiException('gemini_auth');
      case 400 when body.contains('API_KEY_INVALID'):
        return const GeminiException('gemini_auth');
      case 429:
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        return GeminiException(
          'gemini_quota',
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
      default:
        return const GeminiException('gemini_server');
    }
  }
}
