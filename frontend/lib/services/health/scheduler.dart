import 'package:flutter/foundation.dart';
import 'package:hc_bridge/hc_bridge.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/client_events.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/health/sync_engine.dart';
import 'package:notif/services/health/sync_store.dart';
import 'package:notif/services/health/uploader.dart';
import 'package:notif/services/persistence.dart';
import 'package:notif/services/session_store.dart';
import 'package:workmanager/workmanager.dart';

/// WorkManager task names; each is also its work's unique name.
const String healthPeriodicSyncTask = 'notif.health.sync.periodic';
const String healthSyncNowTask = 'notif.health.sync.now';
const String healthBackfillTask = 'notif.health.backfill';

abstract interface class HealthScheduler {
  /// The daily sync; keeps an existing schedule.
  Future<void> ensurePeriodicSync();

  /// "Sync now": the same job, once, as soon as there is a network.
  Future<void> enqueueSyncNow();

  /// The backfill, hourly while charging on an unmetered network, until it
  /// reports completion.
  Future<void> ensureBackfill();

  Future<void> cancelBackfill();
}

class WorkmanagerHealthScheduler implements HealthScheduler {
  WorkmanagerHealthScheduler({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;
  Future<void>? _initialized;

  Future<void> _ready() =>
      _initialized ??= _workmanager.initialize(healthCallbackDispatcher);

  @override
  Future<void> ensurePeriodicSync() async {
    await _ready();
    await _workmanager.registerPeriodicTask(
      healthPeriodicSyncTask,
      healthPeriodicSyncTask,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }

  @override
  Future<void> enqueueSyncNow() async {
    await _ready();
    await _workmanager.registerOneOffTask(
      healthSyncNowTask,
      healthSyncNowTask,
      constraints: Constraints(networkType: NetworkType.connected),
      // A second tap while one is queued or running is the same request.
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }

  @override
  Future<void> ensureBackfill() async {
    await _ready();
    await _workmanager.registerPeriodicTask(
      healthBackfillTask,
      healthBackfillTask,
      frequency: const Duration(hours: 1),
      constraints: Constraints(
        networkType: NetworkType.unmetered,
        requiresCharging: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }

  @override
  Future<void> cancelBackfill() async {
    await _ready();
    await _workmanager.cancelByUniqueName(healthBackfillTask);
  }
}

/// What the WorkManager isolate runs. Both sync tasks reach [sync].
abstract interface class HealthTaskRunner {
  Future<HealthRunReport> sync(HealthSyncTrigger trigger);

  Future<HealthRunReport> backfill();

  /// Called once a backfill run reports completion.
  Future<void> backfillFinished();
}

/// Routes a WorkManager task to the runner. The result is WorkManager's:
/// false asks for a retry with backoff.
Future<bool> runHealthTask(String taskName, HealthTaskRunner runner) async {
  switch (taskName) {
    case healthPeriodicSyncTask:
      return !(await runner.sync(HealthSyncTrigger.periodic)).retryable;
    case healthSyncNowTask:
      return !(await runner.sync(HealthSyncTrigger.manual)).retryable;
    case healthBackfillTask:
      final report = await runner.backfill();
      if (report.backfillComplete) await runner.backfillFinished();
      return !report.retryable;
    default:
      // A task from an older build; nothing to do, so nothing to retry.
      return true;
  }
}

@pragma('vm:entry-point')
void healthCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      return await runHealthTask(
        taskName,
        await BackgroundHealthRunner.create(),
      );
    } on Object catch (error, stackTrace) {
      // Isolate entry point: whatever escapes is lost with the isolate, so it
      // is logged and becomes a retry.
      debugPrint('health task $taskName failed: $error\n$stackTrace');
      return false;
    }
  });
}

/// The WorkManager isolate's wiring. It re-creates only what a sync needs:
/// settings for the backend URL, the stored credential, and the preferences
/// the UI isolate shares. Requests still go through api_client; a dead
/// session is reported, and the credential is left for AuthService to drop.
class BackgroundHealthRunner implements HealthTaskRunner {
  BackgroundHealthRunner._(this._settings, this._store);

  static Future<BackgroundHealthRunner> create() async {
    final settings = AppSettingsController();
    await settings.initialized;
    final store = HealthSyncStore(await PreferenceStore.load());
    return BackgroundHealthRunner._(settings, store);
  }

  final AppSettingsController _settings;
  final HealthSyncStore _store;

  HealthSyncEngine get _engine => HealthSyncEngine(
    bridge: const MethodChannelHcBridge(),
    uploader: ApiHealthIngestUploader(_settings),
    store: _store,
    reportFailure: (failure, stackTrace) => reportClientFailure(
      settings: _settings,
      error: failure,
      stackTrace: stackTrace,
      route: 'health-sync',
      endpoint: failure.endpoint,
    ),
  );

  @override
  Future<HealthRunReport> sync(HealthSyncTrigger trigger) async {
    final signedOut = await _authenticate(HealthRunKind.sync, trigger);
    return signedOut ?? _engine.runSync(trigger);
  }

  @override
  Future<HealthRunReport> backfill() async {
    final signedOut = await _authenticate(HealthRunKind.backfill, null);
    return signedOut ?? _engine.runBackfill();
  }

  @override
  Future<void> backfillFinished() async {
    await _store.saveBackfillRequested(requested: false);
    await WorkmanagerHealthScheduler().cancelBackfill();
  }

  /// Installs the stored credential for this isolate's requests, or records
  /// and returns the signed-out report when there is none.
  Future<HealthRunReport?> _authenticate(
    HealthRunKind kind,
    HealthSyncTrigger? trigger,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final SessionCredential? credential;
    try {
      credential = await createSessionStore().read();
    } on SessionStoreException catch (error) {
      final report = HealthRunReport(
        kind: kind,
        outcome: HealthRunOutcome.failed,
        startedAtMs: now,
        finishedAtMs: now,
        trigger: trigger,
        message: error.toString(),
        failure: FailureCategory.corruptLocalState,
        retryable: true,
      );
      await _store.saveReport(report);
      return report;
    }
    if (credential != null) {
      configureApiAuth(credentialReader: () => credential);
      return null;
    }
    final report = HealthRunReport(
      kind: kind,
      outcome: HealthRunOutcome.sessionExpired,
      startedAtMs: now,
      finishedAtMs: now,
      trigger: trigger,
      message: 'Signed out; health sync is paused until the next sign-in.',
    );
    await _store.saveReport(report);
    await _store.saveSessionExpired(now);
    return report;
  }
}
