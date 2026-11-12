import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:habit_loop/core/services/gemini_client.dart';

void main() {
  group('GeminiClient.checkKey', () {
    Future<Object> check(http.Response Function() respond) async {
      final client = MockClient((_) async => respond());
      try {
        return await GeminiClient(apiKey: 'k', client: client).checkKey();
      } on GeminiException catch (e) {
        return e.code;
      }
    }

    test('accepts a key Google accepts', () async {
      expect(await check(() => http.Response('{"models":[]}', 200)), isTrue);
    });

    test('rejects a bad key', () async {
      expect(
        await check(() => http.Response('{"reason":"API_KEY_INVALID"}', 400)),
        isFalse,
      );
      expect(await check(() => http.Response('', 403)), isFalse);
    });

    test("can't tell without internet or with Google down", () async {
      expect(
        await check(() => throw http.ClientException('offline')),
        'gemini_network',
      );
      expect(await check(() => http.Response('', 500)), 'gemini_busy');
    });
  });

  test('a rate limit keeps the wait Google asked for', () {
    final e = GeminiClient.failureFor(
      http.Response('', 429, headers: {'retry-after': '7'}),
    );
    expect(e.code, 'gemini_quota');
    expect(e.retryAfter, const Duration(seconds: 7));
  });

  test("an unexpected error keeps Google's message", () {
    final e = GeminiClient.failureFor(
      http.Response(
        '{"error":{"code":400,"message":"Unknown name \\"x\\"."}}',
        400,
      ),
    );
    expect(e.code, 'gemini_server');
    expect(e.detail, startsWith('400: Unknown name'));
  });
}
