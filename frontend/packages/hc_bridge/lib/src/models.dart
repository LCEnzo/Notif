import 'package:hc_bridge/src/errors.dart';

const String _read = 'android.permission.health.READ_';

/// The record types Notif uploads. The wire names are the ingest contract's
/// list keys.
enum HcRecordType {
  steps(HcDataType.steps),
  restingHeartRate(HcDataType.restingHeartRate),
  sleepSession(HcDataType.sleepSession);

  const HcRecordType(this.dataType);

  final HcDataType dataType;

  String get wire => dataType.wire;
  String get readPermission => dataType.readPermission;
}

/// The hourly aggregates Notif uploads; wire names are the contract's
/// `metric` values.
enum HcAggregateMetric {
  stepsCountTotal('steps_count_total', HcRecordType.steps),
  sleepDurationTotal('sleep_duration_total', HcRecordType.sleepSession);

  const HcAggregateMetric(this.wire, this.recordType);

  final String wire;
  final HcRecordType recordType;
}

/// Health Connect features the app gates on; wire names are the bridge's.
enum HcFeature {
  history('history'),
  background('background'),
  skinTemperature('skin_temperature'),
  plannedExercise('planned_exercise'),
  mindfulness('mindfulness');

  const HcFeature(this.wire);

  final String wire;
}

/// Every HC record type Notif may read, exercise routes aside (they have
/// their own consent flow). Wire names match the bridge's `ProbeKind`; the
/// second value is the `READ_*` permission's suffix.
enum HcDataType {
  activeCaloriesBurned('active_calories_burned', 'ACTIVE_CALORIES_BURNED'),
  basalBodyTemperature('basal_body_temperature', 'BASAL_BODY_TEMPERATURE'),
  basalMetabolicRate('basal_metabolic_rate', 'BASAL_METABOLIC_RATE'),
  bloodGlucose('blood_glucose', 'BLOOD_GLUCOSE'),
  bloodPressure('blood_pressure', 'BLOOD_PRESSURE'),
  bodyFat('body_fat', 'BODY_FAT'),
  bodyTemperature('body_temperature', 'BODY_TEMPERATURE'),
  bodyWaterMass('body_water_mass', 'BODY_WATER_MASS'),
  boneMass('bone_mass', 'BONE_MASS'),
  cervicalMucus('cervical_mucus', 'CERVICAL_MUCUS'),
  cyclingPedalingCadence('cycling_pedaling_cadence', 'EXERCISE'),
  distance('distance', 'DISTANCE'),
  elevationGained('elevation_gained', 'ELEVATION_GAINED'),
  exerciseSession('exercise_session', 'EXERCISE'),
  floorsClimbed('floors_climbed', 'FLOORS_CLIMBED'),
  heartRate('heart_rate', 'HEART_RATE'),
  heartRateVariabilityRmssd(
    'heart_rate_variability_rmssd',
    'HEART_RATE_VARIABILITY',
  ),
  height('height', 'HEIGHT'),
  hydration('hydration', 'HYDRATION'),
  intermenstrualBleeding('intermenstrual_bleeding', 'INTERMENSTRUAL_BLEEDING'),
  leanBodyMass('lean_body_mass', 'LEAN_BODY_MASS'),
  menstruationFlow('menstruation_flow', 'MENSTRUATION'),
  menstruationPeriod('menstruation_period', 'MENSTRUATION'),
  mindfulnessSession(
    'mindfulness_session',
    'MINDFULNESS',
    HcFeature.mindfulness,
  ),
  nutrition('nutrition', 'NUTRITION'),
  ovulationTest('ovulation_test', 'OVULATION_TEST'),
  oxygenSaturation('oxygen_saturation', 'OXYGEN_SATURATION'),
  plannedExerciseSession(
    'planned_exercise_session',
    'PLANNED_EXERCISE',
    HcFeature.plannedExercise,
  ),
  power('power', 'POWER'),
  respiratoryRate('respiratory_rate', 'RESPIRATORY_RATE'),
  restingHeartRate('resting_heart_rate', 'RESTING_HEART_RATE'),
  sexualActivity('sexual_activity', 'SEXUAL_ACTIVITY'),
  skinTemperature(
    'skin_temperature',
    'SKIN_TEMPERATURE',
    HcFeature.skinTemperature,
  ),
  sleepSession('sleep_session', 'SLEEP'),
  speed('speed', 'SPEED'),
  steps('steps', 'STEPS'),
  stepsCadence('steps_cadence', 'STEPS'),
  totalCaloriesBurned('total_calories_burned', 'TOTAL_CALORIES_BURNED'),
  vo2Max('vo2_max', 'VO2_MAX'),
  weight('weight', 'WEIGHT'),
  wheelchairPushes('wheelchair_pushes', 'WHEELCHAIR_PUSHES');

  const HcDataType(this.wire, String permission, [this.feature])
    : readPermission = '$_read$permission';

  final String wire;
  final String readPermission;

  /// The HC feature the type needs, if any.
  final HcFeature? feature;
}

abstract final class HcPermissions {
  static const String readSteps = '${_read}STEPS';
  static const String readRestingHeartRate = '${_read}RESTING_HEART_RATE';
  static const String readSleep = '${_read}SLEEP';
  static const String readHistory = '${_read}HEALTH_DATA_HISTORY';
  static const String readInBackground = '${_read}HEALTH_DATA_IN_BACKGROUND';

  /// Every data-type read permission.
  static final Set<String> dataReads = {
    for (final type in HcDataType.values) type.readPermission,
  };

  /// Everything Notif asks for, in one sheet, minus what this Health Connect
  /// cannot grant.
  static Set<String> requestable(HcStatus status) => {
    for (final type in HcDataType.values)
      if (type.feature == null || status.supports(type.feature!))
        type.readPermission,
    if (status.supports(HcFeature.history)) readHistory,
    if (status.supports(HcFeature.background)) readInBackground,
  };
}

enum HcSdkStatus {
  available('available'),
  unavailable('unavailable'),
  updateRequired('update_required');

  const HcSdkStatus(this.wire);

  final String wire;
}

class HcStatus {
  const HcStatus({
    required this.sdk,
    required this.features,
    required this.grantedPermissions,
  });

  factory HcStatus.decode(Object? raw) {
    final map = _WireMap.of(raw, 'status');
    final features = _WireMap.of(map.raw('features'), 'status.features');
    return HcStatus(
      sdk: map.enumValue('sdk', HcSdkStatus.values, (s) => s.wire),
      features: {
        for (final feature in HcFeature.values)
          if (features.optionalString(feature.wire) == 'available') feature,
      },
      grantedPermissions: map.stringList('granted').toSet(),
    );
  }

  final HcSdkStatus sdk;

  /// The features this Health Connect offers.
  final Set<HcFeature> features;
  final Set<String> grantedPermissions;

  bool get available => sdk == HcSdkStatus.available;
  bool supports(HcFeature feature) => features.contains(feature);
  bool get historyGranted =>
      grantedPermissions.contains(HcPermissions.readHistory);
  bool get backgroundGranted =>
      grantedPermissions.contains(HcPermissions.readInBackground);

  /// Whether any data type is readable; HC anchors its 30-day window then.
  bool get anyDataReadable =>
      grantedPermissions.any(HcPermissions.dataReads.contains);

  /// The data types whose read permission is granted, in enum order.
  List<HcDataType> get readableDataTypes => [
    for (final type in HcDataType.values)
      if (grantedPermissions.contains(type.readPermission)) type,
  ];

  /// The uploaded record types whose read permission is granted.
  List<HcRecordType> get readableTypes => [
    for (final type in HcRecordType.values)
      if (grantedPermissions.contains(type.readPermission)) type,
  ];
}

class HcDevice {
  const HcDevice({required this.type, this.manufacturer, this.model});

  /// HC's `Device.TYPE_*` as a name; `unknown` for a constant the bridge does
  /// not know.
  final String type;
  final String? manufacturer;
  final String? model;
}

class HcMetadata {
  const HcMetadata({
    required this.id,
    required this.dataOrigin,
    required this.lastModifiedMs,
    required this.recordingMethod,
    this.device,
  });

  final String id;
  final String dataOrigin;
  final int lastModifiedMs;

  /// HC's `RECORDING_METHOD_*` as a name; `unknown` for an unknown constant.
  final String recordingMethod;
  final HcDevice? device;
}

sealed class HcRecord {
  const HcRecord(this.metadata);

  factory HcRecord.decode(Object? raw) {
    final map = _WireMap.of(raw, 'record');
    final type = map.enumValue('type', HcRecordType.values, (t) => t.wire);
    final deviceRaw = map.raw('device');
    final deviceMap = deviceRaw == null
        ? null
        : _WireMap.of(deviceRaw, 'record.device');
    final metadata = HcMetadata(
      id: map.string('id'),
      dataOrigin: map.string('data_origin'),
      lastModifiedMs: map.integer('last_modified_ms'),
      recordingMethod: map.string('recording_method'),
      device: deviceMap == null
          ? null
          : HcDevice(
              type: deviceMap.string('type'),
              manufacturer: deviceMap.optionalString('manufacturer'),
              model: deviceMap.optionalString('model'),
            ),
    );
    return switch (type) {
      HcRecordType.steps => HcStepsRecord(
        metadata: metadata,
        startMs: map.integer('start_ms'),
        startOffsetS: map.optionalInteger('start_offset_s'),
        endMs: map.integer('end_ms'),
        endOffsetS: map.optionalInteger('end_offset_s'),
        count: map.integer('count'),
      ),
      HcRecordType.restingHeartRate => HcRestingHeartRateRecord(
        metadata: metadata,
        timeMs: map.integer('time_ms'),
        offsetS: map.optionalInteger('offset_s'),
        beatsPerMinute: map.integer('beats_per_minute'),
      ),
      HcRecordType.sleepSession => HcSleepSessionRecord(
        metadata: metadata,
        startMs: map.integer('start_ms'),
        startOffsetS: map.optionalInteger('start_offset_s'),
        endMs: map.integer('end_ms'),
        endOffsetS: map.optionalInteger('end_offset_s'),
        title: map.optionalString('title'),
        notes: map.optionalString('notes'),
        stages: [
          for (final stage in map.list('stages'))
            HcSleepStage._decode(_WireMap.of(stage, 'record.stages[]')),
        ],
      ),
    };
  }

  final HcMetadata metadata;

  HcRecordType get type;
}

class HcStepsRecord extends HcRecord {
  const HcStepsRecord({
    required HcMetadata metadata,
    required this.startMs,
    required this.endMs,
    required this.count,
    this.startOffsetS,
    this.endOffsetS,
  }) : super(metadata);

  final int startMs;
  final int? startOffsetS;
  final int endMs;
  final int? endOffsetS;
  final int count;

  @override
  HcRecordType get type => HcRecordType.steps;
}

class HcRestingHeartRateRecord extends HcRecord {
  const HcRestingHeartRateRecord({
    required HcMetadata metadata,
    required this.timeMs,
    required this.beatsPerMinute,
    this.offsetS,
  }) : super(metadata);

  final int timeMs;
  final int? offsetS;
  final int beatsPerMinute;

  @override
  HcRecordType get type => HcRecordType.restingHeartRate;
}

class HcSleepStage {
  const HcSleepStage({
    required this.startMs,
    required this.endMs,
    required this.stage,
  });

  factory HcSleepStage._decode(_WireMap map) => HcSleepStage(
    startMs: map.integer('start_ms'),
    endMs: map.integer('end_ms'),
    stage: map.string('stage'),
  );

  final int startMs;
  final int endMs;

  /// HC's `STAGE_TYPE_*` as a name; `unknown` for an unknown constant.
  final String stage;
}

class HcSleepSessionRecord extends HcRecord {
  const HcSleepSessionRecord({
    required HcMetadata metadata,
    required this.startMs,
    required this.endMs,
    required this.stages,
    this.startOffsetS,
    this.endOffsetS,
    this.title,
    this.notes,
  }) : super(metadata);

  final int startMs;
  final int? startOffsetS;
  final int endMs;
  final int? endOffsetS;
  final String? title;
  final String? notes;
  final List<HcSleepStage> stages;

  @override
  HcRecordType get type => HcRecordType.sleepSession;
}

class HcRecordPage {
  const HcRecordPage({required this.records, this.nextPageToken});

  factory HcRecordPage.decode(Object? raw) {
    final map = _WireMap.of(raw, 'readRecords');
    return HcRecordPage(
      records: [
        for (final record in map.list('records')) HcRecord.decode(record),
      ],
      nextPageToken: map.optionalString('next_page_token'),
    );
  }

  final List<HcRecord> records;
  final String? nextPageToken;
}

class HcAggregateBucket {
  const HcAggregateBucket({
    required this.startMs,
    required this.endMs,
    required this.value,
    required this.dataOrigins,
  });

  final int startMs;
  final int endMs;

  /// Steps, or milliseconds of sleep.
  final int value;
  final List<String> dataOrigins;
}

/// One `aggregateGroupByDuration` answer over whole hours. Hours without data
/// have no bucket: HC omits them.
class HcAggregateWindow {
  const HcAggregateWindow({
    required this.metric,
    required this.startMs,
    required this.endMs,
    required this.computedAtMs,
    required this.buckets,
  });

  factory HcAggregateWindow.decode(Object? raw) {
    final map = _WireMap.of(raw, 'aggregateHourly');
    return HcAggregateWindow(
      metric: map.enumValue('metric', HcAggregateMetric.values, (m) => m.wire),
      startMs: map.integer('start_ms'),
      endMs: map.integer('end_ms'),
      computedAtMs: map.integer('computed_at_ms'),
      buckets: [
        for (final bucket in map.list('buckets'))
          _decodeBucket(_WireMap.of(bucket, 'aggregateHourly.buckets[]')),
      ],
    );
  }

  final HcAggregateMetric metric;
  final int startMs;
  final int endMs;
  final int computedAtMs;
  final List<HcAggregateBucket> buckets;

  static HcAggregateBucket _decodeBucket(_WireMap map) => HcAggregateBucket(
    startMs: map.integer('start_ms'),
    endMs: map.integer('end_ms'),
    value: map.integer('value'),
    dataOrigins: map.stringList('data_origins'),
  );
}

sealed class HcChange {
  const HcChange();
}

class HcUpsertion extends HcChange {
  const HcUpsertion(this.record);

  final HcRecord record;
}

class HcDeletion extends HcChange {
  const HcDeletion(this.id);

  final String id;
}

/// One `getChanges` page. [changes] is in an order where "the last change per
/// id wins" is correct: the bridge normalizes Android 14's
/// upserts-then-deletions page layout.
class HcChangesPage {
  const HcChangesPage({
    required this.changes,
    required this.nextToken,
    required this.hasMore,
    required this.tokenExpired,
    required this.observedAtMs,
    required this.skippedUnsupported,
  });

  factory HcChangesPage.decode(Object? raw) {
    final map = _WireMap.of(raw, 'changes');
    return HcChangesPage(
      changes: [
        for (final change in map.list('changes'))
          _decodeChange(_WireMap.of(change, 'changes.changes[]')),
      ],
      nextToken: map.string('next_token'),
      hasMore: map.boolean('has_more'),
      tokenExpired: map.boolean('token_expired'),
      observedAtMs: map.integer('observed_at_ms'),
      skippedUnsupported: map.integer('skipped_unsupported'),
    );
  }

  final List<HcChange> changes;
  final String nextToken;
  final bool hasMore;
  final bool tokenExpired;

  /// Read on the phone's clock just before `getChanges` ran: a version written
  /// after it cannot be one this page's deletions refer to.
  final int observedAtMs;

  /// Upserts of record types the token does not cover; zero in practice.
  final int skippedUnsupported;

  static HcChange _decodeChange(_WireMap map) {
    final kind = map.string('kind');
    return switch (kind) {
      'upsert' => HcUpsertion(HcRecord.decode(map.raw('record'))),
      'deletion' => HcDeletion(map.string('id')),
      _ => throw map.malformed('kind', 'unknown change kind "$kind"'),
    };
  }
}

/// One data type's answer from the coverage probe.
class HcTypeCoverage {
  const HcTypeCoverage({
    required this.type,
    required this.byAggregate,
    required this.count,
    this.capped = false,
    this.firstMonth,
    this.lastMonth,
  });

  final HcDataType type;

  /// True: [count] is months with data, from monthly aggregates. False: it
  /// is records, read in bounded pages.
  final bool byAggregate;
  final int count;

  /// The record count stopped at the page bound; the true count is higher.
  final bool capped;

  /// `YYYY-MM`, local; aggregate path only.
  final String? firstMonth;
  final String? lastMonth;

  bool get hasData => count > 0;
}

class HcCoverage {
  const HcCoverage({required this.computedAtMs, required this.types});

  factory HcCoverage.decode(Object? raw) {
    final map = _WireMap.of(raw, 'coverageProbe');
    return HcCoverage(
      computedAtMs: map.integer('computed_at_ms'),
      types: [
        for (final entry in map.list('types'))
          _decodeType(_WireMap.of(entry, 'coverageProbe.types[]')),
      ],
    );
  }

  final int computedAtMs;
  final List<HcTypeCoverage> types;

  static HcTypeCoverage _decodeType(_WireMap map) {
    final type = map.enumValue('type', HcDataType.values, (t) => t.wire);
    return switch (map.string('method')) {
      'aggregate' => HcTypeCoverage(
        type: type,
        byAggregate: true,
        count: map.integer('months'),
        firstMonth: map.optionalString('first_month'),
        lastMonth: map.optionalString('last_month'),
      ),
      'records' => HcTypeCoverage(
        type: type,
        byAggregate: false,
        count: map.integer('records'),
        capped: map.boolean('capped'),
      ),
      final other => throw map.malformed('method', 'unknown "$other"'),
    };
  }
}

/// Strict reads from a platform-channel map: a missing or mistyped field is a
/// [HcErrorCode.malformedResponse], never a silent null.
class _WireMap {
  _WireMap._(this._map, this._context);

  factory _WireMap.of(Object? raw, String context) {
    if (raw is Map<Object?, Object?>) return _WireMap._(raw, context);
    throw HcBridgeException(
      HcErrorCode.malformedResponse,
      'expected a map but got ${raw.runtimeType}',
      operation: context,
    );
  }

  final Map<Object?, Object?> _map;
  final String _context;

  HcBridgeException malformed(String key, String detail) => HcBridgeException(
    HcErrorCode.malformedResponse,
    '$key: $detail',
    operation: _context,
  );

  Object? raw(String key) => _map[key];

  T _required<T>(String key) {
    final value = _map[key];
    if (value is T) return value;
    throw malformed(key, 'expected $T but got ${value.runtimeType}');
  }

  String string(String key) => _required<String>(key);

  int integer(String key) => _required<int>(key);

  bool boolean(String key) => _required<bool>(key);

  List<Object?> list(String key) => _required<List<Object?>>(key);

  String? optionalString(String key) => _map[key] == null ? null : string(key);

  int? optionalInteger(String key) => _map[key] == null ? null : integer(key);

  List<String> stringList(String key) => [
    for (final item in list(key))
      item is String ? item : throw malformed(key, 'non-string item'),
  ];

  T enumValue<T>(String key, List<T> values, String Function(T) wire) {
    final name = string(key);
    for (final value in values) {
      if (wire(value) == name) return value;
    }
    throw malformed(key, 'unknown value "$name"');
  }
}
