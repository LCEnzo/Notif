import 'dart:convert';
import 'dart:math';

import 'package:hc_bridge/hc_bridge.dart';

import 'package:notif/services/failures.dart';
import 'package:notif/services/persistence.dart';

enum HealthRunKind { sync, backfill }

enum HealthSyncTrigger { periodic, manual }

enum HealthRunOutcome {
  /// Everything uploaded.
  succeeded,

  /// Uploaded what it could; [HealthRunReport.notes] says what it skipped.
  partial,

  failed,

  /// The server ended the session, or there is none: sign in to resume.
  sessionExpired,

  /// Health Connect is unavailable or nothing is granted; nothing to do.
  notReady,
}

/// What one sync or backfill run did. Persisted as JSON for the Health screen.
class HealthRunReport {
  const HealthRunReport({
    required this.kind,
    required this.outcome,
    required this.startedAtMs,
    required this.finishedAtMs,
    this.trigger,
    this.message,
    this.failure,
    this.retryable = false,
    this.uploadedItems = 0,
    this.batches = 0,
    this.rejected = 0,
    this.notes = const [],
    this.backfillComplete = false,
  });

  factory HealthRunReport.fromJson(Map<String, Object?> json) {
    T field<T>(String key) {
      final value = json[key];
      if (value is T) return value;
      throw FormatException('HealthRunReport.$key is ${value.runtimeType}');
    }

    E named<E extends Enum>(List<E> values, String key) {
      final name = field<String>(key);
      return values.firstWhere(
        (value) => value.name == name,
        orElse: () => throw FormatException('HealthRunReport.$key "$name"'),
      );
    }

    final trigger = json['trigger'];
    final failure = json['failure'];
    return HealthRunReport(
      kind: named(HealthRunKind.values, 'kind'),
      outcome: named(HealthRunOutcome.values, 'outcome'),
      startedAtMs: field<int>('started_at_ms'),
      finishedAtMs: field<int>('finished_at_ms'),
      trigger: trigger == null
          ? null
          : named(HealthSyncTrigger.values, 'trigger'),
      message: field<String?>('message'),
      failure: failure == null
          ? null
          : named(FailureCategory.values, 'failure'),
      retryable: field<bool>('retryable'),
      uploadedItems: field<int>('uploaded_items'),
      batches: field<int>('batches'),
      rejected: field<int>('rejected'),
      notes: [
        for (final note in field<List<Object?>>('notes'))
          note is String ? note : throw const FormatException('note'),
      ],
      backfillComplete: field<bool>('backfill_complete'),
    );
  }

  final HealthRunKind kind;
  final HealthRunOutcome outcome;
  final int startedAtMs;
  final int finishedAtMs;
  final HealthSyncTrigger? trigger;
  final String? message;
  final FailureCategory? failure;

  /// Whether WorkManager should retry the run with backoff.
  final bool retryable;
  final int uploadedItems;
  final int batches;

  /// Records or windows the contract would refuse, left out of every batch.
  final int rejected;
  final List<String> notes;
  final bool backfillComplete;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'outcome': outcome.name,
    'started_at_ms': startedAtMs,
    'finished_at_ms': finishedAtMs,
    'trigger': trigger?.name,
    'message': message,
    'failure': failure?.name,
    'retryable': retryable,
    'uploaded_items': uploadedItems,
    'batches': batches,
    'rejected': rejected,
    'notes': notes,
    'backfill_complete': backfillComplete,
  };
}

/// The coverage probe's answer plus the size forecast built from it.
class HealthCoverageReport {
  const HealthCoverageReport({
    required this.computedAtMs,
    required this.historyGranted,
    required this.types,
    required this.recordsPerDay,
    required this.stagesPerDay,
    required this.forecastBytesPerYear,
  });

  factory HealthCoverageReport.fromJson(Map<String, Object?> json) {
    T field<T>(Map<String, Object?> map, String key) {
      final value = map[key];
      if (value is T) return value;
      throw FormatException('HealthCoverageReport.$key is $value');
    }

    return HealthCoverageReport(
      computedAtMs: field<int>(json, 'computed_at_ms'),
      historyGranted: field<bool>(json, 'history_granted'),
      types: [
        for (final raw in field<List<Object?>>(json, 'types'))
          if (raw case final Map<String, Object?> entry)
            HcTypeCoverage(
              type: HcDataType.values.firstWhere(
                (type) => type.wire == entry['type'],
                orElse: () => throw FormatException('type ${entry['type']}'),
              ),
              byAggregate: field<bool>(entry, 'by_aggregate'),
              count: field<int>(entry, 'count'),
              capped: field<bool>(entry, 'capped'),
              firstMonth: field<String?>(entry, 'first_month'),
              lastMonth: field<String?>(entry, 'last_month'),
            )
          else
            throw const FormatException('HealthCoverageReport.types[]'),
      ],
      recordsPerDay: {
        for (final MapEntry(:key, :value) in field<Map<String, Object?>>(
          json,
          'records_per_day',
        ).entries)
          key: value is num
              ? value.toDouble()
              : throw const FormatException('records_per_day'),
      },
      stagesPerDay: field<num>(json, 'stages_per_day').toDouble(),
      forecastBytesPerYear: field<int>(json, 'forecast_bytes_per_year'),
    );
  }

  final int computedAtMs;

  /// Whether the probe ran with the history permission; without it HC hid
  /// everything before the first grant minus 30 days.
  final bool historyGranted;

  /// Every data type readable when the probe ran.
  final List<HcTypeCoverage> types;

  /// Per uploaded record type (contract list key), from the last 7 days.
  final Map<String, double> recordsPerDay;
  final double stagesPerDay;
  final int forecastBytesPerYear;

  /// Local start of the earliest month any uploaded type has data, the floor
  /// the backfill walks back to.
  int? get earliestUploadedMonthStartMs {
    final uploaded = {for (final type in HcRecordType.values) type.dataType};
    final starts = [
      for (final entry in types)
        if (uploaded.contains(entry.type) && entry.firstMonth != null)
          _monthStartMs(entry.firstMonth!),
    ];
    return starts.isEmpty ? null : starts.reduce(min);
  }

  Map<String, Object?> toJson() => {
    'computed_at_ms': computedAtMs,
    'history_granted': historyGranted,
    'types': [
      for (final entry in types)
        {
          'type': entry.type.wire,
          'by_aggregate': entry.byAggregate,
          'count': entry.count,
          'capped': entry.capped,
          'first_month': entry.firstMonth,
          'last_month': entry.lastMonth,
        },
    ],
    'records_per_day': recordsPerDay,
    'stages_per_day': stagesPerDay,
    'forecast_bytes_per_year': forecastBytesPerYear,
  };
}

/// `YYYY-MM` to local midnight on that month's first day.
int _monthStartMs(String month) {
  final parts = month.split('-');
  if (parts.length != 2) throw FormatException('month "$month"');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
  ).millisecondsSinceEpoch;
}

/// The health sync's persisted state, shared by the UI isolate and the
/// WorkManager isolate through [PreferenceStore]. Call [reload] before reading
/// anything the other isolate may have written.
class HealthSyncStore {
  HealthSyncStore(this._prefs);

  final PreferenceStore _prefs;

  static const String _prefix = 'health.v1.';
  static const String _tokenKey = '${_prefix}changes_token';
  static const String _tokenTypesKey = '${_prefix}changes_token_types';
  static const String _firstGrantKey = '${_prefix}first_grant_at_ms';
  static const String _grantedKey = '${_prefix}granted_permissions';
  static const String _grantObservedKey = '${_prefix}grant_observed_at_ms';
  static const String _backfillCursorKey = '${_prefix}backfill_cursor_ms';
  static const String _backfillStartKey = '${_prefix}backfill_start_ms';
  static const String _backfillRequestedKey = '${_prefix}backfill_requested';
  static const String _lastSyncKey = '${_prefix}last_sync';
  static const String _lastBackfillKey = '${_prefix}last_backfill';
  static const String _lastSyncSuccessKey = '${_prefix}last_sync_success_ms';
  static const String _coverageKey = '${_prefix}coverage';
  static const String _sessionExpiredKey = '${_prefix}session_expired_at_ms';
  static const String _syncRequestedKey = '${_prefix}sync_requested_at_ms';

  Future<void> reload() => _prefs.reload();

  // ── changes token ─────────────────────────────────────────

  /// The token for exactly [typesKey]'s record types. A token for another
  /// set (grants changed) is not one: its changes cover the wrong types.
  String? changesTokenFor(String typesKey) =>
      _prefs.read<String>(_tokenTypesKey) == typesKey
      ? _prefs.read<String>(_tokenKey)
      : null;

  Future<void> saveChangesToken(String typesKey, String token) async {
    await _prefs.writeString(_tokenTypesKey, typesKey);
    await _prefs.writeString(_tokenKey, token);
  }

  // ── grants ─────────────────────────────────────────────────

  int? get firstGrantAtMs => _prefs.read<int>(_firstGrantKey);

  Future<void> saveFirstGrantAt(int ms) => _prefs.writeInt(_firstGrantKey, ms);

  Future<void> clearFirstGrantAt() => _prefs.remove(_firstGrantKey);

  Set<String>? get grantedPermissions {
    final raw = _prefs.read<String>(_grantedKey);
    if (raw == null) return null;
    return raw.isEmpty ? <String>{} : raw.split(',').toSet();
  }

  int? get grantObservedAtMs => _prefs.read<int>(_grantObservedKey);

  Future<void> saveGrant(Set<String> permissions, int observedAtMs) async {
    await _prefs.writeString(
      _grantedKey,
      (permissions.toList()..sort()).join(','),
    );
    await _prefs.writeInt(_grantObservedKey, observedAtMs);
  }

  // ── backfill ───────────────────────────────────────────────

  /// Everything from this instant forward is uploaded; the backfill walks it
  /// back one week at a time.
  int? get backfillCursorMs => _prefs.read<int>(_backfillCursorKey);

  /// Where the cursor started, for progress.
  int? get backfillStartMs => _prefs.read<int>(_backfillStartKey);

  Future<void> saveBackfillCursor(int ms) =>
      _prefs.writeInt(_backfillCursorKey, ms);

  Future<void> saveBackfillStart(int ms) =>
      _prefs.writeInt(_backfillStartKey, ms);

  bool get backfillRequested =>
      _prefs.read<bool>(_backfillRequestedKey) ?? false;

  Future<void> saveBackfillRequested({required bool requested}) =>
      _prefs.writeBool(_backfillRequestedKey, requested);

  // ── reports ────────────────────────────────────────────────

  HealthRunReport? get lastSync => _readJson(
    _lastSyncKey,
    'HealthRunReport',
    HealthRunReport.fromJson,
  );

  HealthRunReport? get lastBackfill => _readJson(
    _lastBackfillKey,
    'HealthRunReport',
    HealthRunReport.fromJson,
  );

  /// When a sync last uploaded what it read, partly or fully.
  int? get lastSyncSuccessAtMs => _prefs.read<int>(_lastSyncSuccessKey);

  Future<void> saveReport(HealthRunReport report) async {
    final sync = report.kind == HealthRunKind.sync;
    await _prefs.writeString(
      sync ? _lastSyncKey : _lastBackfillKey,
      jsonEncode(report.toJson()),
    );
    if (sync &&
        (report.outcome == HealthRunOutcome.succeeded ||
            report.outcome == HealthRunOutcome.partial)) {
      await _prefs.writeInt(_lastSyncSuccessKey, report.finishedAtMs);
    }
  }

  HealthCoverageReport? get coverage => _readJson(
    _coverageKey,
    'HealthCoverageReport',
    HealthCoverageReport.fromJson,
  );

  Future<void> saveCoverage(HealthCoverageReport report) =>
      _prefs.writeString(_coverageKey, jsonEncode(report.toJson()));

  // ── session and requests ───────────────────────────────────

  int? get sessionExpiredAtMs => _prefs.read<int>(_sessionExpiredKey);

  Future<void> saveSessionExpired(int ms) =>
      _prefs.writeInt(_sessionExpiredKey, ms);

  Future<void> clearSessionExpired() => _prefs.remove(_sessionExpiredKey);

  int? get syncRequestedAtMs => _prefs.read<int>(_syncRequestedKey);

  Future<void> saveSyncRequested(int ms) =>
      _prefs.writeInt(_syncRequestedKey, ms);

  T? _readJson<T>(
    String key,
    String expected,
    T Function(Map<String, Object?>) parse,
  ) {
    final raw = _prefs.read<String>(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('not an object');
      }
      return parse(decoded);
    } on FormatException catch (error) {
      throw CorruptLocalStateException(
        key: key,
        expected: expected,
        actual: error.message,
      );
    }
  }
}
