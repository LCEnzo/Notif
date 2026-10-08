import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/health/scheduler.dart';
import 'package:notif/services/health/sync_store.dart';

class _RecordingRunner implements HealthTaskRunner {
  _RecordingRunner({this.retryable = false, this.complete = false});

  final bool retryable;
  final bool complete;
  final List<String> calls = [];

  HealthRunReport _report(HealthRunKind kind) => HealthRunReport(
    kind: kind,
    outcome: retryable ? HealthRunOutcome.failed : HealthRunOutcome.succeeded,
    startedAtMs: 0,
    finishedAtMs: 0,
    retryable: retryable,
    backfillComplete: complete,
  );

  @override
  Future<HealthRunReport> sync(HealthSyncTrigger trigger) async {
    calls.add('sync ${trigger.name}');
    return _report(HealthRunKind.sync);
  }

  @override
  Future<HealthRunReport> backfill() async {
    calls.add('backfill');
    return _report(HealthRunKind.backfill);
  }

  @override
  Future<void> backfillFinished() async => calls.add('finished');
}

void main() {
  test('the periodic task and "Sync now" both run sync', () async {
    final runner = _RecordingRunner();

    expect(await runHealthTask(healthPeriodicSyncTask, runner), isTrue);
    expect(await runHealthTask(healthSyncNowTask, runner), isTrue);

    expect(runner.calls, ['sync periodic', 'sync manual']);
  });

  test('a retryable report asks WorkManager to retry', () async {
    final runner = _RecordingRunner(retryable: true);
    expect(await runHealthTask(healthSyncNowTask, runner), isFalse);
    expect(await runHealthTask(healthBackfillTask, runner), isFalse);
  });

  test(
    'a completed backfill unschedules itself; an unfinished one does not',
    () async {
      final done = _RecordingRunner(complete: true);
      await runHealthTask(healthBackfillTask, done);
      expect(done.calls, ['backfill', 'finished']);

      final ongoing = _RecordingRunner();
      await runHealthTask(healthBackfillTask, ongoing);
      expect(ongoing.calls, ['backfill']);
    },
  );

  test('an unknown task is acknowledged, not retried', () async {
    final runner = _RecordingRunner();
    expect(await runHealthTask('notif.health.retired', runner), isTrue);
    expect(runner.calls, isEmpty);
  });
}
