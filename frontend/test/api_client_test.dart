import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('resolveUrls', () {
    test('null settings returns builtin URL only', () {
      final urls = resolveUrls('/auth/login', null);

      expect(urls, hasLength(1));
      expect(urls.first, '$builtinApiUrl/auth/login');
    });

    test('builtin mode returns builtin URL only', () async {
      final settings = AppSettingsController();
      // default mode is builtin
      await Future<void>.delayed(Duration.zero);

      final urls = resolveUrls('/ping', settings);

      expect(urls, hasLength(1));
      expect(urls.first, '$builtinApiUrl/ping');
    });

    test('customWithFallback returns custom first, then builtin', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);
      await settings.setBackendUrlMode(BackendUrlMode.customWithFallback);
      await settings.setCustomBackendUrl('https://example.com/api/v1');

      final urls = resolveUrls('/status', settings);

      expect(urls, hasLength(2));
      expect(urls[0], 'https://example.com/api/v1/status');
      expect(urls[1], '$builtinApiUrl/status');
    });

    test('customOnly returns custom URL only', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await settings.setCustomBackendUrl('https://prod.example.com/api');

      final urls = resolveUrls('/health', settings);

      expect(urls, hasLength(1));
      expect(urls.first, 'https://prod.example.com/api/health');
    });

    test('customWithFallback with empty custom falls back to builtin',
        () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);
      await settings.setBackendUrlMode(BackendUrlMode.customWithFallback);
      // customBackendUrl is empty by default

      final urls = resolveUrls('/users', settings);

      expect(urls, hasLength(1));
      expect(urls.first, '$builtinApiUrl/users');
    });

    test('customOnly with empty custom returns empty list', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);
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
          headers: jsonHeaders,
          body: '{}',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('No API URL resolved for POST /token/'),
          ),
        ),
      );
    });

    test('custom URL is trimmed', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await settings.setCustomBackendUrl('  https://trim.example.com/api  ');

      final urls = resolveUrls('/ping', settings);

      expect(urls, hasLength(1));
      expect(urls.first, 'https://trim.example.com/api/ping');
    });

    test('path with query parameters is preserved', () async {
      final urls = resolveUrls('/search?q=test&page=2', null);

      expect(urls, hasLength(1));
      expect(urls.first, '$builtinApiUrl/search?q=test&page=2');
    });

    test('builtin mode from SharedPreferences preloaded values', () async {
      SharedPreferences.setMockInitialValues({
        'backendUrlMode': 'customOnly',
        'customBackendUrl': 'https://cached.example.com/v2',
      });

      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      final urls = resolveUrls('/data', settings);

      expect(urls, hasLength(1));
      expect(urls.first, 'https://cached.example.com/v2/data');
    });
  });
}
