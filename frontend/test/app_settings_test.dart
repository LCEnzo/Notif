import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppSettingsController defaults', () {
    test('default authCardStyle is framed', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      expect(settings.authCardStyle, AuthCardStyle.framed);
    });

    test('default backendUrlMode is builtin', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      expect(settings.backendUrlMode, BackendUrlMode.builtin);
    });

    test('default customBackendUrl is empty', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      expect(settings.customBackendUrl, isEmpty);
    });

    test('default dithering is enabled', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      expect(settings.designDitheringEnabled, isTrue);
    });
  });

  group('AppSettingsController mutations', () {
    test('setAuthCardStyle updates and persists', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      await settings.setAuthCardStyle(AuthCardStyle.glass);

      expect(settings.authCardStyle, AuthCardStyle.glass);

      // Verify persistence
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('debugAuthCardStyle'), 'glass');
    });

    test('setBackendUrlMode ignores no-op change', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      expect(settings.backendUrlMode, BackendUrlMode.customOnly);

      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      // Still customOnly — no reset
      expect(settings.backendUrlMode, BackendUrlMode.customOnly);
    });

    test('setCustomBackendUrl trims input', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      await settings.setCustomBackendUrl('  https://api.example.com  ');

      expect(settings.customBackendUrl, 'https://api.example.com');
    });

    test('setCustomBackendUrl skips redundant writes', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      await settings.setCustomBackendUrl('https://api.example.com');
      final prefs = await SharedPreferences.getInstance();
      final initialSet = prefs.getString('customBackendUrl');

      await settings.setCustomBackendUrl('https://api.example.com');
      // Should not have changed
      expect(prefs.getString('customBackendUrl'), initialSet);
    });

    test('loads persisted values from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'backendUrlMode': 'customOnly',
        'customBackendUrl': 'https://cached.example.com/v2',
        'debugAuthCardStyle': 'glass',
        'designDitheringEnabled': false,
      });

      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      expect(settings.backendUrlMode, BackendUrlMode.customOnly);
      expect(settings.customBackendUrl, 'https://cached.example.com/v2');
      expect(settings.authCardStyle, AuthCardStyle.glass);
      expect(settings.designDitheringEnabled, isFalse);
    });

    test('notifies listeners on settings change', () async {
      final settings = AppSettingsController();
      await Future<void>.delayed(Duration.zero);

      var notified = false;
      settings.addListener(() {
        notified = true;
      });

      await settings.setDesignDitheringEnabled(false);

      expect(notified, isTrue);
    });
  });
}
