import 'dart:math';

import 'package:hc_bridge/hc_bridge.dart';
import 'package:notif/services/api_client.dart' show isSessionChallengeError;
import 'package:notif/services/failures.dart';
import 'package:notif/services/health/batching.dart';
import 'package:notif/services/health/ingest_items.dart';
import 'package:notif/services/health/sync_store.dart';
import 'package:notif/services/health/uploader.dart';

typedef EpochClock = int Function();

/// Receives each failed run's classified failure, e.g. for the client-event
/// sink. Best effort: must not throw.
typedef HealthFailureReporter =
    Future<void> Function(AppFailure failure, StackTrace stackTrace);

const int dayMs = 86400000;

const String _signInMessage =
    'Signed out; health sync is paused until the next sign-in.';
const int hourMs = IngestLimits.hourMs;

/// Without the history permission HC hides records that start before the
/// first grant minus this (plan fact 1).
const int historyWindowMs = 30 * dayMs;

/// Sizes the coverage forecast uses (plan, options C): a stored record row,
/// one sleep stage inside its session's JSON, one hourly aggregate row.
abstract final class HealthStorageEstimate {
  static const int bytesPerRecord = 100;
  static const int bytesPerStage = 30;
  static const int bytesPerAggregateHour = 139;
}

class HealthSyncConfig {
  const HealthSyncConfig({
    this.trailingDays = 7,
    this.expiredDays = 30,
    this.readMarginDays = 2,
    this.backfillStepDays = 7,
    this.pageSize = 1000,
    this.maxReadPages = 200,
    this.maxChangePages = 200,
    this.maxBackfillStepsPerRun = 52,
  });

  /// The daily re-read, on top of the changes token.
  final int trailingDays;

  /// The re-read after a lost changes token.
  final int expiredDays;

  /// How far each read window reaches back before its start, so a record
  /// that straddles a window edge is read whatever HC's filter semantics
  /// (start-in-range or contained) turn out to be. Duplicates are harmless.
  final int readMarginDays;
  final int backfillStepDays;
  final int pageSize;

  /// Caps per `readRecords` window and per `getChanges` stream; exceeding
  /// the read cap fails the run rather than truncating silently.
  final int maxReadPages;
  final int maxChangePages;
  final int maxBackfillStepsPerRun;
}

/// The run could not start: HC is unavailable or nothing is granted.
class HealthNotReadyException implements Exception {
  const HealthNotReadyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A read window held more pages than [HealthSyncConfig.maxReadPages].
class HealthReadBoundExceeded implements Exception {
  const HealthReadBoundExceeded(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The periodic sync, "Sync now", the backfill and the coverage probe. The
/// first two are the same [runSync]; the trigger is only recorded.
class HealthSyncEngine {
  HealthSyncEngine({
    required HcBridge bridge,
    required HealthIngestUploader uploader,
    required HealthSyncStore store,
    EpochClock? clock,
    HealthFailureReporter? reportFailure,
    this.config = const HealthSyncConfig(),
  }) : _bridge = bridge,
       _uploader = uploader,
       _store = store,
       _clock = clock ?? _systemClock,
       _reportFailure = reportFailure;

  final HcBridge _bridge;
  final HealthIngestUploader _uploader;
  final HealthSyncStore _store;
  final EpochClock _clock;
  final HealthFailureReporter? _reportFailure;
  final HealthSyncConfig config;

  static int _systemClock() => DateTime.now().millisecondsSinceEpoch;

  /// HC's status, with the grant bookkeeping it implies.
  Future<HcStatus> observe() async {
    final status = await _bridge.status();
    await _recordGrants(status, _clock());
    return status;
  }

  /// The earliest instant HC lets this app read, as the contract's
  /// `coverage_start_ms`: null with the history permission.
  int? coverageStartFor(HcStatus status) {
    if (status.historyGranted) return null;
    final firstGrant = _store.firstGrantAtMs;
    return firstGrant == null ? null : max(0, firstGrant - historyWindowMs);
  }

  Future<HealthRunReport> runSync(HealthSyncTrigger trigger) =>
      _run(HealthRunKind.sync, trigger, _sync);

  Future<HealthRunReport> runBackfill({
    Duration budget = const Duration(minutes: 8),
  }) => _run(HealthRunKind.backfill, null, (run) => _backfill(run, budget));

  Future<HealthCoverageReport> runCoverageProbe() async {
    await _store.reload();
    final status = await observe();
    _checkAvailable(status);
    if (!status.anyDataReadable) {
      throw const HealthNotReadyException(
        'No Health Connect read access is granted.',
      );
    }
    return _probeCoverage(status);
  }

  // ── runs ───────────────────────────────────────────────────

  Future<HealthRunReport> _run(
    HealthRunKind kind,
    HealthSyncTrigger? trigger,
    Future<HealthRunReport> Function(_Run run) body,
  ) async {
    final run = _Run(kind, trigger, _clock());
    HealthRunReport report;
    try {
      await _store.reload();
      // Terminal until a sign-in clears it: a dead session cannot heal, so
      // reading HC again only to collect another 401 is wasted quota.
      if (_store.sessionExpiredAtMs != null) {
        return run.finish(
          HealthRunOutcome.sessionExpired,
          _clock(),
          message: _signInMessage,
          failure: FailureCategory.unauthorized,
        );
      }
      report = await body(run);
    } on Exception catch (error, stackTrace) {
      report = await _failed(run, error, stackTrace);
    }
    await _store.saveReport(report);
    if (report.outcome == HealthRunOutcome.sessionExpired) {
      await _store.saveSessionExpired(report.finishedAtMs);
    }
    return report;
  }

  Future<HealthRunReport> _failed(
    _Run run,
    Exception error,
    StackTrace stackTrace,
  ) async {
    if (isSessionChallengeError(error)) {
      return run.finish(
        HealthRunOutcome.sessionExpired,
        _clock(),
        message: _signInMessage,
        failure: FailureCategory.unauthorized,
      );
    }
    final failure = _classify(error, run.status);
    await _reportFailure?.call(failure, stackTrace);
    return run.finish(
      HealthRunOutcome.failed,
      _clock(),
      message: failure.message,
      failure: failure.category,
      retryable: _isTransient(error, failure.category),
    );
  }

  Future<HealthRunReport> _sync(_Run run) async {
    await _store.reload();
    final status = run.status = await _bridge.status();
    final now = run.startedAtMs;
    await _recordGrants(status, now);
    final types = _readyTypesOrNull(status, run);
    if (types == null) return run.finish(HealthRunOutcome.notReady, _clock());

    final coverageStartMs = coverageStartFor(status);
    final typesKey = _typesKey(types);
    final items = _ItemSet();
    var windowDays = config.trailingDays;
    String? tokenToSave;

    final stored = _store.changesTokenFor(typesKey);
    if (stored == null) {
      // Taken before the reads, so a change landing during them is in the
      // next run's stream.
      tokenToSave = await _bridge.changesToken(types.toSet());
      run.notes.add('Started change tracking.');
    } else {
      switch (await _pullChanges(stored)) {
        case _ChangesPulled(:final nextToken, :final changes, :final truncated):
          changes.forEach(items.addChange);
          tokenToSave = nextToken;
          if (truncated) {
            run.notes.add(
              'Changes exceeded ${config.maxChangePages} pages; the rest '
              'come next run.',
            );
          }
        case _ChangesExpired():
          tokenToSave = await _bridge.changesToken(types.toSet());
          windowDays = config.expiredDays;
          run.notes.add(
            'The changes token expired; re-read ${config.expiredDays} days.',
          );
        case _ChangesFailed(:final error):
          // Transient (binder or HC database): keep the token, the trailing
          // re-read still runs, and the next run pulls the same changes.
          run.partial = true;
          run.notes.add(
            'Changes unavailable (${error.code.wire}: ${error.message}); '
            'kept the token for the next run.',
          );
      }
    }

    final startMs = now - windowDays * dayMs;
    await _readInto(items, types, startMs, now);
    final tally = await _upload(items, coverageStartMs);

    // Only after every batch landed: a failed run re-pulls the same changes.
    if (tokenToSave != null) {
      await _store.saveChangesToken(typesKey, tokenToSave);
    }
    await _store.clearSessionExpired();
    return run.finish(
      run.partial || tally.rejected > 0
          ? HealthRunOutcome.partial
          : HealthRunOutcome.succeeded,
      _clock(),
      tally: tally,
    );
  }

  Future<HealthRunReport> _backfill(_Run run, Duration budget) async {
    await _store.reload();
    final status = run.status = await _bridge.status();
    await _recordGrants(status, run.startedAtMs);
    final types = _readyTypesOrNull(status, run);
    if (types == null) return run.finish(HealthRunOutcome.notReady, _clock());
    if (!_store.backfillRequested) {
      return run.finish(
        HealthRunOutcome.notReady,
        _clock(),
        message: 'The backfill has not been started.',
      );
    }

    final coverageStartMs = coverageStartFor(status);
    final int floor;
    if (status.historyGranted) {
      var coverage = _store.coverage;
      if (coverage == null || !coverage.historyGranted) {
        coverage = await _probeCoverage(status);
      }
      // No month with data means nothing to walk back through.
      floor = coverage.earliestUploadedMonthStartMs ?? run.startedAtMs;
    } else {
      floor = coverageStartMs ?? run.startedAtMs;
    }

    final storedCursor = _store.backfillCursorMs;
    var cursor = storedCursor ?? _floorHour(run.startedAtMs);
    if (storedCursor == null) {
      await _store.saveBackfillStart(cursor);
      await _store.saveBackfillCursor(cursor);
    }

    final deadline = run.startedAtMs + budget.inMilliseconds;
    final stepMs = config.backfillStepDays * dayMs;
    var tally = const _Tally();
    var steps = 0;
    while (cursor > floor &&
        steps < config.maxBackfillStepsPerRun &&
        _clock() < deadline) {
      final start = max(cursor - stepMs, floor);
      final items = _ItemSet();
      await _readInto(items, types, start, cursor);
      tally = tally + await _upload(items, coverageStartMs);
      cursor = start;
      await _store.saveBackfillCursor(cursor);
      steps++;
    }

    final complete = cursor <= floor;
    final reached = DateTime.fromMillisecondsSinceEpoch(cursor);
    return run.finish(
      tally.rejected > 0
          ? HealthRunOutcome.partial
          : HealthRunOutcome.succeeded,
      _clock(),
      tally: tally,
      backfillComplete: complete,
      message: complete
          ? 'Backfill complete.'
          : 'Walked back to ${_date(reached)} in $steps weeks; '
                'continuing next run.',
    );
  }

  /// Probes every readable data type; the forecast covers the uploaded ones.
  Future<HealthCoverageReport> _probeCoverage(HcStatus status) async {
    final probe = await _bridge.coverageProbe(
      status.readableDataTypes.toSet(),
    );
    final types = status.readableTypes;
    final now = _clock();
    final weekStart = now - 7 * dayMs;
    final perDay = <String, double>{};
    var stages = 0;
    for (final type in types) {
      final records = await _readAll(type, weekStart, now);
      perDay[type.wire] = records.length / 7;
      for (final record in records) {
        if (record is HcSleepSessionRecord) stages += record.stages.length;
      }
    }
    final stagesPerDay = stages / 7;
    final metrics = HcAggregateMetric.values
        .where((metric) => types.contains(metric.recordType))
        .length;
    final forecast =
        perDay.values.fold<double>(0, (sum, rate) => sum + rate) *
            365 *
            HealthStorageEstimate.bytesPerRecord +
        stagesPerDay * 365 * HealthStorageEstimate.bytesPerStage +
        metrics * 365 * 24 * HealthStorageEstimate.bytesPerAggregateHour;
    final report = HealthCoverageReport(
      computedAtMs: now,
      historyGranted: status.historyGranted,
      types: probe.types,
      recordsPerDay: perDay,
      stagesPerDay: stagesPerDay,
      forecastBytesPerYear: forecast.round(),
    );
    await _store.saveCoverage(report);
    return report;
  }

  // ── pieces ─────────────────────────────────────────────────

  /// Sets `first_grant_at` the first time any data read is granted, and
  /// clears it when none is: HC re-anchors its 30-day window on a fresh
  /// grant. An observed time is never earlier than the real grant, so the
  /// coverage it implies errs towards "gap", never towards a false zero.
  Future<void> _recordGrants(HcStatus status, int now) async {
    if (!status.available) return;
    if (!status.anyDataReadable) {
      if (_store.firstGrantAtMs != null) await _store.clearFirstGrantAt();
    } else if (_store.firstGrantAtMs == null) {
      await _store.saveFirstGrantAt(now);
    }
    await _store.saveGrant(status.grantedPermissions, now);
  }

  List<HcRecordType>? _readyTypesOrNull(HcStatus status, _Run run) {
    try {
      return _readyTypes(status);
    } on HealthNotReadyException catch (error) {
      run.notReadyMessage = error.message;
      return null;
    }
  }

  List<HcRecordType> _readyTypes(HcStatus status) {
    _checkAvailable(status);
    final types = status.readableTypes;
    if (types.isEmpty) {
      throw const HealthNotReadyException(
        'No read access to steps, resting heart rate or sleep is granted.',
      );
    }
    return types;
  }

  static void _checkAvailable(HcStatus status) {
    switch (status.sdk) {
      case HcSdkStatus.unavailable:
        throw const HealthNotReadyException(
          'Health Connect is not available on this device.',
        );
      case HcSdkStatus.updateRequired:
        throw const HealthNotReadyException(
          'Health Connect needs an update from the Play Store.',
        );
      case HcSdkStatus.available:
        break;
    }
  }

  Future<_ChangesPull> _pullChanges(String token) async {
    final latest = <String, _Change>{};
    var current = token;
    for (var pages = 1; ; pages++) {
      final HcChangesPage page;
      try {
        page = await _bridge.changes(current);
      } on HcBridgeException catch (error) {
        if (_transientChangesErrors.contains(error.code)) {
          return _ChangesFailed(error);
        }
        rethrow;
      }
      if (page.tokenExpired) return const _ChangesExpired();
      for (final change in page.changes) {
        final id = switch (change) {
          HcUpsertion(:final record) => record.metadata.id,
          HcDeletion(:final id) => id,
        };
        // Contract rule 3: the last change per id wins, so a deletion
        // followed by a rewrite is not sent as a deletion.
        latest
          ..remove(id)
          ..[id] = _Change(change, page.observedAtMs);
      }
      current = page.nextToken;
      if (!page.hasMore || pages >= config.maxChangePages) {
        return _ChangesPulled(
          nextToken: current,
          changes: latest.values.toList(growable: false),
          truncated: page.hasMore,
        );
      }
    }
  }

  static const Set<HcErrorCode> _transientChangesErrors = {
    HcErrorCode.remote,
    HcErrorCode.io,
  };

  /// Records of [types] in `[startMs - margin, endMs)` and the hourly windows
  /// covering `[startMs, endMs)`.
  Future<void> _readInto(
    _ItemSet items,
    List<HcRecordType> types,
    int startMs,
    int endMs,
  ) async {
    final readFrom = max(0, startMs - config.readMarginDays * dayMs);
    for (final type in types) {
      (await _readAll(type, readFrom, endMs)).forEach(items.addRecord);
    }
    final windowStart = _floorHour(startMs);
    final windowEnd = endMs % hourMs == 0 ? endMs : _floorHour(endMs) + hourMs;
    for (final metric in HcAggregateMetric.values) {
      if (!types.contains(metric.recordType)) continue;
      for (var chunk = windowStart; chunk < windowEnd;) {
        final chunkEnd = min(
          windowEnd,
          chunk + IngestLimits.maxWindowHours * hourMs,
        );
        items.addWindow(
          await _bridge.aggregateHourly(
            metric,
            startMs: chunk,
            endMs: chunkEnd,
          ),
        );
        chunk = chunkEnd;
      }
    }
  }

  Future<List<HcRecord>> _readAll(
    HcRecordType type,
    int startMs,
    int endMs,
  ) async {
    final records = <HcRecord>[];
    String? token;
    var pages = 0;
    do {
      if (pages >= config.maxReadPages) {
        throw HealthReadBoundExceeded(
          '${type.wire} between $startMs and $endMs holds more than '
          '${config.maxReadPages} pages',
        );
      }
      final page = await _bridge.readRecords(
        type,
        startMs: startMs,
        endMs: endMs,
        pageToken: token,
        pageSize: config.pageSize,
      );
      records.addAll(page.records);
      token = page.nextPageToken;
      pages++;
    } while (token != null);
    return records;
  }

  Future<_Tally> _upload(_ItemSet items, int? coverageStartMs) async {
    final packed = packBatches(items.all, coverageStartMs: coverageStartMs);
    var uploaded = 0;
    for (final batch in packed.batches) {
      await _uploader.upload(batch.body);
      uploaded += batch.items.length;
    }
    final skipped = [
      ...items.rejections.map((rejection) => rejection.toString()),
      for (final item in packed.oversized)
        '${item.list.key} ${item.hcId ?? ''}: larger than a batch',
    ];
    return _Tally(
      batches: packed.batches.length,
      uploadedItems: uploaded,
      rejected: skipped.length,
      notes: skipped,
    );
  }

  AppFailure _classify(Exception error, HcStatus? status) {
    if (error is HcBridgeException) {
      final backgroundOff =
          error.code == HcErrorCode.permissionDenied &&
          status != null &&
          !status.backgroundGranted;
      return AppFailure(
        category: switch (error.code) {
          HcErrorCode.permissionDenied => FailureCategory.forbidden,
          HcErrorCode.rateLimited ||
          HcErrorCode.unavailable => FailureCategory.sourceBlockedDegraded,
          HcErrorCode.malformedResponse => FailureCategory.contractViolation,
          _ => FailureCategory.unexpectedFailure,
        },
        message: backgroundOff
            ? 'Background access is off, so health sync runs only while '
                  'Notif is open.'
            : error.toString(),
        endpoint: 'health_connect.${error.operation}',
        cause: error,
      );
    }
    if (error is HealthReadBoundExceeded) {
      return AppFailure(
        category: FailureCategory.unexpectedFailure,
        message: error.message,
        cause: error,
      );
    }
    return AppFailure.from(error, endpoint: healthIngestEndpoint);
  }

  static bool _isTransient(Exception error, FailureCategory category) {
    if (error is HcBridgeException) {
      return const {
        HcErrorCode.rateLimited,
        HcErrorCode.io,
        HcErrorCode.remote,
        HcErrorCode.unexpected,
      }.contains(error.code);
    }
    return const {
      FailureCategory.networkUnavailable,
      FailureCategory.timeout,
      FailureCategory.serverError,
      FailureCategory.sourceBlockedDegraded,
    }.contains(category);
  }
}

/// The sorted type wire names a changes token was issued for.
String _typesKey(List<HcRecordType> types) =>
    (types.map((type) => type.wire).toList()..sort()).join(',');

int _floorHour(int ms) => ms - ms % hourMs;

String _date(DateTime local) =>
    '${local.year}-${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

class _Run {
  _Run(this.kind, this.trigger, this.startedAtMs);

  final HealthRunKind kind;
  final HealthSyncTrigger? trigger;
  final int startedAtMs;
  final List<String> notes = [];
  HcStatus? status;
  String? notReadyMessage;
  bool partial = false;

  HealthRunReport finish(
    HealthRunOutcome outcome,
    int finishedAtMs, {
    String? message,
    FailureCategory? failure,
    bool retryable = false,
    _Tally tally = const _Tally(),
    bool backfillComplete = false,
  }) => HealthRunReport(
    kind: kind,
    outcome: outcome,
    startedAtMs: startedAtMs,
    finishedAtMs: finishedAtMs,
    trigger: trigger,
    message: message ?? notReadyMessage,
    failure: failure,
    retryable: retryable,
    uploadedItems: tally.uploadedItems,
    batches: tally.batches,
    rejected: tally.rejected,
    // Bounded: a run that skips thousands of records stores the first few.
    notes: [...notes, ...tally.notes].take(12).toList(growable: false),
    backfillComplete: backfillComplete,
  );
}

class _Tally {
  const _Tally({
    this.batches = 0,
    this.uploadedItems = 0,
    this.rejected = 0,
    this.notes = const [],
  });

  final int batches;
  final int uploadedItems;
  final int rejected;
  final List<String> notes;

  _Tally operator +(_Tally other) => _Tally(
    batches: batches + other.batches,
    uploadedItems: uploadedItems + other.uploadedItems,
    rejected: rejected + other.rejected,
    notes: [...notes, ...other.notes],
  );
}

class _Change {
  const _Change(this.change, this.observedAtMs);

  final HcChange change;
  final int observedAtMs;
}

sealed class _ChangesPull {
  const _ChangesPull();
}

class _ChangesPulled extends _ChangesPull {
  const _ChangesPulled({
    required this.nextToken,
    required this.changes,
    required this.truncated,
  });

  final String nextToken;
  final List<_Change> changes;
  final bool truncated;
}

class _ChangesExpired extends _ChangesPull {
  const _ChangesExpired();
}

class _ChangesFailed extends _ChangesPull {
  const _ChangesFailed(this.error);

  final HcBridgeException error;
}

/// One upload's contents: records de-duplicated by id (newest version wins),
/// deletions, windows, and what the contract would refuse.
class _ItemSet {
  final Map<String, MappedRecord> _records = {};
  final List<IngestItem> _deletions = [];
  final List<IngestItem> _windows = [];
  final List<IngestRejection> rejections = [];

  List<IngestItem> get all => [
    for (final record in _records.values) record.item,
    ..._deletions,
    ..._windows,
  ];

  void addRecord(HcRecord record) {
    switch (mapRecord(record)) {
      case Accepted(:final value):
        final id = value.item.hcId!;
        final existing = _records[id];
        if (existing == null ||
            existing.lastModifiedMs <= value.lastModifiedMs) {
          _records[id] = value;
        }
      case Refused(:final rejection):
        rejections.add(rejection);
    }
  }

  void addChange(_Change change) {
    switch (change.change) {
      case HcUpsertion(:final record):
        addRecord(record);
      case HcDeletion(:final id):
        switch (mapDeletion(id, change.observedAtMs)) {
          case Accepted(:final value):
            _deletions.add(value);
          case Refused(:final rejection):
            rejections.add(rejection);
        }
    }
  }

  void addWindow(HcAggregateWindow window) {
    switch (mapWindow(window)) {
      case Accepted(:final value):
        _windows.add(value);
      case Refused(:final rejection):
        rejections.add(rejection);
    }
  }
}
