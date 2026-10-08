import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/screens/health.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/health/health_service.dart';
import 'package:notif/services/health/sync_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/auth_test_harness.dart';
import 'support/fake_hc_bridge.dart';
import 'support/fake_health_scheduler.dart';

const int _now = 1790000000000;

String _report(HealthRunReport report) => jsonEncode(report.toJson());

/// Pumps the Health screen over [bridge] and [prefs], and lets the first
/// refresh settle.
Future<(HealthService, FakeHealthScheduler)> _pump(
  WidgetTester tester, {
  FakeHcBridge? bridge,
  Map<String, Object> prefs = const {},
  bool supported = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final scheduler = FakeHealthScheduler();
  final health = HealthService(
    AuthService(
      store: InMemorySessionStore(),
      transport: SessionTransport.bearer,
      maxRecoveryProbes: 0,
    ),
    bridge: bridge ?? FakeHcBridge(),
    scheduler: scheduler,
    supported: supported,
    clock: () => _now,
  );
  addTearDown(health.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<HealthService>.value(
      value: health,
      child: MaterialApp(
        theme: buildNotifTheme(
          colorway: NotifColorway.dusk1,
          fontSet: NotifFontSet.current,
        ),
        home: const HealthPage(pollInterval: Duration(hours: 1)),
      ),
    ),
  );
  // The first refresh runs after the first frame; the fakes answer at once.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
  return (health, scheduler);
}

void main() {
  testWidgets('off Android it says so and offers nothing', (tester) async {
    await _pump(tester, supported: false);

    expect(find.text('Health Connect exists only on Android.'), findsOneWidget);
    expect(find.byKey(const Key('health-grant')), findsNothing);
    expect(find.byKey(const Key('health-sync-now')), findsNothing);
  });

  testWidgets('an outdated Health Connect asks for an update', (tester) async {
    await _pump(
      tester,
      bridge: FakeHcBridge(
        currentStatus: const HcStatus(
          sdk: HcSdkStatus.updateRequired,
          features: {},
          grantedPermissions: {},
        ),
      ),
    );

    expect(
      find.text('Health Connect needs an update from the Play Store.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('health-grant')), findsNothing);
  });

  testWidgets('nothing granted: one button asks for everything', (
    tester,
  ) async {
    final bridge = FakeHcBridge(
      currentStatus: grantedWithout(everyPermission),
    );
    await _pump(tester, bridge: bridge);

    expect(find.text('0 of 41 readable'), findsOneWidget);
    expect(find.text('not granted'), findsNWidgets(2));
    expect(find.byKey(const Key('health-sync-now')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('health-grant')));

    await tester.tap(find.byKey(const Key('health-grant')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(bridge.permissionRequests, [everyPermission]);
    expect(find.text('41 of 41 readable'), findsOneWidget);
    expect(find.text('granted'), findsNWidgets(2));
    expect(find.byKey(const Key('health-grant')), findsNothing);
    expect(find.byKey(const Key('health-sync-now')), findsOneWidget);
  });

  testWidgets(
    'without the history grant it names the floor and re-asks for it alone',
    (
      tester,
    ) async {
      final bridge = FakeHcBridge(
        currentStatus: grantedWithout({HcPermissions.readHistory}),
      );
      await _pump(
        tester,
        bridge: bridge,
        prefs: {'health.v1.first_grant_at_ms': _now},
      );

      final floor = DateTime.fromMillisecondsSinceEpoch(_now - 30 * testDayMs);
      final date =
          '${floor.year}-${floor.month.toString().padLeft(2, '0')}-'
          '${floor.day.toString().padLeft(2, '0')}';
      expect(find.text('Past data off: nothing before $date.'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('health-grant')));

      await tester.tap(find.byKey(const Key('health-grant')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(bridge.permissionRequests, [
        {HcPermissions.readHistory},
      ]);
    },
  );

  testWidgets(
    'a dead session shows the signed-out state and the last success',
    (
      tester,
    ) async {
      await _pump(
        tester,
        prefs: {
          'health.v1.session_expired_at_ms': _now,
          'health.v1.last_sync_success_ms': _now - 15 * testDayMs,
          'health.v1.last_sync': _report(
            const HealthRunReport(
              kind: HealthRunKind.sync,
              outcome: HealthRunOutcome.sessionExpired,
              startedAtMs: _now,
              finishedAtMs: _now,
              message:
                  'Signed out; health sync is paused until the next sign-in.',
              failure: FailureCategory.unauthorized,
            ),
          ),
        },
      );

      expect(find.byKey(const Key('health-session-expired')), findsOneWidget);
      // A silently dead sync shows when it last worked.
      expect(
        find.descendant(
          of: find.byKey(const Key('health-last-success')),
          matching: find.text(formatDateTime(_now - 15 * testDayMs)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('health-session-expired')),
          matching: find.text(
            'Signed out; health sync is paused until the next sign-in.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Signed out ·'), findsOneWidget);
    },
  );

  testWidgets('the last sync shows its outcome, counts and message', (
    tester,
  ) async {
    await _pump(
      tester,
      prefs: {
        'health.v1.last_sync': _report(
          const HealthRunReport(
            kind: HealthRunKind.sync,
            outcome: HealthRunOutcome.failed,
            startedAtMs: _now,
            finishedAtMs: _now,
            message: 'The network is unavailable.',
            failure: FailureCategory.networkUnavailable,
            retryable: true,
          ),
        ),
      },
    );

    expect(find.textContaining('Failed ·'), findsOneWidget);
    expect(find.text('The network is unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('health-session-expired')), findsNothing);
  });

  testWidgets('Sync now queues the job and then shows it as queued', (
    tester,
  ) async {
    final (_, scheduler) = await _pump(tester);
    expect(find.text('No sync has run yet.'), findsOneWidget);
    expect(find.text('never'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('health-sync-now')));

    await tester.tap(find.byKey(const Key('health-sync-now')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(scheduler.calls, contains('now'));
    final button = tester.widget<NotifButton>(
      find.byKey(const Key('health-sync-now')),
    );
    expect(button.label, 'Sync queued');
    expect(button.onPressed, isNull);
  });

  testWidgets('coverage lists each type with data and names the empty ones', (
    tester,
  ) async {
    await _pump(
      tester,
      prefs: {
        'health.v1.coverage': jsonEncode(
          const HealthCoverageReport(
            computedAtMs: _now,
            historyGranted: true,
            types: [
              HcTypeCoverage(
                type: HcDataType.steps,
                byAggregate: true,
                count: 42,
                firstMonth: '2023-04',
                lastMonth: '2026-10',
              ),
              HcTypeCoverage(
                type: HcDataType.oxygenSaturation,
                byAggregate: false,
                count: 10000,
                capped: true,
              ),
              HcTypeCoverage(
                type: HcDataType.vo2Max,
                byAggregate: false,
                count: 0,
              ),
              HcTypeCoverage(
                type: HcDataType.weight,
                byAggregate: true,
                count: 0,
              ),
            ],
            recordsPerDay: {'steps': 96},
            stagesPerDay: 40,
            forecastBytesPerYear: 27500000,
          ).toJson(),
        ),
      },
    );

    expect(find.text('27.5 MB a year'), findsOneWidget);
    expect(find.text('steps: 42 months, 2023-04 to 2026-10'), findsOneWidget);
    expect(
      find.text('oxygen saturation: at least 10000 records'),
      findsOneWidget,
    );
    expect(find.text('No data: vo2 max, weight.'), findsOneWidget);
  });

  testWidgets('backfill: a start button, then progress once requested', (
    tester,
  ) async {
    final (health, scheduler) = await _pump(tester);
    expect(find.byKey(const Key('health-start-backfill')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('health-start-backfill')));
    await tester.tap(find.byKey(const Key('health-start-backfill')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(scheduler.calls, contains('backfill'));
    expect(find.byKey(const Key('health-start-backfill')), findsNothing);
    expect(find.text('waiting to start'), findsOneWidget);
    expect(health.snapshot.backfillRequested, isTrue);
  });

  testWidgets('backfill progress is the share walked from start to floor', (
    tester,
  ) async {
    // Without history the floor is first grant - 30 days; a cursor halfway
    // between the start and the floor is 50%.
    const start = _now;
    const floor = _now - 30 * testDayMs;
    await _pump(
      tester,
      bridge: FakeHcBridge(
        currentStatus: grantedWithout({HcPermissions.readHistory}),
      ),
      prefs: {
        'health.v1.first_grant_at_ms': _now,
        'health.v1.backfill_requested': true,
        'health.v1.backfill_start_ms': start,
        'health.v1.backfill_cursor_ms': (start + floor) ~/ 2,
      },
    );

    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('battery optimization: a button while restricted, none after', (
    tester,
  ) async {
    final bridge = FakeHcBridge();
    final (health, _) = await _pump(tester, bridge: bridge);

    expect(
      find.text('optimized: background sync may be delayed or killed'),
      findsOneWidget,
    );
    expect(find.textContaining('Autostart'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('health-allow-background')),
    );
    await tester.tap(find.byKey(const Key('health-allow-background')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(bridge.batteryExemptionRequests, 1);

    // Back from the system dialog, exempted: the resume refresh shows it.
    bridge.batteryExempt = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(health.batteryExempt, isTrue);
    expect(find.text('unrestricted'), findsOneWidget);
    expect(find.byKey(const Key('health-allow-background')), findsNothing);
  });
}
