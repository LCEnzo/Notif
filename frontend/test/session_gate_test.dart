import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/notif_theme.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/persistence.dart';
import 'package:notif/services/refresh_cookie_store.dart';
import 'package:notif/services/router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';
import 'support/in_memory_secure_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    overrideSecureStore(InMemorySecureStore());
    resetRefreshCookieStoreForTesting();
    resetApiAuthForTesting();
  });

  tearDown(() {
    overrideSecureStore(null);
    resetRefreshCookieStoreForTesting();
    resetApiAuthForTesting();
    apiDio.httpClientAdapter = HttpClientAdapter();
  });

  Future<void> pumpApp(WidgetTester tester, AuthService auth) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await settings.initialized;
    final router = createRouter(auth);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthService>.value(value: auth),
        ],
        child: MaterialApp.router(
          theme: buildNotifTheme(
            colorway: settings.colorway,
            fontSet: settings.fontSet,
          ),
          routerConfig: router,
        ),
      ),
    );
    auth.updateSettings(settings);
    await tester.pump();
  }

  testWidgets('a remembered cold start waits on a splash, not the login form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'hasRememberedSession': true});
    final refreshGate = Completer<ResponseBody>();
    apiDio.httpClientAdapter = FakeHttpAdapter((options) => refreshGate.future);
    final auth = AuthService(
      restoreSessionOnStart: true,
      recoveryBackoff: const [],
    );
    addTearDown(auth.dispose);

    await pumpApp(tester, auth);
    await tester.pump();

    expect(find.byKey(const Key('sessionRestoreSplash')), findsOneWidget);
    expect(
      find.text('Log in'),
      findsNothing,
      reason: 'the login screen must not flash before the session lands',
    );

    refreshGate.complete(
      jsonResponse({'detail': 'invalid'}, statusCode: 401),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sessionRestoreSplash')), findsNothing);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('a first-ever visit lands on the login form', (tester) async {
    apiDio.httpClientAdapter = FakeHttpAdapter(
      (options) => jsonResponse({'access': 'unexpected'}),
    );
    final auth = AuthService(
      restoreSessionOnStart: true,
      recoveryBackoff: const [],
    );
    addTearDown(auth.dispose);

    await pumpApp(tester, auth);
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsOneWidget);
    expect(auth.state, isA<AuthAnonymous>());
  });

  testWidgets('an unreachable backend explains itself on the login screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'hasRememberedSession': true});
    var attempts = 0;
    apiDio.httpClientAdapter = FakeHttpAdapter((options) {
      attempts += 1;
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
      );
    });
    final auth = AuthService(
      restoreSessionOnStart: true,
      // No automatic retries: this test drives the manual path.
      recoveryBackoff: const [],
    );
    addTearDown(auth.dispose);

    await pumpApp(tester, auth);
    await tester.pumpAndSettle();

    expect(auth.state, isA<AuthUnavailable>());
    expect(find.byKey(const Key('authSessionNotice')), findsOneWidget);
    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    expect(
      find.textContaining('XMLHttpRequest'),
      findsNothing,
      reason: 'transport internals are for logs, not users',
    );

    final attemptsBeforeRetry = attempts;
    await tester.tap(find.byKey(const Key('authSessionRetry')));
    await tester.pumpAndSettle();

    expect(
      attempts,
      greaterThan(attemptsBeforeRetry),
      reason: 'the retry action must actually re-attempt the restore',
    );
  });
}
