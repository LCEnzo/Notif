import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_bridge/hc_bridge.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/health/sync_engine.dart';
import 'package:notif/services/health/sync_store.dart';
import 'package:notif/services/persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_hc_bridge.dart';
import 'support/fake_uploader.dart';

/// Deliberately not on an hour, so window alignment is exercised.
const int _now = 1790000000000 + 1234567;
const int _hour = testHourMs;
const int _day = testDayMs;
const String _allTypes = 'resting_heart_rate,sleep_session,steps';

int _floorHour(int ms) => ms - ms % _hour;

class _Harness {
  _Harness(this.bridge, this.uploader, this.store);

  final FakeHcBridge bridge;
  final FakeUploader uploader;
  final HealthSyncStore store;
  int clock = _now;
  HealthSyncConfig config = const HealthSyncConfig();

  HealthSyncEngine get engine => HealthSyncEngine(
    bridge: bridge,
    uploader: uploader,
    store: store,
    clock: () => clock,
    config: config,
  );

  /// Every body's parsed JSON, in upload order.
  List<Map<String, dynamic>> get sent => [
    for (final body in uploader.bodies)
      jsonDecode(body) as Map<String, dynamic>,
  ];

  /// The ids of every entry in [list] across all bodies.
  List<String> sentIds(String list) => [
    for (final body in sent)
      for (final entry in (body[list] as List<dynamic>? ?? const []))
        (entry as Map<String, dynamic>)['hc_id'] as String,
  ];
}

Future<_Harness> _harness({HcStatus? status}) async {
  SharedPreferences.setMockInitialValues({});
  return _Harness(
    FakeHcBridge(currentStatus: status ?? grantedEverything),
    FakeUploader(),
    HealthSyncStore(await PreferenceStore.load()),
  );
}

HcChangesPage _page(
  List<HcChange> changes, {
  String next = 'next',
  bool hasMore = false,
  int observedAtMs = 5000,
}) => HcChangesPage(
  changes: changes,
  nextToken: next,
  hasMore: hasMore,
  tokenExpired: false,
  observedAtMs: observedAtMs,
  skippedUnsupported: 0,
);

DioException _sessionChallenge() {
  final request = RequestOptions(path: '/health/ingest/');
  return DioException.badResponse(
    statusCode: 401,
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: 401,
      headers: Headers.fromMap({
        'www-authenticate': ['Session'],
      }),
    ),
  );
}

void main() {
  group('sync', () {
    test('a first sync takes a token before reading, then saves it', () async {
      final h = await _harness();
      h.bridge.records[HcRecordType.steps] = [
        stepsRecord(1, startMs: _now - 2 * _day),
        // Inside the 2-day read margin: read again, which is harmless.
        stepsRecord(2, startMs: _now - 8 * _day),
        stepsRecord(3, startMs: _now - 20 * _day),
      ];

      final report = await h.engine.runSync(HealthSyncTrigger.periodic);

      expect(report.outcome, HealthRunOutcome.succeeded);
      expect(
        h.bridge.log.indexOf('token'),
        lessThan(h.bridge.log.indexWhere((e) => e.startsWith('read'))),
      );
      expect(h.bridge.changesCalls, isEmpty);
      expect(h.store.changesTokenFor(_allTypes), 'token-1');
      expect(
        h.bridge.reads.map((read) => (read.type, read.startMs, read.endMs)),
        [
          for (final type in HcRecordType.values) (type, _now - 9 * _day, _now),
        ],
      );
      expect(
        h.bridge.aggregates.map((a) => (a.metric, a.startMs, a.endMs)),
        [
          for (final metric in HcAggregateMetric.values)
            (metric, _floorHour(_now - 7 * _day), _floorHour(_now) + _hour),
        ],
      );
      expect(h.sentIds('steps'), [uuid(1), uuid(2)]);
      expect(h.sent.single['coverage_start_ms'], isNull);
      expect(
        (h.sent.single['aggregate_windows'] as List<dynamic>).length,
        2,
      );
    });

    test(
      'a later sync pulls changes from the saved token and saves the next',
      () async {
        final h = await _harness();
        await h.store.saveChangesToken(_allTypes, 'saved');
        // An edit to a 2023 record: outside every re-read window, so only the
        // changes stream can deliver it.
        final old = stepsRecord(
          7,
          startMs: 1680000000000,
          lastModifiedMs: 4000,
        );
        h.bridge.changesQueue.addAll([
          _page([HcUpsertion(old)], next: 'page-2', hasMore: true),
          _page([HcDeletion(uuid(8))], next: 'final', observedAtMs: 6000),
        ]);

        final report = await h.engine.runSync(HealthSyncTrigger.periodic);

        expect(report.outcome, HealthRunOutcome.succeeded);
        expect(h.bridge.changesCalls, ['saved', 'page-2']);
        expect(h.sentIds('steps'), [uuid(7)]);
        expect(h.sent.single['deletions'], [
          {'hc_id': uuid(8), 'observed_at_ms': 6000},
        ]);
        expect(h.store.changesTokenFor(_allTypes), 'final');
        expect(h.bridge.tokensIssued, 0);
      },
    );

    test(
      'the last change per id wins across pages (contract rule 3)',
      () async {
        final h = await _harness();
        await h.store.saveChangesToken(_allTypes, 'saved');
        final x = stepsRecord(1, startMs: 1680000000000, count: 5);
        final y = stepsRecord(2, startMs: 1680000000000);
        h.bridge.changesQueue.addAll([
          _page([HcDeletion(x.metadata.id), HcUpsertion(y)], hasMore: true),
          _page([HcUpsertion(x), HcDeletion(y.metadata.id)]),
        ]);

        await h.engine.runSync(HealthSyncTrigger.periodic);

        // X was deleted, then rewritten: only the rewrite goes.
        expect(h.sentIds('steps'), [uuid(1)]);
        // Y was written, then deleted: only the deletion goes.
        expect(h.sentIds('deletions'), [uuid(2)]);
      },
    );

    test('an expired token re-reads 30 days and starts a new token', () async {
      final h = await _harness();
      await h.store.saveChangesToken(_allTypes, 'stale');
      h.bridge.changesQueue.add(
        const HcChangesPage(
          changes: [],
          nextToken: '',
          hasMore: false,
          tokenExpired: true,
          observedAtMs: 0,
          skippedUnsupported: 0,
        ),
      );
      h.bridge.records[HcRecordType.steps] = [
        stepsRecord(1, startMs: _now - 25 * _day),
      ];

      final report = await h.engine.runSync(HealthSyncTrigger.periodic);

      expect(report.outcome, HealthRunOutcome.succeeded);
      expect(report.notes, contains(contains('expired')));
      expect(h.store.changesTokenFor(_allTypes), 'token-1');
      expect(
        h.bridge.reads.map((read) => read.startMs).toSet(),
        {_now - 32 * _day},
      );
      expect(
        h.bridge.aggregates.map((a) => (a.startMs, a.endMs)).toSet(),
        {(_floorHour(_now - 30 * _day), _floorHour(_now) + _hour)},
      );
      expect(h.sentIds('steps'), [uuid(1)]);
    });

    test('the token is saved only after every batch has landed', () async {
      final h = await _harness();
      await h.store.saveChangesToken(_allTypes, 'saved');
      h.bridge.records[HcRecordType.steps] = [
        for (var n = 0; n < 6000; n++) stepsRecord(n, startMs: _now - _day - n),
      ];
      h.uploader.failures[1] = DioException.connectionError(
        requestOptions: RequestOptions(path: '/health/ingest/'),
        reason: 'offline',
      );

      final failed = await h.engine.runSync(HealthSyncTrigger.periodic);

      expect(h.uploader.bodies, hasLength(1), reason: 'first batch landed');
      expect(failed.outcome, HealthRunOutcome.failed);
      expect(failed.failure, FailureCategory.networkUnavailable);
      expect(failed.retryable, isTrue);
      expect(h.store.changesTokenFor(_allTypes), 'saved');

      final retried = await h.engine.runSync(HealthSyncTrigger.periodic);
      expect(retried.outcome, HealthRunOutcome.succeeded);
      expect(h.bridge.changesCalls, ['saved', 'saved']);
      expect(h.store.changesTokenFor(_allTypes), 'saved+');
    });

    test(
      'a binder failure in getChanges keeps the token and re-reads',
      () async {
        final h = await _harness();
        await h.store.saveChangesToken(_allTypes, 'saved');
        for (final code in [HcErrorCode.remote, HcErrorCode.io]) {
          h.bridge.changesQueue.add(
            HcBridgeException(code, 'binder died', operation: 'changes'),
          );
          h.bridge.reads.clear();

          final report = await h.engine.runSync(HealthSyncTrigger.periodic);

          expect(report.outcome, HealthRunOutcome.partial, reason: code.wire);
          expect(report.notes.join(), contains('kept the token'));
          expect(h.store.changesTokenFor(_allTypes), 'saved');
          // The trailing re-read still ran, at its usual length.
          expect(h.bridge.reads.first.startMs, _now - 9 * _day);
        }
        expect(h.bridge.tokensIssued, 0);
      },
    );

    test(
      'a rate limit fails the run and keeps the token',
      () async {
        final h = await _harness();
        await h.store.saveChangesToken(_allTypes, 'saved');
        h.bridge.changesQueue.add(
          const HcBridgeException(
            HcErrorCode.rateLimited,
            'quota',
            operation: 'changes',
          ),
        );

        final report = await h.engine.runSync(HealthSyncTrigger.periodic);

        expect(report.outcome, HealthRunOutcome.failed);
        expect(report.retryable, isTrue);
        expect(report.failure, FailureCategory.sourceBlockedDegraded);
        expect(h.store.changesTokenFor(_allTypes), 'saved');
        expect(h.uploader.calls, 0);
      },
    );

    test(
      'coverage_start_ms: first grant minus 30 days, anchored, null with history',
      () async {
        final h = await _harness(
          status: grantedWithout({HcPermissions.readHistory}),
        );
        const firstSeen = _now;

        await h.engine.runSync(HealthSyncTrigger.periodic);
        expect(h.sent.last['coverage_start_ms'], firstSeen - 30 * _day);

        // Later runs keep the first observation, as HC keeps its anchor.
        h.clock = _now + 5 * _day;
        await h.engine.runSync(HealthSyncTrigger.periodic);
        expect(h.sent.last['coverage_start_ms'], firstSeen - 30 * _day);

        h.bridge.currentStatus = grantedEverything;
        await h.engine.runSync(HealthSyncTrigger.periodic);
        expect(h.sent.last['coverage_start_ms'], isNull);
      },
    );

    test(
      'revoking every read clears first_grant_at; a new grant re-anchors it',
      () async {
        final h = await _harness(
          status: grantedWithout({HcPermissions.readHistory}),
        );
        await h.engine.runSync(HealthSyncTrigger.periodic);
        expect(h.store.firstGrantAtMs, _now);

        // Weight alone still counts as a grant: HC keeps the anchor.
        h.bridge.currentStatus = HcStatus(
          sdk: HcSdkStatus.available,
          features: HcFeature.values.toSet(),
          grantedPermissions: {HcDataType.weight.readPermission},
        );
        h.clock = _now + _day;
        final weightOnly = await h.engine.runSync(HealthSyncTrigger.periodic);
        expect(weightOnly.outcome, HealthRunOutcome.notReady);
        expect(h.store.firstGrantAtMs, _now);

        h.bridge.currentStatus = grantedWithout(everyPermission);
        final revoked = await h.engine.runSync(HealthSyncTrigger.periodic);
        expect(revoked.outcome, HealthRunOutcome.notReady);
        expect(h.store.firstGrantAtMs, isNull);

        h.bridge.currentStatus = grantedWithout({HcPermissions.readHistory});
        h.clock = _now + 2 * _day;
        await h.engine.runSync(HealthSyncTrigger.periodic);
        expect(h.sent.last['coverage_start_ms'], _now + 2 * _day - 30 * _day);
      },
    );

    test('Sync now and the periodic job do exactly the same work', () async {
      Future<(List<String>, List<String>, HealthRunReport)> run(
        HealthSyncTrigger trigger,
      ) async {
        final h = await _harness();
        await h.store.saveChangesToken(_allTypes, 'saved');
        h.bridge.records[HcRecordType.sleepSession] = [
          HcSleepSessionRecord(
            metadata: metadata(4),
            startMs: _now - _day,
            endMs: _now - _day + 8 * _hour,
            stages: const [],
          ),
        ];
        h.bridge.changesQueue.add(_page([HcDeletion(uuid(5))]));
        final report = await h.engine.runSync(trigger);
        return (h.bridge.log, h.uploader.bodies, report);
      }

      final (periodicCalls, periodicBodies, periodic) = await run(
        HealthSyncTrigger.periodic,
      );
      final (manualCalls, manualBodies, manual) = await run(
        HealthSyncTrigger.manual,
      );

      expect(manualCalls, periodicCalls);
      expect(manualBodies, periodicBodies);
      expect(periodicBodies, isNotEmpty);
      final periodicJson = periodic.toJson()..remove('trigger');
      final manualJson = manual.toJson()..remove('trigger');
      expect(manualJson, periodicJson);
      expect(
        (periodic.trigger, manual.trigger),
        (
          HealthSyncTrigger.periodic,
          HealthSyncTrigger.manual,
        ),
      );
    });

    test(
      "the server's session challenge stops the run and marks the session",
      () async {
        final h = await _harness();
        await h.store.saveChangesToken(_allTypes, 'saved');
        h.uploader.failures[0] = _sessionChallenge();
        h.bridge.records[HcRecordType.steps] = [stepsRecord(1, startMs: _now)];
        await h.engine.runSync(HealthSyncTrigger.periodic);
        h.clock = _now + _day;
        await h.engine.runSync(HealthSyncTrigger.periodic);

        final report = await h.engine.runSync(HealthSyncTrigger.periodic);

        expect(report.outcome, HealthRunOutcome.sessionExpired);
        expect(
          report.message,
          'Signed out; health sync is paused until the next sign-in.',
        );
        expect(report.retryable, isFalse);
        expect(h.store.sessionExpiredAtMs, _now);
        // Terminal: the runs after the 401 touched neither HC nor the server,
        // and the token waits for the session to come back.
        expect(h.uploader.calls, 1);
        expect(h.bridge.changesCalls, ['saved']);
        expect(h.store.changesTokenFor(_allTypes), 'saved');
        expect(h.store.lastSync!.outcome, HealthRunOutcome.sessionExpired);
        expect(h.store.lastSyncSuccessAtMs, isNull);

        // A sign-in clears the marker (HealthService does it); then it resumes.
        await h.store.clearSessionExpired();
        h.uploader.failures.clear();
        final resumed = await h.engine.runSync(HealthSyncTrigger.manual);
        expect(resumed.outcome, HealthRunOutcome.succeeded);
        expect(h.store.lastSyncSuccessAtMs, _now + _day);
      },
    );

    test(
      'a 401 without the challenge header is a failure, not a dead session',
      () async {
        final h = await _harness();
        final request = RequestOptions(path: '/health/ingest/');
        h.uploader.failures[0] = DioException.badResponse(
          statusCode: 401,
          requestOptions: request,
          response: Response<dynamic>(requestOptions: request, statusCode: 401),
        );
        h.bridge.records[HcRecordType.steps] = [stepsRecord(1, startMs: _now)];

        final report = await h.engine.runSync(HealthSyncTrigger.periodic);

        expect(report.outcome, HealthRunOutcome.failed);
        expect(report.failure, FailureCategory.unauthorized);
        expect(h.store.sessionExpiredAtMs, isNull);
      },
    );

    test('nothing happens without Health Connect or without grants', () async {
      final unavailable = await _harness(
        status: const HcStatus(
          sdk: HcSdkStatus.updateRequired,
          features: {},
          grantedPermissions: {},
        ),
      );
      final report = await unavailable.engine.runSync(
        HealthSyncTrigger.periodic,
      );
      expect(report.outcome, HealthRunOutcome.notReady);
      expect(report.message, contains('update'));
      expect(unavailable.bridge.log, ['status']);

      final ungranted = await _harness(
        status: grantedWithout(everyPermission),
      );
      final none = await ungranted.engine.runSync(HealthSyncTrigger.periodic);
      expect(none.outcome, HealthRunOutcome.notReady);
      expect(ungranted.uploader.calls, 0);
      expect(ungranted.store.changesTokenFor(_allTypes), isNull);
    });

    test('only granted types are read and tracked', () async {
      final h = await _harness(
        status: grantedWithout({HcPermissions.readSleep}),
      );
      await h.engine.runSync(HealthSyncTrigger.periodic);

      expect(h.bridge.reads.map((read) => read.type).toSet(), {
        HcRecordType.steps,
        HcRecordType.restingHeartRate,
      });
      expect(h.bridge.aggregates.map((a) => a.metric).toSet(), {
        HcAggregateMetric.stepsCountTotal,
      });
      expect(h.store.changesTokenFor('resting_heart_rate,steps'), 'token-1');
    });

    test(
      'a record the contract would refuse is skipped, the rest go',
      () async {
        final h = await _harness();
        h.bridge.records[HcRecordType.steps] = [
          stepsRecord(1, startMs: _now - _day),
          HcStepsRecord(
            metadata: metadata(2),
            startMs: _now - _day,
            endMs: _now - _day,
            count: 1,
          ),
        ];

        final report = await h.engine.runSync(HealthSyncTrigger.periodic);

        expect(report.outcome, HealthRunOutcome.partial);
        expect(report.rejected, 1);
        expect(h.sentIds('steps'), [uuid(1)]);
      },
    );
  });

  group('backfill', () {
    Future<_Harness> requested({HcStatus? status}) async {
      final h = await _harness(status: status);
      await h.store.saveBackfillRequested(requested: true);
      return h;
    }

    test(
      'walks back a week at a time to the earliest month, saving the cursor',
      () async {
        final h = await requested();
        final floor = DateTime.fromMillisecondsSinceEpoch(_now - 20 * _day);
        final earliest = DateTime(floor.year, floor.month);
        String month(DateTime at) =>
            '${at.year}-${at.month.toString().padLeft(2, '0')}';
        h.bridge.coverage = HcCoverage(
          computedAtMs: _now,
          types: [
            HcTypeCoverage(
              type: HcDataType.steps,
              byAggregate: true,
              count: 1,
              firstMonth: month(earliest),
              lastMonth: month(earliest),
            ),
            // Older, but not uploaded: the backfill does not walk to it.
            const HcTypeCoverage(
              type: HcDataType.weight,
              byAggregate: true,
              count: 1,
              firstMonth: '2016-01',
              lastMonth: '2016-01',
            ),
          ],
        );
        final floorMs = earliest.millisecondsSinceEpoch;
        final start = _floorHour(_now);

        final report = await h.engine.runBackfill();

        expect(report.backfillComplete, isTrue);
        expect(h.store.backfillStartMs, start);
        expect(h.store.backfillCursorMs, floorMs);
        // Contiguous weekly steps from the start down to the floor, each read
        // reaching 2 days further back than its step.
        final steps = <(int, int)>[];
        for (var cursor = start; cursor > floorMs; cursor -= 7 * _day) {
          final stepStart = cursor - 7 * _day < floorMs
              ? floorMs
              : cursor - 7 * _day;
          steps.add((stepStart - 2 * _day, cursor));
        }
        expect(
          h.bridge.reads
              // The coverage probe's own last-week read ends at the unaligned
              // now; backfill reads end on a cursor, which is on an hour.
              .where(
                (read) =>
                    read.type == HcRecordType.steps && read.endMs % _hour == 0,
              )
              .map((read) => (read.startMs, read.endMs)),
          steps,
        );
        for (final aggregate in h.bridge.aggregates) {
          expect(aggregate.startMs % _hour, 0);
          expect(aggregate.endMs % _hour, 0);
        }
      },
    );

    test('resumes from the saved cursor after a failed step', () async {
      final h = await requested(
        status: grantedWithout({HcPermissions.readHistory}),
      );
      // Without history the floor is first grant - 30 days.
      await h.store.saveFirstGrantAt(_now);
      h.uploader.failures[2] = DioException.connectionError(
        requestOptions: RequestOptions(path: '/health/ingest/'),
        reason: 'offline',
      );
      h.bridge.records[HcRecordType.steps] = [
        for (var day = 0; day < 30; day++)
          stepsRecord(day, startMs: _now - day * _day - _hour),
      ];

      final failed = await h.engine.runBackfill();
      expect(failed.outcome, HealthRunOutcome.failed);
      final start = _floorHour(_now);
      expect(h.store.backfillCursorMs, start - 14 * _day);

      h.bridge.reads.clear();
      final resumed = await h.engine.runBackfill();
      expect(resumed.backfillComplete, isTrue);
      expect(h.bridge.reads.first.endMs, start - 14 * _day);
      expect(h.store.backfillCursorMs, _now - 30 * _day);
      expect(
        h.sent.every((body) => body['coverage_start_ms'] == _now - 30 * _day),
        isTrue,
      );
    });

    test('stops at its step budget and continues next run', () async {
      final h = await requested(
        status: grantedWithout({HcPermissions.readHistory}),
      );
      await h.store.saveFirstGrantAt(_now);
      h.config = const HealthSyncConfig(maxBackfillStepsPerRun: 2);

      final first = await h.engine.runBackfill();
      expect(first.backfillComplete, isFalse);
      expect(h.store.backfillCursorMs, _floorHour(_now) - 14 * _day);

      await h.engine.runBackfill();
      final third = await h.engine.runBackfill();
      expect(third.backfillComplete, isTrue);
    });

    test('does nothing until the backfill is requested', () async {
      final h = await _harness();
      final report = await h.engine.runBackfill();
      expect(report.outcome, HealthRunOutcome.notReady);
      expect(h.bridge.reads, isEmpty);
    });
  });

  test('the coverage probe forecasts a year from the last week', () async {
    final h = await _harness();
    h.bridge.currentStatus = grantedOnly({HcDataType.bodyFat.readPermission});
    h.bridge.coverage = const HcCoverage(
      computedAtMs: 1,
      types: [
        HcTypeCoverage(type: HcDataType.bodyFat, byAggregate: false, count: 4),
      ],
    );
    h.bridge.records[HcRecordType.steps] = [
      for (var n = 0; n < 70; n++)
        stepsRecord(n, startMs: _now - n * 2 * _hour - 1),
    ];
    h.bridge.records[HcRecordType.restingHeartRate] = [
      for (var n = 0; n < 7; n++)
        HcRestingHeartRateRecord(
          metadata: metadata(100 + n),
          timeMs: _now - n * _day - 1,
          beatsPerMinute: 55,
        ),
    ];
    h.bridge.records[HcRecordType.sleepSession] = [
      for (var n = 0; n < 7; n++)
        HcSleepSessionRecord(
          metadata: metadata(200 + n),
          startMs: _now - n * _day - 9 * _hour,
          endMs: _now - n * _day - _hour,
          stages: [
            for (var s = 0; s < 40; s++)
              HcSleepStage(
                startMs: _now - n * _day - 9 * _hour + s * 60000,
                endMs: _now - n * _day - 9 * _hour + (s + 1) * 60000,
                stage: 'light',
              ),
          ],
        ),
    ];

    final report = await h.engine.runCoverageProbe();

    expect(report.recordsPerDay, {
      'steps': 10.0,
      'resting_heart_rate': 1.0,
      'sleep_session': 1.0,
    });
    expect(report.stagesPerDay, 40.0);
    // 12 records a day at 100 B, 40 stages at 30 B, and two hourly
    // aggregates at 139 B, for 365 days: 438,000 + 438,000 + 2,435,280.
    expect(report.forecastBytesPerYear, 3311280);
    // Every readable type is probed; only the uploaded ones are forecast.
    expect(h.bridge.probed.single, {
      HcDataType.steps,
      HcDataType.stepsCadence,
      HcDataType.restingHeartRate,
      HcDataType.sleepSession,
      HcDataType.bodyFat,
    });
    expect(report.types.single.type, HcDataType.bodyFat);
    expect(report.historyGranted, isFalse);
    expect(h.store.coverage!.toJson(), report.toJson());
  });
}
