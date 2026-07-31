import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/auth_test_harness.dart';

void main() {
  late FakeApiAdapter adapter;
  late HttpClientAdapter originalAdapter;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalAdapter = apiHttpClientAdapter;
    adapter = FakeApiAdapter();
    apiHttpClientAdapter = adapter;
  });

  tearDown(() {
    apiHttpClientAdapter = originalAdapter;
    resetApiAuth();
  });

  SessionCredential credential([String token = 'stored-token']) =>
      SessionCredential(token: token, origin: Uri.parse(builtinApiUrl).origin);

  AuthService bearerService(InMemorySessionStore store) =>
      AuthService(store: store, transport: SessionTransport.bearer);

  AuthService cookieService() => AuthService(
    store: const PlatformOwnedSessionStore(),
    transport: SessionTransport.cookie,
  );

  group('cold start (native / bearer)', () {
    test('no keystore record means Anonymous with no request at all', () async {
      final store = InMemorySessionStore();
      final auth = bearerService(store);

      await auth.restore();

      expect(auth.state, isA<AuthAnonymous>());
      expect(adapter.sawRequestFor('/get_my_info/'), isFalse);
    });

    test('a stored record is restored by one probe', () async {
      final store = InMemorySessionStore(initial: credential());
      adapter.enqueue(
        '/get_my_info/',
        const FakeReply(statusCode: 200, body: fakeUserJson),
      );
      final auth = bearerService(store);

      await auth.restore();

      expect(auth.state, isA<AuthAuthenticated>());
      expect(auth.userData?.username, 'tester');
      expect(auth.currentUserId, 7);
      expect(
        adapter.requestFor('/get_my_info/').authorization,
        'Session stored-token',
      );
    });

    test('a session 401 goes Anonymous and deletes the record', () async {
      final store = InMemorySessionStore(initial: credential());
      adapter.enqueue('/get_my_info/', const FakeReply.sessionChallenge());
      final auth = bearerService(store);

      await auth.restore();

      expect(auth.state, isA<AuthAnonymous>());
      expect(store.record, isNull);
      expect(store.deletes, 1);
    });

    test('an outage goes Unavailable and keeps the record', () async {
      final store = InMemorySessionStore(initial: credential());
      adapter.enqueue('/get_my_info/', const FakeReply.offline());
      final auth = bearerService(store);

      await auth.restore();

      expect(auth.state, isA<AuthUnavailable>());
      expect(store.record, isNotNull);
    });

    test(
      'a 401 without the challenge header is an outage, not a verdict',
      () async {
        final store = InMemorySessionStore(initial: credential());
        adapter.enqueue('/get_my_info/', const FakeReply.edgeUnauthorized());
        final auth = bearerService(store);

        await auth.restore();

        expect(auth.state, isA<AuthUnavailable>());
        expect(store.record, isNotNull);
      },
    );

    test('an unreadable keystore is reported, not fatal', () async {
      final store = InMemorySessionStore(initial: credential())
        ..failOn = 'read';
      final auth = bearerService(store);

      await auth.restore();

      expect(auth.state, isA<AuthAnonymous>());
      expect(auth.credentialWarning, contains('read'));
      expect(adapter.sawRequestFor('/get_my_info/'), isFalse);
    });
  });

  group('cold start (web / cookie)', () {
    test('always probes, because the cookie is invisible to the app', () async {
      adapter.enqueue(
        '/get_my_info/',
        const FakeReply(statusCode: 200, body: fakeUserJson),
      );
      final auth = cookieService();

      await auth.restore();

      expect(auth.state, isA<AuthAuthenticated>());
      // No credential of our own is ever attached: the browser sends the cookie.
      expect(adapter.requestFor('/get_my_info/').authorization, isNull);
    });

    test('an anonymous cold start costs exactly one 401', () async {
      adapter.enqueue('/get_my_info/', const FakeReply.sessionChallenge());
      final auth = cookieService();

      await auth.restore();

      expect(auth.state, isA<AuthAnonymous>());
      expect(adapter.requests.length, 1);
    });
  });

  group('login', () {
    test('bearer login stores the token and probes with it', () async {
      final store = InMemorySessionStore();
      adapter.enqueue(
        '/auth/login/',
        const FakeReply(
          statusCode: 200,
          body: {'transport': 'bearer', 'public_id': 'abc', 'token': 'fresh'},
        ),
      );
      adapter.enqueue(
        '/get_my_info/',
        const FakeReply(statusCode: 200, body: fakeUserJson),
      );
      final auth = bearerService(store);

      await auth.login('tester', 'hunter2', deviceLabel: 'Pixel 8');

      expect(auth.state, isA<AuthAuthenticated>());
      expect(store.record?.token, 'fresh');
      final login = adapter.requestFor('/auth/login/');
      final body = login.body! as Map<String, dynamic>;
      expect(body['transport'], 'bearer');
      expect(body['device_label'], 'Pixel 8');
      expect(
        adapter.requestFor('/get_my_info/').authorization,
        'Session fresh',
      );
    });

    test('cookie login stores nothing and sends no token back', () async {
      adapter.enqueue(
        '/auth/login/',
        const FakeReply(
          statusCode: 200,
          body: {'transport': 'cookie', 'public_id': 'abc', 'token': null},
        ),
      );
      adapter.enqueue(
        '/get_my_info/',
        const FakeReply(statusCode: 200, body: fakeUserJson),
      );
      final auth = cookieService();

      await auth.login('tester', 'hunter2');

      expect(auth.state, isA<AuthAuthenticated>());
      expect(
        (adapter.requestFor('/auth/login/').body! as Map)['transport'],
        'cookie',
      );
      expect(adapter.requestFor('/get_my_info/').authorization, isNull);
    });

    test(
      'a bearer login with no token in the body is a hard failure',
      () async {
        final store = InMemorySessionStore();
        adapter.enqueue(
          '/auth/login/',
          const FakeReply(
            statusCode: 200,
            body: {'transport': 'bearer', 'public_id': 'abc', 'token': null},
          ),
        );
        final auth = bearerService(store);

        await expectLater(auth.login('tester', 'hunter2'), throwsException);
        expect(store.record, isNull);
      },
    );

    test(
      'a keystore write failure is reported without faking durability',
      () async {
        final store = InMemorySessionStore()..failOn = 'write';
        adapter.enqueue(
          '/auth/login/',
          const FakeReply(
            statusCode: 200,
            body: {'transport': 'bearer', 'public_id': 'abc', 'token': 'fresh'},
          ),
        );
        adapter.enqueue(
          '/get_my_info/',
          const FakeReply(statusCode: 200, body: fakeUserJson),
        );
        final auth = bearerService(store);

        await auth.login('tester', 'hunter2');

        expect(auth.state, isA<AuthAuthenticated>());
        expect(auth.credentialWarning, contains('could not remember'));
      },
    );
  });

  group('logout', () {
    Future<AuthService> signedInBearer(InMemorySessionStore store) async {
      adapter.enqueue(
        '/get_my_info/',
        const FakeReply(statusCode: 200, body: fakeUserJson),
      );
      final auth = bearerService(store);
      await auth.restore();
      return auth;
    }

    test('native logout deletes the local credential', () async {
      final store = InMemorySessionStore(initial: credential());
      final auth = await signedInBearer(store);
      adapter.enqueue(
        '/auth/logout/',
        const FakeReply(statusCode: 200, body: {'status': 'ok'}),
      );

      await auth.logout();

      expect(auth.state, isA<AuthAnonymous>());
      expect(store.record, isNull);
    });

    test(
      'native logout still signs out locally when the server is down',
      () async {
        final store = InMemorySessionStore(initial: credential());
        final auth = await signedInBearer(store);
        adapter.enqueue('/auth/logout/', const FakeReply.offline());

        await auth.logout();

        // The credential is genuinely gone from this device; the orphaned row
        // stays visible in the sessions list and dies at idle expiry.
        expect(auth.state, isA<AuthAnonymous>());
        expect(store.record, isNull);
      },
    );

    test('a keystore delete failure is reported rather than claimed', () async {
      final store = InMemorySessionStore(initial: credential());
      final auth = await signedInBearer(store);
      store.failOn = 'delete';
      adapter.enqueue(
        '/auth/logout/',
        const FakeReply(statusCode: 200, body: {'status': 'ok'}),
      );

      await auth.logout();

      expect(auth.credentialWarning, contains('could not be removed'));
    });

    test('web logout offline reports failure and does not sign out', () async {
      adapter
        ..enqueue(
          '/get_my_info/',
          const FakeReply(statusCode: 200, body: fakeUserJson),
        )
        ..enqueue('/auth/logout/', const FakeReply.offline());
      final auth = cookieService();
      await auth.restore();

      await auth.logout();

      // Only the server can clear an HttpOnly cookie, so a local "signed out"
      // would be a lie the browser refuses to honour.
      expect(auth.state, isA<AuthUnavailable>());
      expect(auth.isAuthenticated, isFalse);
      expect((auth.state as AuthUnavailable).reason, contains('still active'));
    });

    test('web logout signs out when the server acknowledges', () async {
      adapter
        ..enqueue(
          '/get_my_info/',
          const FakeReply(statusCode: 200, body: fakeUserJson),
        )
        ..enqueue(
          '/auth/logout/',
          const FakeReply(statusCode: 200, body: {'status': 'ok'}),
        );
      final auth = cookieService();
      await auth.restore();

      await auth.logout();

      expect(auth.state, isA<AuthAnonymous>());
    });
  });

  group('designated 401 handling', () {
    Future<AuthService> authenticated(InMemorySessionStore store) async {
      adapter.enqueue(
        '/get_my_info/',
        const FakeReply(statusCode: 200, body: fakeUserJson),
      );
      final auth = bearerService(store);
      await auth.restore();
      return auth;
    }

    DioException challenge() => DioException(
      requestOptions: RequestOptions(path: '/monitoring/links/'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/monitoring/links/'),
        statusCode: 401,
        headers: Headers.fromMap({
          'www-authenticate': ['Session'],
        }),
      ),
    );

    test('ends the session and deletes the record', () async {
      final store = InMemorySessionStore(initial: credential());
      final auth = await authenticated(store);

      await auth.reportPossibleSessionEnd(
        challenge(),
        generation: auth.generation,
      );

      expect(auth.state, isA<AuthExpired>());
      expect(store.record, isNull);
    });

    test('a stale generation is ignored', () async {
      final store = InMemorySessionStore(initial: credential());
      final auth = await authenticated(store);
      final stale = auth.generation - 1;

      await auth.reportPossibleSessionEnd(challenge(), generation: stale);

      expect(auth.state, isA<AuthAuthenticated>());
      expect(store.record, isNotNull);
    });

    test('an edge 401 without the header changes nothing', () async {
      final store = InMemorySessionStore(initial: credential());
      final auth = await authenticated(store);
      final edge = DioException(
        requestOptions: RequestOptions(path: '/monitoring/links/'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/monitoring/links/'),
          statusCode: 401,
        ),
      );

      await auth.reportPossibleSessionEnd(edge, generation: auth.generation);

      expect(auth.state, isA<AuthAuthenticated>());
      expect(store.record, isNotNull);
    });

    test('a 403 never touches session state', () async {
      final store = InMemorySessionStore(initial: credential());
      final auth = await authenticated(store);
      final forbidden = DioException(
        requestOptions: RequestOptions(path: '/monitoring/links/'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/monitoring/links/'),
          statusCode: 403,
        ),
      );

      await auth.reportPossibleSessionEnd(
        forbidden,
        generation: auth.generation,
      );

      expect(auth.state, isA<AuthAuthenticated>());
    });
  });

  group('generation fencing across a logout', () {
    test(
      'a login bumps the generation so earlier responses cannot land',
      () async {
        final store = InMemorySessionStore();
        adapter
          ..enqueue(
            '/auth/login/',
            const FakeReply(
              statusCode: 200,
              body: {
                'transport': 'bearer',
                'public_id': 'abc',
                'token': 'fresh',
              },
            ),
          )
          ..enqueue(
            '/get_my_info/',
            const FakeReply(statusCode: 200, body: fakeUserJson),
          );
        final auth = bearerService(store);
        final before = auth.generation;

        await auth.login('tester', 'hunter2');

        expect(auth.generation, greaterThan(before));
      },
    );
  });
}
