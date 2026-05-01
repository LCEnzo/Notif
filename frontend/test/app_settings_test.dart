import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppSettingsController> createLoadedSettings() async {
    final settings = AppSettingsController();
    await settings.initialized;
    addTearDown(settings.dispose);
    return settings;
  }

  group('AppSettingsController defaults', () {
    test('default authCardStyle is framed', () async {
      final settings = await createLoadedSettings();

      expect(settings.authCardStyle, AuthCardStyle.framed);
    });

    test('default backendUrlMode is builtin', () async {
      final settings = await createLoadedSettings();

      expect(settings.backendUrlMode, BackendUrlMode.builtin);
    });

    test('default customBackendUrl is empty', () async {
      final settings = await createLoadedSettings();

      expect(settings.customBackendUrl, isEmpty);
    });

    test('default dithering is enabled', () async {
      final settings = await createLoadedSettings();

      expect(settings.designDitheringEnabled, isTrue);
    });

    test('default home density is compact', () async {
      final settings = await createLoadedSettings();

      expect(settings.homeDensity, HomeDensity.compact);
    });
  });

  group('AppSettingsController mutations', () {
    test('setAuthCardStyle updates and persists', () async {
      final settings = await createLoadedSettings();

      await settings.setAuthCardStyle(AuthCardStyle.glass);

      expect(settings.authCardStyle, AuthCardStyle.glass);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('debugAuthCardStyle'), 'glass');
    });

    test('setBackendUrlMode ignores no-op change', () async {
      final settings = await createLoadedSettings();

      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      expect(settings.backendUrlMode, BackendUrlMode.customOnly);

      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      expect(settings.backendUrlMode, BackendUrlMode.customOnly);
    });

    test('setCustomBackendUrl trims input', () async {
      final settings = await createLoadedSettings();

      await settings.setCustomBackendUrl('  https://api.example.com  ');

      expect(settings.customBackendUrl, 'https://api.example.com');
    });

    test('setCustomBackendUrl skips redundant writes', () async {
      final settings = await createLoadedSettings();

      await settings.setCustomBackendUrl('https://api.example.com');
      final prefs = await SharedPreferences.getInstance();
      final initialSet = prefs.getString('customBackendUrl');

      await settings.setCustomBackendUrl('https://api.example.com');
      expect(prefs.getString('customBackendUrl'), initialSet);
    });

    test('setHomeDensity updates and persists', () async {
      final settings = await createLoadedSettings();

      await settings.setHomeDensity(HomeDensity.comfortable);

      expect(settings.homeDensity, HomeDensity.comfortable);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('homeDensity'), 'comfortable');
    });

    test('loads persisted values from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'backendUrlMode': 'customOnly',
        'customBackendUrl': 'https://cached.example.com/v2',
        'debugAuthCardStyle': 'glass',
        'designDitheringEnabled': false,
        'homeDensity': 'dense',
      });

      final settings = await createLoadedSettings();

      expect(settings.backendUrlMode, BackendUrlMode.customOnly);
      expect(settings.customBackendUrl, 'https://cached.example.com/v2');
      expect(settings.authCardStyle, AuthCardStyle.glass);
      expect(settings.designDitheringEnabled, isFalse);
      expect(settings.homeDensity, HomeDensity.dense);
    });

    test('notifies listeners on settings change', () async {
      final settings = await createLoadedSettings();

      var notified = false;
      settings.addListener(() {
        notified = true;
      });

      await settings.setDesignDitheringEnabled(false);

      expect(notified, isTrue);
    });
  });

  test('load falls back to defaults when stored prefs are malformed', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'designDitheringEnabled': 'broken',
      'colorway': NotifColorway.sage.name,
    });

    final settings = await createLoadedSettings();

    expect(settings.loaded, isTrue);
    expect(settings.designDitheringEnabled, isTrue);
    expect(settings.colorway, NotifColorway.dusk1);
    expect(settings.persistenceError, isNotNull);
    expect(settings.persistenceError!.operation, 'load');
  });
}
