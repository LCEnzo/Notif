import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppSettingsController> createLoadedSettings() async {
    final settings = AppSettingsController();
    await settings.initialized;
    return settings;
  }

  group('resolveUrls', () {
    test('null settings returns builtin base URL only', () {
      final urls = resolveUrls('/auth/login', null);

      expect(urls, hasLength(1));
      expect(urls.first, builtinApiUrl);
    });

    test('builtin mode returns builtin base URL only', () async {
      final settings = await createLoadedSettings();

      final urls = resolveUrls('/ping', settings);

      expect(urls, hasLength(1));
      expect(urls.first, builtinApiUrl);
    });

    test('customWithFallback returns custom first, then builtin', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customWithFallback);
      await settings.setCustomBackendUrl('https://example.com/api/v1');

      final urls = resolveUrls('/status', settings);

      expect(urls, hasLength(2));
      expect(urls[0], 'https://example.com/api/v1');
      expect(urls[1], builtinApiUrl);
    });

    test('customOnly returns custom base URL only', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await settings.setCustomBackendUrl('https://prod.example.com/api');

      final urls = resolveUrls('/health', settings);

      expect(urls, hasLength(1));
      expect(urls.first, 'https://prod.example.com/api');
    });

    test('customWithFallback with empty custom falls back to builtin',
        () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customWithFallback);
      // customBackendUrl is empty by default

      final urls = resolveUrls('/users', settings);

      expect(urls, hasLength(1));
      expect(urls.first, builtinApiUrl);
    });

    test('customOnly with empty custom returns empty list', () async {
      final settings = await createLoadedSettings();
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      // customBackendUrl is empty by default

      final urls = resolveUrls('/users', settings);

      expect(urls, isEmpty);
    });

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
          isA<StateError>().having(
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

      final urls = resolveUrls('/ping', settings);

      expect(urls, hasLength(1));
      expect(urls.first, 'https://trim.example.com/api');
    });

    test('builtin base URL returned for any path', () async {
      final urls = resolveUrls('/search?q=test&page=2', null);

      expect(urls, hasLength(1));
      expect(urls.first, builtinApiUrl);
    });

    test('customOnly from SharedPreferences preloaded values', () async {
      SharedPreferences.setMockInitialValues({
        'backendUrlMode': 'customOnly',
        'customBackendUrl': 'https://cached.example.com/v2',
      });

      final settings = await createLoadedSettings();

      final urls = resolveUrls('/data', settings);

      expect(urls, hasLength(1));
      expect(urls.first, 'https://cached.example.com/v2');
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
        data: [{'a': 1}, {'b': 2}],
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
