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

  testWidgets('a URL the client would refuse is rejected at settings time', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'backendUrlMode': BackendUrlMode.customOnly.name,
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

    // VM tests exercise the native rule: a bearer token must not travel over
    // non-loopback plain http, so settings must refuse to store such a URL.
    await tester.enterText(
      find.byType(TextField),
      'http://192.168.1.50:42069/api/v1',
    );
    await tester.pump();

    expect(settings.customBackendUrl, isEmpty);
    expect(find.textContaining('HTTPS'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://notif.example.com/api/v1',
    );
    await tester.pump();

    expect(settings.customBackendUrl, 'https://notif.example.com/api/v1');
    expect(find.textContaining('HTTPS'), findsNothing);
  });
}
