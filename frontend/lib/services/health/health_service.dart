import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hc_bridge/hc_bridge.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/health/scheduler.dart';
import 'package:notif/services/health/sync_engine.dart';
import 'package:notif/services/health/sync_store.dart';
import 'package:notif/services/health/uploader.dart';
import 'package:notif/services/persistence.dart';

// The model types the Health screen renders; the bridge itself stays here.
export 'package:hc_bridge/hc_bridge.dart'
    show
        HcDataType,
        HcFeature,
        HcPermissions,
        HcSdkStatus,
        HcStatus,
        HcTypeCoverage;

/// What the Health screen knows about Health Connect on this device.
@immutable
sealed class HealthAvailability {
  const HealthAvailability();
}

/// Not Android: Health Connect does not exist here.
class HealthUnsupported extends HealthAvailability {
  const HealthUnsupported();
}

class HealthChecking extends HealthAvailability {
  const HealthChecking();
}

class HealthKnown extends HealthAvailability {
  const HealthKnown(this.status);

  final HcStatus status;
}

class HealthCheckFailed extends HealthAvailability {
  const HealthCheckFailed(this.failure);

  final AppFailure failure;
}

/// The persisted sync state, as last read from the store.
@immutable
class HealthSnapshot {
  const HealthSnapshot({
    this.lastSync,
    this.lastBackfill,
    this.coverage,
    this.firstGrantAtMs,
    this.backfillCursorMs,
    this.backfillStartMs,
    this.backfillRequested = false,
    this.sessionExpiredAtMs,
    this.syncRequestedAtMs,
    this.lastSyncSuccessAtMs,
  });

  final HealthRunReport? lastSync;
  final HealthRunReport? lastBackfill;
  final HealthCoverageReport? coverage;
  final int? firstGrantAtMs;
  final int? backfillCursorMs;
  final int? backfillStartMs;
  final bool backfillRequested;
  final int? sessionExpiredAtMs;
  final int? syncRequestedAtMs;
  final int? lastSyncSuccessAtMs;

  bool get sessionExpired => sessionExpiredAtMs != null;

  /// A "Sync now" that no run has answered yet.
  bool get syncPending {
    final requested = syncRequestedAtMs;
    if (requested == null) return false;
    final last = lastSync;
    return last == null || last.startedAtMs < requested;
  }
}

/// The Health screen's controller: HC status and grants in this isolate,
/// sync state read back from the store the WorkManager isolate writes.
class HealthService extends ChangeNotifier {
  HealthService(
    AuthService auth, {
    HcBridge bridge = const MethodChannelHcBridge(),
    HealthScheduler? scheduler,
    Future<PreferenceStore> Function() preferences = PreferenceStore.load,
    EpochClock? clock,
    bool? supported,
  }) : _auth = auth,
       _bridge = bridge,
       _scheduler = scheduler ?? WorkmanagerHealthScheduler(),
       _preferences = preferences,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    _lastAuthState = auth.state;
    auth.addListener(_onAuthChanged);
  }

  AuthService _auth;
  AppSettingsController? _settings;
  final HcBridge _bridge;
  final HealthScheduler _scheduler;
  final Future<PreferenceStore> Function() _preferences;
  final EpochClock _clock;
  Future<HealthSyncStore>? _store;
  late AuthState _lastAuthState;
  bool _disposed = false;

  /// Whether this platform has Health Connect at all.
  final bool supported;

  HealthAvailability _availability = const HealthChecking();
  HealthSnapshot _snapshot = const HealthSnapshot();
  AppFailure? _actionFailure;
  bool _granting = false;
  bool _probing = false;

  HealthAvailability get availability =>
      supported ? _availability : const HealthUnsupported();
  HealthSnapshot get snapshot => _snapshot;

  /// The last failed button press: grant, probe, sync now or backfill.
  AppFailure? get actionFailure => _actionFailure;
  bool get granting => _granting;
  bool get probing => _probing;

  HcStatus? get status => switch (availability) {
    HealthKnown(:final status) => status,
    _ => null,
  };

  /// `coverage_start_ms` as the next batch will carry it.
  int? get coverageStartMs {
    final status = this.status;
    final firstGrant = _snapshot.firstGrantAtMs;
    if (status == null || status.historyGranted || firstGrant == null) {
      return null;
    }
    return firstGrant - historyWindowMs;
  }

  /// How far back the backfill walks: the earliest month the probe saw with
  /// the history permission, else the HC read floor.
  int? get backfillFloorMs {
    final status = this.status;
    if (status == null) return null;
    if (status.historyGranted) {
      final coverage = _snapshot.coverage;
      if (coverage == null || !coverage.historyGranted) return null;
      return coverage.earliestUploadedMonthStartMs ?? _snapshot.backfillStartMs;
    }
    return coverageStartMs;
  }

  /// 0..1, or null before the backfill has a floor and a start.
  double? get backfillProgress {
    final start = _snapshot.backfillStartMs;
    final cursor = _snapshot.backfillCursorMs;
    final floor = backfillFloorMs;
    if (start == null || cursor == null || floor == null) return null;
    if (start <= floor) return 1;
    return ((start - cursor) / (start - floor)).clamp(0, 1).toDouble();
  }

  void updateDependencies(AuthService auth, AppSettingsController? settings) {
    if (!identical(auth, _auth)) {
      _auth.removeListener(_onAuthChanged);
      _auth = auth;
      _lastAuthState = auth.state;
      auth.addListener(_onAuthChanged);
    }
    _settings = settings;
  }

  Future<HealthSyncStore> _openStore() =>
      _store ??= _preferences().then(HealthSyncStore.new);

  Future<HealthSyncEngine> _engine() async => HealthSyncEngine(
    bridge: _bridge,
    uploader: ApiHealthIngestUploader(_settings),
    store: await _openStore(),
    clock: _clock,
  );

  /// Re-reads HC status and grants, keeps the schedules in step with them,
  /// and reloads the sync state.
  Future<void> refresh() async {
    if (!supported) {
      _notify();
      return;
    }
    try {
      final status = await (await _engine()).observe();
      _availability = HealthKnown(status);
      await reloadSnapshot();
      await _syncSchedules(status);
    } on HcBridgeException catch (error) {
      _availability = HealthCheckFailed(_bridgeFailure(error));
    } on Exception catch (error) {
      _availability = HealthCheckFailed(AppFailure.from(error));
    }
    _notify();
  }

  /// Reads what the WorkManager isolate last wrote.
  Future<void> reloadSnapshot() async {
    try {
      final store = await _openStore();
      await store.reload();
      _snapshot = HealthSnapshot(
        lastSync: store.lastSync,
        lastBackfill: store.lastBackfill,
        coverage: store.coverage,
        firstGrantAtMs: store.firstGrantAtMs,
        backfillCursorMs: store.backfillCursorMs,
        backfillStartMs: store.backfillStartMs,
        backfillRequested: store.backfillRequested,
        sessionExpiredAtMs: store.sessionExpiredAtMs,
        syncRequestedAtMs: store.syncRequestedAtMs,
        lastSyncSuccessAtMs: store.lastSyncSuccessAtMs,
      );
    } on Exception catch (error) {
      _actionFailure = AppFailure.from(error);
    }
    _notify();
  }

  /// What Notif would ask for that is not granted yet.
  Set<String> get missingPermissions {
    final status = this.status;
    if (status == null) return const {};
    return HcPermissions.requestable(
      status,
    ).difference(status.grantedPermissions);
  }

  /// Shows Health Connect's permission sheet for what is missing, then
  /// probes coverage if none has run yet.
  Future<void> grantAccess() => _action(
    () async {
      if (status == null) await refresh();
      final missing = missingPermissions;
      if (missing.isEmpty) return;
      await _bridge.requestPermissions(missing);
      await refresh();
      final readable = status?.anyDataReadable ?? false;
      if (readable && _snapshot.coverage == null) await _probe();
    },
    busy: (value) => _granting = value,
  );

  Future<void> runProbe() => _action(_probe, busy: (value) => _probing = value);

  Future<void> _probe() async {
    await (await _engine()).runCoverageProbe();
    await reloadSnapshot();
  }

  /// Queues the sync job to run once, now; the same job the daily schedule
  /// runs.
  Future<void> syncNow() => _action(() async {
    final store = await _openStore();
    await store.saveSyncRequested(_clock());
    await _scheduler.enqueueSyncNow();
    await reloadSnapshot();
  });

  Future<void> startBackfill() => _action(() async {
    final store = await _openStore();
    await store.saveBackfillRequested(requested: true);
    await _scheduler.ensureBackfill();
    await reloadSnapshot();
  });

  Future<void> _syncSchedules(HcStatus status) async {
    if (status.readableTypes.isEmpty || !_auth.isAuthenticated) return;
    await _scheduler.ensurePeriodicSync();
    if (_snapshot.backfillRequested) {
      if (_snapshot.lastBackfill?.backfillComplete ?? false) {
        await _scheduler.cancelBackfill();
      } else {
        await _scheduler.ensureBackfill();
      }
    }
  }

  Future<void> _action(
    Future<void> Function() body, {
    void Function(bool value)? busy,
  }) async {
    _actionFailure = null;
    busy?.call(true);
    _notify();
    try {
      await body();
    } on HcBridgeException catch (error) {
      _actionFailure = _bridgeFailure(error);
    } on Exception catch (error) {
      _actionFailure = AppFailure.from(error);
    } finally {
      busy?.call(false);
      _notify();
    }
  }

  /// A sign-in after the session died is what a paused health sync waits
  /// for, so it clears the marker the WorkManager isolate left.
  void _onAuthChanged() {
    final previous = _lastAuthState;
    final current = _lastAuthState = _auth.state;
    if (current is AuthAuthenticated &&
        (previous is AuthAnonymous || previous is AuthExpired)) {
      unawaited(_clearSessionExpired());
    }
  }

  Future<void> _clearSessionExpired() async {
    try {
      final store = await _openStore();
      await store.clearSessionExpired();
      await reloadSnapshot();
    } on Exception catch (error) {
      _actionFailure = AppFailure.from(error);
      _notify();
    }
  }

  AppFailure _bridgeFailure(HcBridgeException error) => AppFailure(
    category: switch (error.code) {
      HcErrorCode.permissionDenied => FailureCategory.forbidden,
      HcErrorCode.malformedResponse => FailureCategory.contractViolation,
      HcErrorCode.unavailable ||
      HcErrorCode.rateLimited => FailureCategory.sourceBlockedDegraded,
      _ => FailureCategory.unexpectedFailure,
    },
    message: switch (error.code) {
      HcErrorCode.noActivity =>
        'Open Notif in the foreground to change Health Connect access.',
      HcErrorCode.requestInProgress =>
        'A Health Connect permission request is already open.',
      _ => error.toString(),
    },
    endpoint: 'health_connect.${error.operation}',
    cause: error,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
