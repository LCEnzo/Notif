import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load falls back to defaults when stored prefs are malformed', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'designDitheringEnabled': 'broken',
      'colorway': NotifColorway.sage.name,
    });

    final controller = AppSettingsController();
    addTearDown(controller.dispose);

    await _waitUntilLoaded(controller);

    expect(controller.loaded, isTrue);
    expect(controller.designDitheringEnabled, isTrue);
    expect(controller.colorway, NotifColorway.dusk1);
    expect(controller.colorScheme, NotifColorway.dusk1.defaultScheme);
    expect(controller.persistenceError, isNotNull);
    expect(controller.persistenceError!.operation, 'load');
  });
}

Future<void> _waitUntilLoaded(AppSettingsController controller) async {
  for (var i = 0; i < 20 && !controller.loaded; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  if (!controller.loaded) {
    fail('AppSettingsController did not finish loading.');
  }
}
