import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/notif_theme.dart';
import 'package:notif/screens/starting.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/session_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/auth_test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(resetApiAuth);

  AuthService cookieService() => AuthService(
    store: const PlatformOwnedSessionStore(),
    transport: SessionTransport.cookie,
    maxRecoveryProbes: 0,
  );

  Future<void> pumpStarting(WidgetTester tester, AuthService auth) async {
    final settings = AppSettingsController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: MaterialApp(
          theme: buildNotifTheme(
            colorway: settings.colorway,
            fontSet: settings.fontSet,
          ),
          home: const StartingPage(),
        ),
      ),
    );
  }

  testWidgets('a config error offers settings, not just a doomed retry', (
    WidgetTester tester,
  ) async {
    final settings = AppSettingsController();
    final auth = cookieService()..updateSettings(settings);
    addTearDown(auth.dispose);
    // Real async: the restore path must run on the live event loop, not the
    // test's fake-async zone, or its futures never complete.
    await tester.runAsync(() async {
      await settings.initialized;
      await settings.setBackendUrlMode(BackendUrlMode.customOnly);
      await auth.restore();
    });
    expect(auth.state, isA<AuthConfigError>());

    await pumpStarting(tester, auth);

    expect(find.text('BACKEND MISCONFIGURED'), findsOneWidget);
    expect(find.text('OPEN SETTINGS'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);
  });

  testWidgets('an outage offers retry without a settings shortcut', (
    WidgetTester tester,
  ) async {
    final adapter = FakeApiAdapter();
    final original = apiHttpClientAdapter;
    apiHttpClientAdapter = adapter;
    addTearDown(() => apiHttpClientAdapter = original);
    adapter.enqueue('/get_my_info/', const FakeReply.offline());
    final auth = cookieService();
    addTearDown(auth.dispose);
    // Real async: the probe goes through dio, whose timers only fire on the
    // live event loop — awaited in the fake-async zone it hangs forever.
    await tester.runAsync(auth.restore);
    expect(auth.state, isA<AuthUnavailable>());

    await pumpStarting(tester, auth);

    expect(find.text('BACKEND UNREACHABLE'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('OPEN SETTINGS'), findsNothing);
  });
}
