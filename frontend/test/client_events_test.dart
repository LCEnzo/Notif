import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('reports to the failing API base without sending the session', () async {
    final settings = AppSettingsController();
    await settings.initialized;
    await settings.setCustomBackendUrl('https://custom.example/api/v1');
    await settings.setBackendUrlMode(BackendUrlMode.customWithFallback);
    addTearDown(settings.dispose);
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
  });
}
