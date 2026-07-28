import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

/// Pins the auth state machine's failure policy: only a server that actively
/// rejects the refresh cookie may end a session. Transport trouble — timeouts,
/// an unreachable backend — keeps the session and lets a later request retry,
/// and a cold start that cannot refresh is anonymous, not expired.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetApiAuthForTesting();
  });

  tearDown(() {
    resetApiAuthForTesting();
    apiDio.httpClientAdapter = HttpClientAdapter();
  });

  Future<(AuthService, AppSettingsController)> service(
    FakeHttpHandler handler,
  ) async {
    apiDio.httpClientAdapter = FakeHttpAdapter(handler);

    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await settings.initialized;

    final auth = AuthService();
    addTearDown(auth.dispose);
    auth.updateSettings(settings);
    return (auth, settings);
  }

  Future<void> authedRequestExpecting401(
    AuthService auth,
    AppSettingsController settings,
  ) async {
    await expectLater(
      apiGet(
        '/accounts/users/me/',
        settings: settings,
        headers: {'Authorization': 'Bearer ${auth.jwt!.access}'},
      ),
      throwsA(isA<DioException>()),
    );
  }

  test('login lands in AuthAuthenticated with the returned token', () async {
    final (auth, _) = await service(
      (_) => jsonResponse(const {'access': 'access-1'}),
    );

    await auth.loginWithRememberMe('user', 'pass', rememberMe: true);

    expect(auth.state, isA<AuthAuthenticated>());
    expect(auth.jwt?.access, 'access-1');
  });

  test('a rejected refresh mid-session expires it', () async {
    final (auth, settings) = await service((options) {
      final path = options.uri.path;
      if (path.endsWith('/token/')) {
        return jsonResponse(const {'access': 'access-1'});
      }
      if (path.endsWith('/token/refresh/')) {
        return jsonResponse(const {
          'detail': 'Session revoked.',
        }, statusCode: 401);
      }
      return jsonResponse(const {'detail': 'Token expired.'}, statusCode: 401);
    });
    await auth.loginWithRememberMe('user', 'pass', rememberMe: true);

    await authedRequestExpecting401(auth, settings);

    expect(auth.state, isA<AuthExpired>());
    expect(auth.jwt, isNull);
  });

  test('a refresh that cannot reach the server keeps the session', () async {
    final (auth, settings) = await service((options) {
      final path = options.uri.path;
      if (path.endsWith('/token/')) {
        return jsonResponse(const {'access': 'access-1'});
      }
      if (path.endsWith('/token/refresh/')) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'backend unreachable',
        );
      }
      return jsonResponse(const {'detail': 'Token expired.'}, statusCode: 401);
    });
    await auth.loginWithRememberMe('user', 'pass', rememberMe: true);

    await authedRequestExpecting401(auth, settings);

    expect(auth.state, isA<AuthAuthenticated>());
    expect(auth.jwt?.access, 'access-1');
  });

  test(
    'a cold start whose refresh is rejected is anonymous, not expired',
    () async {
      final (auth, _) = await service(
        (_) => jsonResponse(const {'detail': 'No session.'}, statusCode: 401),
      );

      await auth.restoreRememberedSession();

      expect(auth.state, isA<AuthAnonymous>());
    },
  );

  test('a cold start that cannot reach the server stays anonymous', () async {
    final (auth, _) = await service(
      (options) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'backend unreachable',
      ),
    );

    await auth.restoreRememberedSession();

    expect(auth.state, isA<AuthAnonymous>());
  });

  test('a successful restore lands in AuthAuthenticated', () async {
    final (auth, _) = await service(
      (_) => jsonResponse(const {'access': 'access-2'}),
    );

    await auth.restoreRememberedSession();

    expect(auth.state, isA<AuthAuthenticated>());
    expect(auth.jwt?.access, 'access-2');
  });
}
