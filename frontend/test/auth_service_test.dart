import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/persistence.dart';
import 'package:notif/services/refresh_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';
import 'support/in_memory_secure_store.dart';

const String _rememberedSessionKey = 'hasRememberedSession';

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

  Future<AppSettingsController> loadedSettings() async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await settings.initialized;
    return settings;
  }

  AuthService createService({
    bool restoreSessionOnStart = false,
    List<Duration>? recoveryBackoff,
    CrossSiteBackendProbe? crossSiteBackendProbe,
  }) {
    final service = AuthService(
      restoreSessionOnStart: restoreSessionOnStart,
      // Default: no automatic retries, so tests that do not exercise recovery
      // never leave timers running.
      recoveryBackoff: recoveryBackoff ?? const [],
      crossSiteBackendProbe: crossSiteBackendProbe,
    );
    addTearDown(service.dispose);
    return service;
  }

  /// Answers the login endpoint and delegates everything else.
  FakeHttpAdapter install(FakeHttpHandler handler) {
    final adapter = FakeHttpAdapter(handler);
    apiDio.httpClientAdapter = adapter;
    return adapter;
  }

  bool isLogin(RequestOptions options) =>
      options.uri.path.endsWith('/token/') && options.method == 'POST';
  bool isRefresh(RequestOptions options) =>
      options.uri.path.endsWith('/token/refresh/');
  bool isHealth(RequestOptions options) =>
      options.uri.path.endsWith('/monitoring/health/');

  Future<void> triggerRefresh(AuthService auth) async {
    try {
      await auth.refreshToken();
    } on Exception {
      // The failure surfaces through auth state, which is what the tests read.
    }
  }

  Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue, reason: 'condition not met within $timeout');
  }

  Future<AuthService> signedInService({
    required FakeHttpHandler handler,
    List<Duration>? recoveryBackoff,
    CrossSiteBackendProbe? crossSiteBackendProbe,
  }) async {
    final settings = await loadedSettings();
    install((options) {
      if (isLogin(options)) {
        return jsonResponse({'access': 'access-1'});
      }
      return handler(options);
    });
    final auth = createService(
      recoveryBackoff: recoveryBackoff,
      crossSiteBackendProbe: crossSiteBackendProbe,
    );
    auth.updateSettings(settings);
    await auth.loginWithRememberMe('user', 'pass', rememberMe: true);
    expect(auth.state, isA<AuthAuthenticated>());
    return auth;
  }

  group('an unreachable backend is not a logout', () {
    test('a refused connection keeps the session and stays retryable',
        () async {
      final auth = await signedInService(
        handler: (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection refused',
        ),
      );

      await triggerRefresh(auth);

      expect(auth.state, isA<AuthUnavailable>());
      expect(
        auth.jwt?.access,
        'access-1',
        reason: 'a backend that is merely down has not rejected anything',
      );
      final failure = auth.sessionUnavailableFailure;
      expect(failure?.category, FailureCategory.networkUnavailable);
      expect(failure?.isRetryable, isTrue);
    });

    test('a 502 from the gateway keeps the session', () async {
      final auth = await signedInService(
        handler: (options) => jsonResponse(
          {'detail': 'Bad Gateway'},
          statusCode: 502,
        ),
      );

      await triggerRefresh(auth);

      expect(auth.state, isA<AuthUnavailable>());
      expect(auth.jwt?.access, 'access-1');
      expect(
        auth.sessionUnavailableFailure?.category,
        FailureCategory.sourceBlockedDegraded,
      );
    });

    test('a receive timeout keeps the session', () async {
      final auth = await signedInService(
        handler: (options) => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 15),
          requestOptions: options,
        ),
      );

      await triggerRefresh(auth);

      expect(auth.state, isA<AuthUnavailable>());
      expect(auth.sessionUnavailableFailure?.category, FailureCategory.timeout);
    });

    test('a 401 does end the session', () async {
      final auth = await signedInService(
        handler: (options) => jsonResponse(
          {'detail': 'Token is invalid'},
          statusCode: 401,
        ),
      );

      await triggerRefresh(auth);

      expect(auth.state, isA<AuthExpired>());
      expect(auth.jwt, isNull);
    });

    test('a 403 does end the session', () async {
      final auth = await signedInService(
        handler: (options) => jsonResponse(
          {'detail': 'Not allowed'},
          statusCode: 403,
        ),
      );

      await triggerRefresh(auth);

      expect(auth.state, isA<AuthExpired>());
    });

    test('an outage during a cold-start restore is not an expiry', () async {
      SharedPreferences.setMockInitialValues({_rememberedSessionKey: true});
      final settings = await loadedSettings();
      install(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection refused',
        ),
      );
      final auth = createService(restoreSessionOnStart: true);

      auth.updateSettings(settings);
      await auth.restoreRememberedSession();

      expect(auth.state, isA<AuthUnavailable>());
      expect(
        (auth.state as AuthUnavailable).hadRememberedSession,
        isTrue,
        reason: 'the refresh cookie is still valid; retrying is worthwhile',
      );
      expect(auth.state, isNot(isA<AuthExpired>()));
    });
  });

  group('recovery after a failed restore', () {
    test('retries on a backoff and signs in once the backend returns',
        () async {
      SharedPreferences.setMockInitialValues({_rememberedSessionKey: true});
      final settings = await loadedSettings();
      var backendDown = true;
      final adapter = install((options) {
        if (backendDown) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection refused',
          );
        }
        if (isHealth(options)) {
          return jsonResponse({'status': 'ok'});
        }
        if (isRefresh(options)) {
          return jsonResponse({'access': 'access-recovered'});
        }
        return jsonResponse({}, statusCode: 404);
      });
      final auth = createService(
        restoreSessionOnStart: true,
        recoveryBackoff: const [
          Duration(milliseconds: 5),
          Duration(milliseconds: 5),
          Duration(milliseconds: 5),
          Duration(milliseconds: 5),
        ],
      );

      auth.updateSettings(settings);
      await auth.restoreRememberedSession();
      expect(auth.state, isA<AuthUnavailable>());
      expect(auth.isRecoveryScheduled, isTrue);

      backendDown = false;
      await waitFor(() => auth.state is AuthAuthenticated);

      expect(auth.jwt?.access, 'access-recovered');
      expect(
        adapter.requestsFor('/monitoring/health/'),
        isNotEmpty,
        reason: 'the readiness probe gates the retry',
      );
    });

    test('the health probe holds retries back while the backend is down',
        () async {
      SharedPreferences.setMockInitialValues({_rememberedSessionKey: true});
      final settings = await loadedSettings();
      final adapter = install((options) {
        if (isHealth(options)) {
          return jsonResponse({'detail': 'nope'}, statusCode: 503);
        }
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection refused',
        );
      });
      final auth = createService(
        restoreSessionOnStart: true,
        recoveryBackoff: const [
          Duration(milliseconds: 5),
          Duration(milliseconds: 5),
        ],
      );

      auth.updateSettings(settings);
      await auth.restoreRememberedSession();
      await waitFor(() => !auth.isRecoveryScheduled);

      expect(auth.state, isA<AuthUnavailable>());
      expect(
        adapter.requestsFor('/token/refresh/'),
        hasLength(1),
        reason: 'only the initial attempt should have spent a refresh token',
      );
    });

    test('a manual retry works after the automatic budget is spent', () async {
      SharedPreferences.setMockInitialValues({_rememberedSessionKey: true});
      final settings = await loadedSettings();
      var backendDown = true;
      install((options) {
        if (backendDown) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection refused',
          );
        }
        if (isHealth(options)) {
          return jsonResponse({'status': 'ok'});
        }
        return jsonResponse({'access': 'access-manual'});
      });
      final auth = createService(restoreSessionOnStart: true);

      auth.updateSettings(settings);
      await auth.restoreRememberedSession();
      expect(auth.state, isA<AuthUnavailable>());
      expect(
        auth.isRecoveryScheduled,
        isFalse,
        reason: 'no automatic budget in this test',
      );

      backendDown = false;
      await auth.retryRememberedSession();

      expect(auth.state, isA<AuthAuthenticated>());
      expect(auth.jwt?.access, 'access-manual');
    });
  });

  group('a late rejection cannot kill a newer session', () {
    test('a slow 401 after re-login leaves the new session alone', () async {
      final settings = await loadedSettings();
      final refreshStarted = Completer<void>();
      final refreshGate = Completer<ResponseBody>();
      var logins = 0;
      install((options) {
        if (isLogin(options)) {
          logins += 1;
          return jsonResponse({'access': 'access-$logins'});
        }
        if (isRefresh(options)) {
          if (!refreshStarted.isCompleted) {
            refreshStarted.complete();
          }
          return refreshGate.future;
        }
        // The stale in-flight request that triggers the refresh.
        return jsonResponse({'detail': 'expired'}, statusCode: 401);
      });
      final auth = createService();
      auth.updateSettings(settings);
      await auth.loginWithRememberMe('user', 'pass', rememberMe: true);
      expect(auth.jwt?.access, 'access-1');

      // A request from before the re-login, answered 401 by the server.
      final stale = apiGet(
        '/accounts/users/get_my_info/',
        settings: settings,
        headers: const {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer access-1',
        },
      ).then<void>((_) {}, onError: (Object _) {});

      // The refresh is in flight against the old session before the new login
      // replaces it — the exact interleaving that used to expire the new one.
      await refreshStarted.future;
      await auth.loginWithRememberMe('user', 'pass', rememberMe: true);
      expect(auth.jwt?.access, 'access-2');

      refreshGate.complete(
        jsonResponse({'detail': 'Token is invalid'}, statusCode: 401),
      );
      await stale;

      expect(
        auth.state,
        isA<AuthAuthenticated>(),
        reason: 'the 401 answered a question about the previous session',
      );
      expect(auth.jwt?.access, 'access-2');
    });
  });

  group('missing session versus rejected session', () {
    test('a first-ever launch is anonymous and makes no request', () async {
      final settings = await loadedSettings();
      final adapter = install(
        (options) => jsonResponse({'access': 'should-not-happen'}),
      );
      final auth = createService(restoreSessionOnStart: true);

      expect(
        auth.state,
        isA<AuthRestoring>(),
        reason: 'the router needs a splash state before the first frame',
      );

      auth.updateSettings(settings);
      await auth.restoreRememberedSession();

      expect(auth.state, isA<AuthAnonymous>());
      expect(adapter.requests, isEmpty);
    });

    test('a rejected remembered session expires and clears the flag',
        () async {
      SharedPreferences.setMockInitialValues({_rememberedSessionKey: true});
      final settings = await loadedSettings();
      install(
        (options) => jsonResponse({'detail': 'invalid'}, statusCode: 401),
      );
      final auth = createService(restoreSessionOnStart: true);

      auth.updateSettings(settings);
      await auth.restoreRememberedSession();

      expect(auth.state, isA<AuthExpired>());
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys(),
        isNot(contains(_rememberedSessionKey)),
        reason: 'the next cold start must not claim a session expired again',
      );
    });

    test('remember-me writes the flag and logout clears it', () async {
      final settings = await loadedSettings();
      install((options) => jsonResponse({'access': 'access-1'}));
      final auth = createService();
      auth.updateSettings(settings);

      await auth.loginWithRememberMe('user', 'pass', rememberMe: true);
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_rememberedSessionKey), isTrue);

      await auth.logout();
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isNot(contains(_rememberedSessionKey)));
    });

    test('a login without remember-me leaves no flag', () async {
      final settings = await loadedSettings();
      install((options) => jsonResponse({'access': 'access-1'}));
      final auth = createService();
      auth.updateSettings(settings);

      await auth.loginWithRememberMe('user', 'pass', rememberMe: false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isNot(contains(_rememberedSessionKey)));
    });
  });

  group('cross-site backend diagnostic', () {
    test('a rejection with a cross-site backend explains itself', () async {
      final auth = await signedInService(
        handler: (options) => jsonResponse(
          {'detail': 'Token is invalid'},
          statusCode: 401,
        ),
        crossSiteBackendProbe: (_) => 'https://api.other.test',
      );

      await triggerRefresh(auth);

      expect(auth.state, isA<AuthExpired>());
      expect(auth.sessionDiagnostic, contains('https://api.other.test'));
      expect(auth.sessionDiagnostic, contains('cross-site'));
    });

    test('a same-site backend produces no diagnostic', () async {
      final auth = await signedInService(
        handler: (options) => jsonResponse(
          {'detail': 'Token is invalid'},
          statusCode: 401,
        ),
      );

      await triggerRefresh(auth);

      expect(auth.sessionDiagnostic, isNull);
    });

    test('a successful sign-in clears the diagnostic', () async {
      var reject = true;
      final settings = await loadedSettings();
      install((options) {
        if (isLogin(options)) {
          return jsonResponse({'access': 'access-1'});
        }
        if (reject) {
          return jsonResponse({'detail': 'invalid'}, statusCode: 401);
        }
        return jsonResponse({'access': 'access-2'});
      });
      final auth = createService(
        crossSiteBackendProbe: (_) => 'https://api.other.test',
      );
      auth.updateSettings(settings);
      await auth.loginWithRememberMe('user', 'pass', rememberMe: true);
      await triggerRefresh(auth);
      expect(auth.sessionDiagnostic, isNotNull);

      reject = false;
      await auth.loginWithRememberMe('user', 'pass', rememberMe: true);

      expect(auth.sessionDiagnostic, isNull);
    });
  });
}
