import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_bridge/hc_bridge.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/health/health_service.dart';
import 'package:notif/services/health/sync_store.dart';
import 'package:notif/services/persistence.dart';
import 'package:notif/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/auth_test_harness.dart';
import 'support/fake_hc_bridge.dart';
import 'support/fake_health_scheduler.dart';

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

  AuthService auth() => AuthService(
    store: InMemorySessionStore(),
    transport: SessionTransport.bearer,
    maxRecoveryProbes: 0,
  );

  test('signing in again clears the signed-out state', () async {
    SharedPreferences.setMockInitialValues({
      'health.v1.session_expired_at_ms': 1234,
    });
    final authService = auth();
    final health = HealthService(
      authService,
      bridge: FakeHcBridge(),
      scheduler: FakeHealthScheduler(),
      supported: true,
    );
    addTearDown(health.dispose);
    await authService.restore(); // No credential: Anonymous.
    await health.reloadSnapshot();
    expect(health.snapshot.sessionExpired, isTrue);

    adapter
      ..enqueue(
        '/auth/login/',
        const FakeReply(statusCode: 200, body: {'token': 'fresh'}),
      )
      ..enqueue(
        '/get_my_info/',
        const FakeReply(statusCode: 200, body: fakeUserJson),
      );
    await authService.login('tester', 'pw');
    await pumpEventQueue();

    expect(health.snapshot.sessionExpired, isFalse);
    final store = HealthSyncStore(await PreferenceStore.load());
    expect(store.sessionExpiredAtMs, isNull);
  });

  test(
    'a cold-start restore with a live session leaves the marker alone',
    () async {
      // Restoring -> Authenticated is the same credential coming back, not a
      // sign-in; only a sign-in can have replaced a dead session.
      SharedPreferences.setMockInitialValues({
        'health.v1.session_expired_at_ms': 1234,
      });
      final authService = AuthService(
        store: InMemorySessionStore(
          initial: SessionCredential(
            token: 't',
            origin: Uri.parse(builtinApiUrl).origin,
          ),
        ),
        transport: SessionTransport.bearer,
        maxRecoveryProbes: 0,
      );
      final health = HealthService(
        authService,
        bridge: FakeHcBridge(),
        scheduler: FakeHealthScheduler(),
        supported: true,
      );
      addTearDown(health.dispose);
      adapter.enqueue(
        '/get_my_info/',
        const FakeReply(statusCode: 200, body: fakeUserJson),
      );

      await authService.restore();
      await pumpEventQueue();
      await health.reloadSnapshot();

      expect(health.snapshot.sessionExpired, isTrue);
    },
  );

  test(
    'granting asks for every permission, records the grant, and probes',
    () async {
      final bridge =
          FakeHcBridge(currentStatus: grantedWithout(everyPermission))
            ..coverage = const HcCoverage(
              computedAtMs: 1,
              types: [
                HcTypeCoverage(
                  type: HcDataType.weight,
                  byAggregate: true,
                  count: 3,
                ),
              ],
            );
      final scheduler = FakeHealthScheduler();
      final health = HealthService(
        auth(),
        bridge: bridge,
        scheduler: scheduler,
        supported: true,
        clock: () => 1790000000000,
      );
      addTearDown(health.dispose);

      await health.grantAccess();

      expect(bridge.permissionRequests, [everyPermission]);
      expect(health.missingPermissions, isEmpty);
      expect(health.status!.readableTypes, HcRecordType.values);
      expect(health.snapshot.firstGrantAtMs, 1790000000000);
      expect(health.snapshot.coverage!.types.single.type, HcDataType.weight);
      // Signed out: nothing is scheduled until there is a session to upload on.
      expect(scheduler.calls, isEmpty);
    },
  );

  test(
    'Sync now queues the shared job and shows as pending until a run answers',
    () async {
      var now = 1000;
      final scheduler = FakeHealthScheduler();
      final health = HealthService(
        auth(),
        bridge: FakeHcBridge(),
        scheduler: scheduler,
        supported: true,
        clock: () => now,
      );
      addTearDown(health.dispose);

      await health.syncNow();
      expect(scheduler.calls, ['now']);
      expect(health.snapshot.syncPending, isTrue);

      final store = HealthSyncStore(await PreferenceStore.load());
      await store.saveReport(
        const HealthRunReport(
          kind: HealthRunKind.sync,
          outcome: HealthRunOutcome.succeeded,
          startedAtMs: 1001,
          finishedAtMs: 1002,
        ),
      );
      now = 2000;
      await health.reloadSnapshot();
      expect(health.snapshot.syncPending, isFalse);
    },
  );

  test('a bridge failure on grant is shown, not thrown', () async {
    final health = HealthService(
      auth(),
      bridge: _RefusingBridge(),
      scheduler: FakeHealthScheduler(),
      supported: true,
    );
    addTearDown(health.dispose);

    await health.grantAccess();

    expect(health.actionFailure!.message, contains('foreground'));
    expect(health.granting, isFalse);
  });

  test(
    'off Android the service reports unsupported and touches nothing',
    () async {
      final bridge = FakeHcBridge();
      final health = HealthService(
        auth(),
        bridge: bridge,
        scheduler: FakeHealthScheduler(),
        supported: false,
      );
      addTearDown(health.dispose);

      await health.refresh();

      expect(health.availability, isA<HealthUnsupported>());
      expect(bridge.log, isEmpty);
    },
  );
}

class _RefusingBridge extends FakeHcBridge {
  _RefusingBridge() : super(currentStatus: grantedWithout(everyPermission));

  @override
  Future<Set<String>> requestPermissions(Set<String> permissions) async =>
      throw const HcBridgeException(
        HcErrorCode.noActivity,
        'no activity',
        operation: 'requestPermissions',
      );
}
