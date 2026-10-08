import 'dart:convert';

import 'package:hc_bridge/hc_bridge.dart';
import 'package:notif/generated/openapi.enums.swagger.dart' as enums;
import 'package:notif/generated/openapi.swagger.dart' as api;

/// The ingest contract's bounds (docs/architecture/health-ingest.md, Limits).
abstract final class IngestLimits {
  static const int maxBytes = 4 * 1024 * 1024;
  static const int maxItems = 5000;
  static const int hourMs = 3600000;
  static const int maxWindowHours = 744;
  static const int maxEpochMs = 4102444800000;
  static const int maxZoneOffsetS = 64800;
  static const int maxStringLength = 255;
  static const int maxTextLength = 10000;
  static const int maxSleepStages = 10000;
  static const int maxStepsCount = 10000000;
  static const int maxBeatsPerMinute = 1000;
  static const int maxAggregateValue = 1000000000;
  static const int maxDataOrigins = 100;
}

/// The request's lists, in the order a batch body writes them.
enum IngestList {
  steps('steps'),
  restingHeartRate('resting_heart_rate'),
  sleepSession('sleep_session'),
  deletions('deletions'),
  aggregateWindows('aggregate_windows');

  const IngestList(this.key);

  final String key;
}

/// One entry of an ingest list, JSON-encoded once so batching can count its
/// exact UTF-8 size.
class IngestItem {
  IngestItem._(this.list, this.cost, Map<String, dynamic> json, {this.hcId})
    : encoded = jsonEncode(json) {
    encodedBytes = utf8.encode(encoded).length;
  }

  factory IngestItem.steps(api.StepsRecordRequest record) => IngestItem._(
    IngestList.steps,
    1,
    record.toJson(),
    hcId: record.hcId,
  );

  factory IngestItem.restingHeartRate(
    api.RestingHeartRateRecordRequest record,
  ) => IngestItem._(
    IngestList.restingHeartRate,
    1,
    record.toJson(),
    hcId: record.hcId,
  );

  factory IngestItem.sleepSession(api.SleepSessionRecordRequest record) =>
      IngestItem._(
        IngestList.sleepSession,
        1,
        record.toJson(),
        hcId: record.hcId,
      );

  factory IngestItem.deletion(api.HealthDeletionRequest deletion) =>
      IngestItem._(
        IngestList.deletions,
        1,
        deletion.toJson(),
        hcId: deletion.hcId,
      );

  /// A window costs one item per hour it spans, buckets or not.
  factory IngestItem.window(api.HealthAggregateWindowRequest window) =>
      IngestItem._(
        IngestList.aggregateWindows,
        (window.endMs - window.startMs) ~/ IngestLimits.hourMs,
        window.toJson(),
      );

  final IngestList list;

  /// What this entry counts against the per-batch item cap.
  final int cost;
  final String encoded;
  late final int encodedBytes;

  /// The HC record id, for records and deletions.
  final String? hcId;
}

/// A record or window the contract would refuse, kept out of every batch so
/// that one odd value never stalls a sync.
class IngestRejection {
  const IngestRejection({required this.what, required this.reason});

  final String what;
  final String reason;

  @override
  String toString() => '$what: $reason';
}

/// A mapping outcome: the request entry, or why the contract would refuse it.
sealed class Mapped<T> {
  const Mapped();
}

class Accepted<T> extends Mapped<T> {
  const Accepted(this.value);

  final T value;
}

class Refused<T> extends Mapped<T> {
  const Refused(this.rejection);

  final IngestRejection rejection;
}

/// A record mapped for upload, with its version for de-duplication.
class MappedRecord {
  const MappedRecord(this.item, this.lastModifiedMs);

  final IngestItem item;
  final int lastModifiedMs;
}

/// [record] as its contract request type, or why the contract would refuse it.
/// Sleep stages shorter than a millisecond are dropped: truncating HC's
/// nanosecond instants leaves them with no duration, which the contract
/// refuses, and they carry nothing at millisecond resolution.
Mapped<MappedRecord> mapRecord(HcRecord record) {
  final metadata = record.metadata;
  final problem = _metadataProblem(metadata);
  if (problem != null) return _rejected(record, problem);
  final device = _device(metadata.device);
  final method = byWire(
    enums.RecordingMethodEnum.values,
    metadata.recordingMethod,
    (value) => value.value,
    enums.RecordingMethodEnum.unknown,
  );

  switch (record) {
    case HcStepsRecord():
      final problem =
          _intervalProblem(
            record.startMs,
            record.startOffsetS,
            record.endMs,
            record.endOffsetS,
          ) ??
          _rangeProblem('count', record.count, 0, IngestLimits.maxStepsCount);
      if (problem != null) return _rejected(record, problem);
      return Accepted(
        MappedRecord(
          IngestItem.steps(
            api.StepsRecordRequest(
              hcId: metadata.id,
              dataOrigin: metadata.dataOrigin,
              lastModifiedMs: metadata.lastModifiedMs,
              recordingMethod: method,
              device: device,
              startMs: record.startMs,
              startOffsetS: record.startOffsetS,
              endMs: record.endMs,
              endOffsetS: record.endOffsetS,
              count: record.count,
            ),
          ),
          metadata.lastModifiedMs,
        ),
      );
    case HcRestingHeartRateRecord():
      final problem =
          _epochProblem('time_ms', record.timeMs) ??
          _offsetProblem('offset_s', record.offsetS) ??
          _rangeProblem(
            'beats_per_minute',
            record.beatsPerMinute,
            0,
            IngestLimits.maxBeatsPerMinute,
          );
      if (problem != null) return _rejected(record, problem);
      return Accepted(
        MappedRecord(
          IngestItem.restingHeartRate(
            api.RestingHeartRateRecordRequest(
              hcId: metadata.id,
              dataOrigin: metadata.dataOrigin,
              lastModifiedMs: metadata.lastModifiedMs,
              recordingMethod: method,
              device: device,
              timeMs: record.timeMs,
              offsetS: record.offsetS,
              beatsPerMinute: record.beatsPerMinute,
            ),
          ),
          metadata.lastModifiedMs,
        ),
      );
    case HcSleepSessionRecord():
      final stages = [
        for (final stage in record.stages)
          if (stage.endMs > stage.startMs) stage,
      ];
      final problem =
          _intervalProblem(
            record.startMs,
            record.startOffsetS,
            record.endMs,
            record.endOffsetS,
          ) ??
          _textProblem('title', record.title) ??
          _textProblem('notes', record.notes) ??
          (stages.length > IngestLimits.maxSleepStages
              ? 'more than ${IngestLimits.maxSleepStages} stages'
              : null) ??
          (stages.any(
                (stage) =>
                    stage.startMs < record.startMs ||
                    stage.endMs > record.endMs,
              )
              ? 'a stage lies outside the session'
              : null);
      if (problem != null) return _rejected(record, problem);
      return Accepted(
        MappedRecord(
          IngestItem.sleepSession(
            api.SleepSessionRecordRequest(
              hcId: metadata.id,
              dataOrigin: metadata.dataOrigin,
              lastModifiedMs: metadata.lastModifiedMs,
              recordingMethod: method,
              device: device,
              startMs: record.startMs,
              startOffsetS: record.startOffsetS,
              endMs: record.endMs,
              endOffsetS: record.endOffsetS,
              title: record.title,
              notes: record.notes,
              stages: [
                for (final stage in stages)
                  api.SleepStageRequest(
                    startMs: stage.startMs,
                    endMs: stage.endMs,
                    stage: byWire(
                      enums.SleepStageEnum.values,
                      stage.stage,
                      (value) => value.value,
                      enums.SleepStageEnum.unknown,
                    ),
                  ),
              ],
            ),
          ),
          metadata.lastModifiedMs,
        ),
      );
  }
}

/// A deletion as its request type, or the rejection.
Mapped<IngestItem> mapDeletion(String hcId, int observedAtMs) {
  final problem = !_isUuid(hcId)
      ? 'hc_id is not a UUID'
      : _epochProblem('observed_at_ms', observedAtMs);
  if (problem != null) {
    return Refused(IngestRejection(what: 'deletion $hcId', reason: problem));
  }
  return Accepted(
    IngestItem.deletion(
      api.HealthDeletionRequest(hcId: hcId, observedAtMs: observedAtMs),
    ),
  );
}

/// An hourly window as its request type, or the rejection.
Mapped<IngestItem> mapWindow(HcAggregateWindow window) {
  final what =
      'window ${window.metric.wire} ${window.startMs}..${window.endMs}';
  final hours = (window.endMs - window.startMs) ~/ IngestLimits.hourMs;
  String? problem =
      _epochProblem('start_ms', window.startMs) ??
      _epochProblem('end_ms', window.endMs) ??
      _epochProblem('computed_at_ms', window.computedAtMs);
  if (problem == null &&
      (window.startMs % IngestLimits.hourMs != 0 ||
          window.endMs % IngestLimits.hourMs != 0)) {
    problem = 'not on UTC hours';
  }
  if (problem == null && window.endMs <= window.startMs) {
    problem = 'empty window';
  }
  if (problem == null && hours > IngestLimits.maxWindowHours) {
    problem = 'longer than ${IngestLimits.maxWindowHours} hours';
  }
  final seen = <int>{};
  for (final bucket in window.buckets) {
    if (problem != null) break;
    if (bucket.startMs % IngestLimits.hourMs != 0 ||
        bucket.startMs < window.startMs ||
        bucket.startMs >= window.endMs ||
        !seen.add(bucket.startMs)) {
      problem = 'bucket ${bucket.startMs} is not a distinct hour inside';
    } else if (bucket.value < 0 ||
        bucket.value > IngestLimits.maxAggregateValue) {
      problem = 'bucket value ${bucket.value} out of range';
    } else if (bucket.dataOrigins.length > IngestLimits.maxDataOrigins ||
        bucket.dataOrigins.any(
          (origin) =>
              origin.isEmpty ||
              origin.runes.length > IngestLimits.maxStringLength,
        )) {
      problem = 'bucket data origins out of bounds';
    }
  }
  if (problem != null) {
    return Refused(IngestRejection(what: what, reason: problem));
  }

  final metric = byWire(
    enums.HealthAggregateMetricEnum.values,
    window.metric.wire,
    (value) => value.value,
    enums.HealthAggregateMetricEnum.swaggerGeneratedUnknown,
  );
  if (metric == enums.HealthAggregateMetricEnum.swaggerGeneratedUnknown) {
    return Refused(
      IngestRejection(what: what, reason: 'metric unknown to the contract'),
    );
  }
  return Accepted(
    IngestItem.window(
      api.HealthAggregateWindowRequest(
        metric: metric,
        startMs: window.startMs,
        endMs: window.endMs,
        computedAtMs: window.computedAtMs,
        buckets: [
          for (final bucket in window.buckets)
            api.HealthAggregateBucketRequest(
              startMs: bucket.startMs,
              value: bucket.value,
              dataOrigins: bucket.dataOrigins,
            ),
        ],
      ),
    ),
  );
}

/// The value of [values] whose wire name is [name], or [fallback]. A name the
/// generated enum lacks (a newer HC constant the bridge passed through) lands
/// on the contract's `unknown` rather than on the generator's null-valued
/// placeholder, which would serialize as a refused null.
T byWire<T>(
  List<T> values,
  String name,
  String? Function(T value) wire,
  T fallback,
) {
  for (final value in values) {
    if (wire(value) == name) return value;
  }
  return fallback;
}

api.HealthDeviceRequest? _device(HcDevice? device) => device == null
    ? null
    : api.HealthDeviceRequest(
        type: byWire(
          enums.HealthDeviceTypeEnum.values,
          device.type,
          (value) => value.value,
          enums.HealthDeviceTypeEnum.unknown,
        ),
        manufacturer: device.manufacturer,
        model: device.model,
      );

Refused<MappedRecord> _rejected(HcRecord record, String reason) => Refused(
  IngestRejection(
    what: '${record.type.wire} ${record.metadata.id}',
    reason: reason,
  ),
);

final RegExp _uuidPattern = RegExp(
  r'^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32})$',
);

bool _isUuid(String value) => _uuidPattern.hasMatch(value);

String? _metadataProblem(HcMetadata metadata) {
  if (!_isUuid(metadata.id)) return 'hc_id is not a UUID';
  if (metadata.dataOrigin.isEmpty ||
      metadata.dataOrigin.runes.length > IngestLimits.maxStringLength) {
    return 'data_origin is empty or too long';
  }
  final device = metadata.device;
  if (device != null &&
      ((device.manufacturer?.runes.length ?? 0) >
              IngestLimits.maxStringLength ||
          (device.model?.runes.length ?? 0) > IngestLimits.maxStringLength)) {
    return 'device strings are too long';
  }
  return _epochProblem('last_modified_ms', metadata.lastModifiedMs);
}

String? _intervalProblem(
  int startMs,
  int? startOffsetS,
  int endMs,
  int? endOffsetS,
) =>
    _epochProblem('start_ms', startMs) ??
    _epochProblem('end_ms', endMs) ??
    _offsetProblem('start_offset_s', startOffsetS) ??
    _offsetProblem('end_offset_s', endOffsetS) ??
    (endMs <= startMs ? 'end_ms is not after start_ms' : null);

String? _epochProblem(String field, int value) =>
    _rangeProblem(field, value, 0, IngestLimits.maxEpochMs);

String? _offsetProblem(String field, int? value) => value == null
    ? null
    : _rangeProblem(
        field,
        value,
        -IngestLimits.maxZoneOffsetS,
        IngestLimits.maxZoneOffsetS,
      );

String? _rangeProblem(String field, int value, int min, int max) =>
    value < min || value > max ? '$field $value is outside $min..$max' : null;

String? _textProblem(String field, String? value) =>
    (value?.runes.length ?? 0) > IngestLimits.maxTextLength
    ? '$field is longer than ${IngestLimits.maxTextLength} characters'
    : null;
