import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/generated/openapi.swagger.dart' as api;
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/client_events.dart';
import 'package:notif/services/session_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/auth_test_harness.dart';

void main() {
  late HttpClientAdapter originalAdapter;
  late FakeApiAdapter adapter;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Notif',
      packageName: 'com.example.notif',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    originalAdapter = apiHttpClientAdapter;
    adapter = FakeApiAdapter();
    apiHttpClientAdapter = adapter;
  });

  tearDown(() {
    apiHttpClientAdapter = originalAdapter;
    resetApiAuth();
  });

  Future<AppSettingsController> customSettings() async {
    final settings = AppSettingsController();
    await settings.initialized;
    await settings.setCustomBackendUrl('https://custom.example/api/v1');
    await settings.setBackendUrlMode(BackendUrlMode.customWithFallback);
    addTearDown(settings.dispose);
    return settings;
  }

  test('reports to the failing API base without sending the session', () async {
    final settings = await customSettings();
    configureApiAuth(
      credentialReader: () => const SessionCredential(
        token: 'must-not-leak',
        origin: 'https://custom.example',
      ),
    );
    adapter.enqueue(
      '/client-events/',
      const FakeReply(statusCode: 202, body: {'status': 'accepted'}),
    );
    final requestOptions = RequestOptions(
      path: '/api/v1/ops/events/',
      baseUrl: 'https://custom.example',
    );

    await reportClientFailure(
      settings: settings,
      error: DioException.connectionError(
        requestOptions: requestOptions,
        reason: 'offline',
      ),
      endpoint: 'GET /ops/events/',
    );

    final request = adapter.requestFor('/client-events/');
    expect(request.uri.origin, 'https://custom.example');
    expect(request.uri.path, '/api/v1/client-events/');
    expect(request.authorization, isNull);
    final body = request.body! as Map<String, dynamic>;
    expect(body['category'], 'network_unavailable');
    expect(body['endpoint'], 'GET /ops/events/');
    expect(body['app_version'], '1.0.0+1');
    expect(body.values, isNot(contains(isNull)));
  });

  test('an overlong failure message is clipped, not dropped', () async {
    final settings = await customSettings();
    adapter.enqueue('/client-events/', const FakeReply(statusCode: 202));

    await reportClientFailure(
      settings: settings,
      error: Exception('x' * 600),
    );

    final body =
        adapter.requestFor('/client-events/').body! as Map<String, dynamic>;
    expect(body['category'], 'unexpected_failure');
    expect(body['message'], 'x' * 500);
  });

  group('clientEventBody', () {
    test('omits absent fields instead of sending null', () {
      final body = clientEventBody(
        const api.ClientEventRequest(
          category: api.CategoryEnum.timeout,
          message: 'slow',
        ),
      );

      expect(body, {'category': 'timeout', 'message': 'slow'});
    });

    test('clips at the limit and not one below it', () {
      final body = clientEventBody(
        api.ClientEventRequest(
          category: api.CategoryEnum.contractViolation,
          message: 'm' * 500,
          actual: 'a' * 501,
          stack: 's' * 2001,
          appVersion: 'v' * 60,
        ),
      );

      expect(body['message'], 'm' * 500);
      expect(body['actual'], 'a' * 500);
      expect(body['stack'], 's' * 2000);
      expect(body['app_version'], 'v' * 60);
    });
  });

  group('clipToLength', () {
    const emoji = '\u{1F600}';

    test('leaves a string at the limit alone', () {
      expect(clipToLength('${'a' * 498}$emoji', 500), '${'a' * 498}$emoji');
    });

    test('drops a surrogate pair that straddles the limit', () {
      expect(clipToLength('${'a' * 499}$emoji', 500), 'a' * 499);
    });

    test('keeps a surrogate pair that ends exactly at the limit', () {
      expect(clipToLength('${'a' * 498}${emoji}b', 500), '${'a' * 498}$emoji');
    });

    test('agrees with a code-point oracle on random mixed-width text', () {
      // Independent oracle: whole code points while they fit, counted in
      // UTF-16 units, the way Dart's String.length counts.
      String oracle(String value, int max) {
        final out = StringBuffer();
        var units = 0;
        for (final rune in value.runes) {
          final width = rune > 0xFFFF ? 2 : 1;
          if (units + width > max) break;
          out.writeCharCode(rune);
          units += width;
        }
        return out.toString();
      }

      const alphabet = ['a', 'é', '中', emoji, '\u{1D11E}'];
      final random = Random(78);
      for (var i = 0; i < 2000; i++) {
        final text = List.generate(
          random.nextInt(24),
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join();
        final max = random.nextInt(text.length + 3);
        final clipped = clipToLength(text, max);

        expect(clipped, oracle(text, max), reason: 'text=$text max=$max');
        expect(clipped.runes.length, lessThanOrEqualTo(max));
      }
    });
  });

  test("limits match the schema's ClientEventRequest maxLength", () {
    final schema =
        jsonDecode(File('../backend/openapi.json').readAsStringSync())
            as Map<String, dynamic>;
    final components = schema['components'] as Map<String, dynamic>;
    final schemas = components['schemas'] as Map<String, dynamic>;
    final request = schemas['ClientEventRequest'] as Map<String, dynamic>;
    final properties = request['properties'] as Map<String, dynamic>;
    final schemaLimits = {
      for (final MapEntry(:key, :value) in properties.entries)
        if ((value as Map<String, dynamic>)['maxLength'] != null)
          key: value['maxLength'] as int,
    };

    expect(clientEventFieldLimits, schemaLimits);
    expect(
      properties.keys.toSet().difference(schemaLimits.keys.toSet()),
      {'category'},
      reason: 'Every free-text field needs a limit here.',
    );
  });
}
