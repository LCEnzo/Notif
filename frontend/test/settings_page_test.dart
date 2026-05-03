import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/notif_theme.dart';
import 'package:notif/screens/settings.dart';
import 'package:notif/services/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('backend URL field reflects persisted settings after load', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'backendUrlMode': BackendUrlMode.customOnly.name,
      'customBackendUrl': 'https://cached.example.com/v2',
      'designDitheringEnabled': false,
    });
    final settings = AppSettingsController();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: buildNotifTheme(
            colorway: settings.colorway,
            fontSet: settings.fontSet,
          ),
          home: const SettingsPage(),
        ),
      ),
    );

    await settings.initialized;
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'https://cached.example.com/v2');
  });
}
