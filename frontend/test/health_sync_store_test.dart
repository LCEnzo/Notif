import 'package:flutter_test/flutter_test.dart';
import 'package:hc_bridge/hc_bridge.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/health/sync_store.dart';
import 'package:notif/services/persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<HealthSyncStore> _fresh() async =>
    HealthSyncStore(await PreferenceStore.load());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the changes token round-trips, keyed by its type set', () async {
    final store = await _fresh();
    expect(store.changesTokenFor('sleep_session,steps'), isNull);

    await store.saveChangesToken('sleep_session,steps', 'tok-1');
    final reopened = await _fresh();
    expect(reopened.changesTokenFor('sleep_session,steps'), 'tok-1');
    // A grant change makes a different type set; the old token covers the
    // wrong types and must not be used for it.
    expect(
      reopened.changesTokenFor('resting_heart_rate,sleep_session,steps'),
      isNull,
    );
  });

  test('cursor, start, first grant and failures round-trip', () async {
    final store = await _fresh();
    await store.saveBackfillCursor(1700000000000);
    await store.saveBackfillStart(1790000000000);
    await store.saveFirstGrantAt(1780000000000);
    await store.saveBackfillRequested(requested: true);
    await store.saveGrant({'b', 'a'}, 42);

    final reopened = await _fresh();
    expect(reopened.backfillCursorMs, 1700000000000);
    expect(reopened.backfillStartMs, 1790000000000);
    expect(reopened.firstGrantAtMs, 1780000000000);
    expect(reopened.backfillRequested, isTrue);
    expect(reopened.grantedPermissions, {'a', 'b'});
    expect(reopened.grantObservedAtMs, 42);

    await reopened.clearFirstGrantAt();
    expect((await _fresh()).firstGrantAtMs, isNull);
  });

  test('an empty grant set is not "never observed"', () async {
    final store = await _fresh();
    expect(store.grantedPermissions, isNull);
    await store.saveGrant({}, 1);
    expect((await _fresh()).grantedPermissions, isEmpty);
  });

  test('run reports round-trip by kind', () async {
    final store = await _fresh();
    const sync = HealthRunReport(
      kind: HealthRunKind.sync,
      outcome: HealthRunOutcome.failed,
      startedAtMs: 10,
      finishedAtMs: 20,
      trigger: HealthSyncTrigger.manual,
      message: 'server said no',
      failure: FailureCategory.serverError,
      retryable: true,
      uploadedItems: 3,
      batches: 1,
      rejected: 2,
      notes: ['a', 'b'],
    );
    const backfill = HealthRunReport(
      kind: HealthRunKind.backfill,
      outcome: HealthRunOutcome.succeeded,
      startedAtMs: 30,
      finishedAtMs: 40,
      backfillComplete: true,
    );
    await store.saveReport(sync);
    await store.saveReport(backfill);

    final reopened = await _fresh();
    expect(reopened.lastSync!.toJson(), sync.toJson());
    expect(reopened.lastBackfill!.toJson(), backfill.toJson());
  });

  test('the coverage report round-trips', () async {
    final store = await _fresh();
    const report = HealthCoverageReport(
      computedAtMs: 5,
      historyGranted: true,
      types: [
        HcTypeCoverage(
          type: HcDataType.sleepSession,
          byAggregate: true,
          count: 30,
          firstMonth: '2023-02',
          lastMonth: '2026-10',
        ),
        HcTypeCoverage(
          type: HcDataType.steps,
          byAggregate: true,
          count: 2,
          firstMonth: '2024-11',
          lastMonth: '2024-12',
        ),
        // Earlier, but not uploaded: no part of the backfill floor.
        HcTypeCoverage(
          type: HcDataType.weight,
          byAggregate: true,
          count: 1,
          firstMonth: '2019-01',
          lastMonth: '2019-01',
        ),
        HcTypeCoverage(
          type: HcDataType.bodyFat,
          byAggregate: false,
          count: 10000,
          capped: true,
        ),
      ],
      recordsPerDay: {'steps': 96.5, 'sleep_session': 1},
      stagesPerDay: 38.25,
      forecastBytesPerYear: 12345678,
    );
    await store.saveCoverage(report);

    final reopened = (await _fresh()).coverage!;
    expect(reopened.toJson(), report.toJson());
    expect(
      reopened.earliestUploadedMonthStartMs,
      DateTime(2023, 2).millisecondsSinceEpoch,
    );
  });

  test('a corrupt report is classified, not swallowed', () async {
    SharedPreferences.setMockInitialValues({
      'health.v1.last_sync': '{"kind": "sync"}',
      'health.v1.coverage': 'not json',
    });
    final store = await _fresh();
    expect(() => store.lastSync, throwsA(isA<CorruptLocalStateException>()));
    expect(() => store.coverage, throwsA(isA<CorruptLocalStateException>()));
    expect(
      AppFailure.from(_thrown(() => store.lastSync)).category,
      FailureCategory.corruptLocalState,
    );
  });
}

Object _thrown(void Function() body) {
  try {
    body();
  } on Exception catch (error) {
    return error;
  }
  fail('expected a throw');
}
