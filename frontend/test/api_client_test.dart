import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';
import 'support/in_memory_secure_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    overrideSecureStore(InMemorySecureStore());
    resetApiAuthForTesting();
  });

  tearDown(() {
    overrideSecureStore(null);
    resetApiAuthForTesting();
    apiDio.httpClientAdapter = HttpClientAdapter();
  });

  Future<AppSettingsController> createLoadedSettings() async {
    final settings = AppSettingsController();
    await settings.initialized;
    return settings;
  }

  Future<AppSettingsController> createFallbackSettings(String custom) async {
    final settings = await createLoadedSettings();
    await settings.setBackendUrlMode(BackendUrlMode.customWithFallback);
    await settings.setCustomBackendUrl(custom);
    return settings;
  }

  group('resolveUrls', () {
    test('null settings returns builtin base URL only', () {
      final urls = resolveUrls(null);

      expect(urls, hasLength(1));
      expect(urls.first, builtinApiUrl);
    });

    test('builtin mode returns builtin base URL only', () async {
      final settings = await createLoadedSettings();

      final urls = resolveUrls(settings);

      expect(urls, hasLength(1));
      expect(urls.first, builtinApiUrl);
    });

    test('customWithFallback returns custom first, then builtin', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customWithFallback);
      await settings.setCustomBackendUrl('https://example.com/api/v1');

      final urls = resolveUrls(settings);

      expect(urls, hasLength(2));
      expect(urls[0], 'https://example.com/api/v1');
      expect(urls[1], builtinApiUrl);
    });

    test('customOnly returns custom base URL only', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await settings.setCustomBackendUrl('https://prod.example.com/api');

      final urls = resolveUrls(settings);

      expect(urls, hasLength(1));
      expect(urls.first, 'https://prod.example.com/api');
    });

    test(
      'customWithFallback with empty custom falls back to builtin',
      () async {
        final settings = await createLoadedSettings();
        await settings.setBackendUrlMode(BackendUrlMode.customWithFallback);
        // customBackendUrl is empty by default

        final urls = resolveUrls(settings);

        expect(urls, hasLength(1));
        expect(urls.first, builtinApiUrl);
      },
    );

    test('customOnly with empty custom returns empty list', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      // customBackendUrl is empty by default

      final urls = resolveUrls(settings);

      expect(urls, isEmpty);
    });

    test(
      'customWithFallback with custom equal to builtin is one destination',
      () async {
        final settings = await createFallbackSettings(builtinApiUrl);

        final urls = resolveUrls(settings);

        expect(urls, [builtinApiUrl]);
      },
    );

    test('apiPost fails clearly when customOnly has no custom URL', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);

      await expectLater(
        () => apiPost(
          '/token/',
          settings: settings,
          headers: const {'Content-Type': 'application/json'},
          body: '{}',
        ),
        throwsA(
          isA<ApiClientException>().having(
            (error) => error.message,
            'message',
            contains('POST /token/ failed: no backend URL configured'),
          ),
        ),
      );
    });

    test('custom base URL is trimmed', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await settings.setCustomBackendUrl('  https://trim.example.com/api  ');

      final urls = resolveUrls(settings);

      expect(urls, hasLength(1));
      expect(urls.first, 'https://trim.example.com/api');
    });

    test('customOnly from SharedPreferences preloaded values', () async {
      SharedPreferences.setMockInitialValues({
        'backendUrlMode': 'customOnly',
        'customBackendUrl': 'https://cached.example.com/v2',
      });

      final settings = await createLoadedSettings();

      final urls = resolveUrls(settings);

      expect(urls, hasLength(1));
      expect(urls.first, 'https://cached.example.com/v2');
    });
  });

  group('fallback safety for non-replayable auth calls', () {
    const custom = 'https://custom.example.com/api/v1';

    test('refresh POST is never re-sent after a receive timeout', () async {
      final settings = await createFallbackSettings(custom);
      final adapter = FakeHttpAdapter(
        (options) => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 15),
          requestOptions: options,
        ),
      );
      apiDio.httpClientAdapter = adapter;

      await expectLater(
        () => apiPost(
          '/token/refresh/',
          settings: settings,
          headers: const {'Content-Type': 'application/json'},
          body: const <String, Object?>{},
        ),
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.receiveTimeout,
          ),
        ),
      );

      expect(
        adapter.requests,
        hasLength(1),
        reason:
            'the rotation may already have been committed; a replay trips '
            'theft detection and revokes the whole token family',
      );
      expect(adapter.requests.single.uri.host, 'custom.example.com');
    });

    test('refresh POST is never re-sent after a dropped connection', () async {
      final settings = await createFallbackSettings(custom);
      final adapter = FakeHttpAdapter(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'The XMLHttpRequest onError callback was called.',
        ),
      );
      apiDio.httpClientAdapter = adapter;

      await expectLater(
        () => apiPost(
          '/token/refresh/',
          settings: settings,
          headers: const {'Content-Type': 'application/json'},
          body: const <String, Object?>{},
        ),
        throwsA(isA<DioException>()),
      );

      expect(adapter.requests, hasLength(1));
    });

    test('logout POST is never re-sent after a receive timeout', () async {
      final settings = await createFallbackSettings(custom);
      final adapter = FakeHttpAdapter(
        (options) => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 15),
          requestOptions: options,
        ),
      );
      apiDio.httpClientAdapter = adapter;

      await expectLater(
        () => apiPost(
          '/token/logout/',
          settings: settings,
          headers: const {'Content-Type': 'application/json'},
          body: const <String, Object?>{},
        ),
        throwsA(isA<DioException>()),
      );

      expect(adapter.requests, hasLength(1));
    });

    test('refresh POST still falls back when no connection was made', () async {
      final settings = await createFallbackSettings(custom);
      final adapter = FakeHttpAdapter((options) {
        if (options.uri.host == 'custom.example.com') {
          throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 10),
            requestOptions: options,
          );
        }
        return jsonResponse({'access': 'fresh-token'});
      });
      apiDio.httpClientAdapter = adapter;

      final response = await apiPost(
        '/token/refresh/',
        settings: settings,
        headers: const {'Content-Type': 'application/json'},
        body: const <String, Object?>{},
      );

      expect(response.statusCode, 200);
      expect(adapter.requests, hasLength(2));
    });

    test('idempotent GET still falls back after a receive timeout', () async {
      final settings = await createFallbackSettings(custom);
      final adapter = FakeHttpAdapter((options) {
        if (options.uri.host == 'custom.example.com') {
          throw DioException.receiveTimeout(
            timeout: const Duration(seconds: 15),
            requestOptions: options,
          );
        }
        return jsonResponse({'status': 'ok'});
      });
      apiDio.httpClientAdapter = adapter;

      final response = await apiGet(
        healthPath,
        settings: settings,
        headers: const {'Content-Type': 'application/json'},
      );

      expect(response.statusCode, 200);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.uri.toString(), contains(builtinApiUrl));
    });

    test('a custom URL equal to builtin is only requested once', () async {
      final settings = await createFallbackSettings(builtinApiUrl);
      final adapter = FakeHttpAdapter(
        (options) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 10),
          requestOptions: options,
        ),
      );
      apiDio.httpClientAdapter = adapter;

      await expectLater(
        () => apiGet(
          healthPath,
          settings: settings,
          headers: const {'Content-Type': 'application/json'},
        ),
        throwsA(isA<DioException>()),
      );

      expect(adapter.requests, hasLength(1));
    });
  });

  group('crossSiteBackendOrigin', () {
    test('flags a cross-site custom backend on web', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await settings.setCustomBackendUrl('https://api.other.test/api/v1');

      expect(
        crossSiteBackendOrigin(
          settings,
          isWeb: true,
          pageUri: Uri.parse('https://app.example.test/home'),
        ),
        'https://api.other.test',
      );
    });

    test('same-site subdomains and same host are not flagged', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await settings.setCustomBackendUrl('https://api.example.test/api/v1');

      expect(
        crossSiteBackendOrigin(
          settings,
          isWeb: true,
          pageUri: Uri.parse('https://app.example.test/home'),
        ),
        isNull,
      );
    });

    test('relative same-origin API base is not flagged', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await settings.setCustomBackendUrl('https://app.example.test/api/v1');

      expect(
        crossSiteBackendOrigin(
          settings,
          isWeb: true,
          pageUri: Uri.parse('https://app.example.test/home'),
        ),
        isNull,
      );
    });

    test('native builds are never flagged', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await settings.setCustomBackendUrl('https://api.other.test/api/v1');

      expect(
        crossSiteBackendOrigin(
          settings,
          isWeb: false,
          pageUri: Uri.parse('https://app.example.test/home'),
        ),
        isNull,
      );
    });
  });

  group('expectSuccessJson', () {
    test('extracts data on 200 with Map body', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
        data: {'key': 'value'},
      );

      final result = expectSuccessJson(response, 'Test');

      expect(result, {'key': 'value'});
    });

    test('throws on non-200 status', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 500,
        data: 'Internal error',
      );

      expect(
        () => expectSuccessJson(response, 'Test'),
        throwsA(isA<Exception>()),
      );
    });

    test('throws on 200 with non-Map body', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
        data: 'not a map',
      );

      expect(
        () => expectSuccessJson(response, 'Test'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('expectSuccessList', () {
    test('extracts list on 200', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
        data: [
          {'a': 1},
          {'b': 2},
        ],
      );

      final result = expectSuccessList(response, 'Test');

      expect(result, hasLength(2));
    });

    test('throws on 200 with non-List body', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
        data: {'not': 'a list'},
      );

      expect(
        () => expectSuccessList(response, 'Test'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('expectSuccessStatus', () {
    test('passes when status is in successCodes', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 201,
      );

      // Should not throw
      expectSuccessStatus(response, 'Test', successCodes: const {200, 201});
    });

    test('passes on 2xx by default', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 204,
      );

      expectSuccessStatus(response, 'Test');
    });

    test('throws on non-2xx by default', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 404,
      );

      expect(
        () => expectSuccessStatus(response, 'Test'),
        throwsA(isA<Exception>()),
      );
    });

    test('throws on null status code', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
      );

      expect(
        () => expectSuccessStatus(response, 'Test'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
