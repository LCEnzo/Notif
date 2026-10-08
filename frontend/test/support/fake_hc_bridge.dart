import 'package:hc_bridge/hc_bridge.dart';

const int testHourMs = 3600000;
const int testDayMs = 86400000;

/// A canonical UUID per [n], as HC ids are.
String uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

HcMetadata metadata(int n, {int lastModifiedMs = 1000}) => HcMetadata(
  id: uuid(n),
  dataOrigin: 'com.example.fit',
  lastModifiedMs: lastModifiedMs,
  recordingMethod: 'automatically_recorded',
);

HcStepsRecord stepsRecord(
  int n, {
  required int startMs,
  int count = 10,
  int lastModifiedMs = 1000,
}) => HcStepsRecord(
  metadata: metadata(n, lastModifiedMs: lastModifiedMs),
  startMs: startMs,
  startOffsetS: 7200,
  endMs: startMs + 60000,
  endOffsetS: 7200,
  count: count,
);

/// Every permission Notif can ask for on a Health Connect with every feature.
final Set<String> everyPermission = {
  ...HcPermissions.dataReads,
  HcPermissions.readHistory,
  HcPermissions.readInBackground,
};

final HcStatus grantedEverything = grantedWithout(const {});

HcStatus grantedWithout(Set<String> missing) => HcStatus(
  sdk: HcSdkStatus.available,
  features: HcFeature.values.toSet(),
  grantedPermissions: everyPermission.difference(missing),
);

/// Granted reads of exactly the three uploaded types, plus [extra].
HcStatus grantedOnly(Set<String> extra) => HcStatus(
  sdk: HcSdkStatus.available,
  features: HcFeature.values.toSet(),
  grantedPermissions: {
    HcPermissions.readSteps,
    HcPermissions.readRestingHeartRate,
    HcPermissions.readSleep,
    ...extra,
  },
);

/// An in-memory Health Connect. Records are served by type and time range,
/// changes pages from a queue, and every call is recorded.
class FakeHcBridge implements HcBridge {
  FakeHcBridge({HcStatus? currentStatus})
    : currentStatus = currentStatus ?? grantedEverything;

  HcStatus currentStatus;
  final Map<HcRecordType, List<HcRecord>> records = {};
  final List<Object> changesQueue = [];
  HcCoverage coverage = const HcCoverage(computedAtMs: 0, types: []);
  final List<Set<HcDataType>> probed = [];
  int pageSize = 1000;
  int tokensIssued = 0;

  /// Hourly buckets to answer for each metric, by bucket start.
  final Map<HcAggregateMetric, Map<int, int>> buckets = {};

  final List<({HcRecordType type, int startMs, int endMs})> reads = [];
  final List<({HcAggregateMetric metric, int startMs, int endMs})> aggregates =
      [];
  final List<String> changesCalls = [];

  /// Every call in order, e.g. `status`, `token`, `read steps`, `changes t`.
  final List<String> log = [];
  final List<Set<String>> permissionRequests = [];
  Set<String>? grantOnRequest;

  @override
  Future<HcStatus> status() async {
    log.add('status');
    return currentStatus;
  }

  bool batteryExempt = false;
  int batteryExemptionRequests = 0;

  @override
  Future<bool> batteryOptimizationExempt() async => batteryExempt;

  @override
  Future<void> requestBatteryOptimizationExemption() async =>
      batteryExemptionRequests++;

  @override
  Future<Set<String>> requestPermissions(Set<String> permissions) async {
    permissionRequests.add(permissions);
    final grant = grantOnRequest ?? permissions;
    currentStatus = HcStatus(
      sdk: currentStatus.sdk,
      features: currentStatus.features,
      grantedPermissions: {...currentStatus.grantedPermissions, ...grant},
    );
    return grant;
  }

  @override
  Future<HcRecordPage> readRecords(
    HcRecordType type, {
    required int startMs,
    required int endMs,
    String? pageToken,
    int pageSize = 1000,
  }) async {
    if (pageToken == null) {
      reads.add((type: type, startMs: startMs, endMs: endMs));
    }
    log.add('read ${type.wire} $startMs..$endMs ${pageToken ?? ''}');
    final matching = [
      for (final record in records[type] ?? const <HcRecord>[])
        if (_startOf(record) >= startMs && _startOf(record) < endMs) record,
    ];
    final offset = int.parse(pageToken ?? '0');
    final size = this.pageSize;
    final page = matching.skip(offset).take(size).toList();
    final next = offset + size < matching.length ? '${offset + size}' : null;
    return HcRecordPage(records: page, nextPageToken: next);
  }

  @override
  Future<HcAggregateWindow> aggregateHourly(
    HcAggregateMetric metric, {
    required int startMs,
    required int endMs,
  }) async {
    aggregates.add((metric: metric, startMs: startMs, endMs: endMs));
    log.add('aggregate ${metric.wire} $startMs..$endMs');
    return HcAggregateWindow(
      metric: metric,
      startMs: startMs,
      endMs: endMs,
      computedAtMs: endMs,
      buckets: [
        for (final MapEntry(:key, :value)
            in (buckets[metric] ?? const <int, int>{}).entries)
          if (key >= startMs && key < endMs)
            HcAggregateBucket(
              startMs: key,
              endMs: key + testHourMs,
              value: value,
              dataOrigins: const ['com.example.fit'],
            ),
      ],
    );
  }

  @override
  Future<String> changesToken(Set<HcRecordType> types) async {
    log.add('token');
    return 'token-${++tokensIssued}';
  }

  /// Each queued entry is an [HcChangesPage] or an [HcBridgeException].
  @override
  Future<HcChangesPage> changes(String token) async {
    changesCalls.add(token);
    log.add('changes $token');
    if (changesQueue.isEmpty) {
      return HcChangesPage(
        changes: const [],
        nextToken: '$token+',
        hasMore: false,
        tokenExpired: false,
        observedAtMs: 0,
        skippedUnsupported: 0,
      );
    }
    final next = changesQueue.removeAt(0);
    if (next is HcBridgeException) throw next;
    return next as HcChangesPage;
  }

  @override
  Future<HcCoverage> coverageProbe(Set<HcDataType> types) async {
    log.add('coverage');
    probed.add(types);
    return coverage;
  }

  static int _startOf(HcRecord record) => switch (record) {
    HcStepsRecord(:final startMs) => startMs,
    HcRestingHeartRateRecord(:final timeMs) => timeMs,
    HcSleepSessionRecord(:final startMs) => startMs,
  };
}
