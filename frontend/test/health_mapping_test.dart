import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_bridge/hc_bridge.dart';
import 'package:notif/services/health/ingest_items.dart';

import 'support/fake_hc_bridge.dart';

const int _hour = 3600000;
const int _base = 1790000000000 - 1790000000000 % _hour;

Map<String, dynamic> _json(IngestItem item) =>
    jsonDecode(item.encoded) as Map<String, dynamic>;

IngestItem _accepted(Mapped<Object> mapped) => switch (mapped) {
  Accepted(:final value) =>
    value is MappedRecord ? value.item : value as IngestItem,
  Refused(:final rejection) => fail('refused: $rejection'),
};

String _refusal(Mapped<Object> mapped) => switch (mapped) {
  Accepted() => fail('accepted'),
  Refused(:final rejection) => rejection.reason,
};

HcSleepSessionRecord _sleep({
  List<HcSleepStage> stages = const [],
  String? title,
  HcDevice? device,
  String recordingMethod = 'manual_entry',
}) => HcSleepSessionRecord(
  metadata: HcMetadata(
    id: uuid(9),
    dataOrigin: 'com.example.sleep',
    lastModifiedMs: 5000,
    recordingMethod: recordingMethod,
    device: device,
  ),
  startMs: _base,
  startOffsetS: 3600,
  endMs: _base + 8 * _hour,
  endOffsetS: 3600,
  title: title,
  stages: stages,
);

void main() {
  test('steps map field for field onto the contract', () {
    final item = _accepted(
      mapRecord(stepsRecord(1, startMs: _base, count: 42)),
    );

    expect(item.list, IngestList.steps);
    expect(_json(item), {
      'hc_id': uuid(1),
      'data_origin': 'com.example.fit',
      'last_modified_ms': 1000,
      'recording_method': 'automatically_recorded',
      'device': null,
      'start_ms': _base,
      'start_offset_s': 7200,
      'end_ms': _base + 60000,
      'end_offset_s': 7200,
      'count': 42,
    });
  });

  test('resting heart rate keeps a null offset', () {
    final item = _accepted(
      mapRecord(
        HcRestingHeartRateRecord(
          metadata: metadata(2),
          timeMs: _base,
          beatsPerMinute: 51,
        ),
      ),
    );
    expect(_json(item), containsPair('offset_s', null));
    expect(_json(item), containsPair('beats_per_minute', 51));
    expect(item.list, IngestList.restingHeartRate);
  });

  test(
    'names the bridge passed through but the contract lacks map to unknown',
    () {
      final item = _accepted(
        mapRecord(
          _sleep(
            recordingMethod: 'telepathy',
            device: const HcDevice(
              type: 'implant',
              manufacturer: '',
              model: 'X',
            ),
            stages: const [
              HcSleepStage(
                startMs: _base,
                endMs: _base + _hour,
                stage: 'lucid',
              ),
              HcSleepStage(
                startMs: _base + _hour,
                endMs: _base + 2 * _hour,
                stage: 'rem',
              ),
            ],
          ),
        ),
      );
      final json = _json(item);
      expect(json['recording_method'], 'unknown');
      expect(json['device'], {
        'type': 'unknown',
        'manufacturer': '',
        'model': 'X',
      });
      expect(
        (json['stages'] as List<dynamic>).map(
          (stage) => (stage as Map)['stage'],
        ),
        ['unknown', 'rem'],
      );
    },
  );

  test('a stage shorter than a millisecond is dropped, the session kept', () {
    final item = _accepted(
      mapRecord(
        _sleep(
          stages: const [
            HcSleepStage(startMs: _base, endMs: _base, stage: 'awake'),
            HcSleepStage(startMs: _base, endMs: _base + _hour, stage: 'deep'),
          ],
        ),
      ),
    );
    expect(_json(item)['stages'], hasLength(1));
  });

  test('records the contract would refuse are refused, with a reason', () {
    final cases = <String, HcRecord>{
      'hc_id is not a UUID': const HcStepsRecord(
        metadata: HcMetadata(
          id: 'testHCid0',
          dataOrigin: 'a',
          lastModifiedMs: 1,
          recordingMethod: 'unknown',
        ),
        startMs: _base,
        endMs: _base + 1,
        count: 1,
      ),
      'end_ms is not after start_ms': HcStepsRecord(
        metadata: metadata(1),
        startMs: _base,
        endMs: _base,
        count: 1,
      ),
      'count': HcStepsRecord(
        metadata: metadata(1),
        startMs: _base,
        endMs: _base + 1,
        count: 10000001,
      ),
      'start_offset_s': HcStepsRecord(
        metadata: metadata(1),
        startMs: _base,
        startOffsetS: 64801,
        endMs: _base + 1,
        count: 1,
      ),
      'beats_per_minute': HcRestingHeartRateRecord(
        metadata: metadata(1),
        timeMs: _base,
        beatsPerMinute: 1001,
      ),
      'title': _sleep(title: 'ž' * 10001),
      'outside the session': _sleep(
        stages: const [
          HcSleepStage(
            startMs: _base - 1,
            endMs: _base + _hour,
            stage: 'light',
          ),
        ],
      ),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(_refusal(mapRecord(value)), contains(key), reason: key);
    }
  });

  test('the bounds themselves are accepted', () {
    _accepted(
      mapRecord(
        HcStepsRecord(
          metadata: metadata(1),
          startMs: 0,
          startOffsetS: -64800,
          endMs: IngestLimits.maxEpochMs,
          endOffsetS: 64800,
          count: 10000000,
        ),
      ),
    );
    _accepted(mapRecord(_sleep(title: 'ž' * 10000)));
  });

  test('windows map on whole hours and refuse anything else', () {
    HcAggregateWindow window({
      int start = _base,
      int hours = 3,
      List<HcAggregateBucket> buckets = const [],
    }) => HcAggregateWindow(
      metric: HcAggregateMetric.sleepDurationTotal,
      startMs: start,
      endMs: start + hours * _hour,
      computedAtMs: start + hours * _hour,
      buckets: buckets,
    );
    HcAggregateBucket bucket(int start, {int value = 1}) => HcAggregateBucket(
      startMs: start,
      endMs: start + _hour,
      value: value,
      dataOrigins: const ['a'],
    );

    final item = _accepted(mapWindow(window(buckets: [bucket(_base + _hour)])));
    expect(item.cost, 3);
    expect(_json(item), {
      'metric': 'sleep_duration_total',
      'start_ms': _base,
      'end_ms': _base + 3 * _hour,
      'computed_at_ms': _base + 3 * _hour,
      'buckets': [
        {
          'start_ms': _base + _hour,
          'value': 1,
          'data_origins': ['a'],
        },
      ],
    });

    expect(_refusal(mapWindow(window(start: _base + 1))), contains('hours'));
    expect(_refusal(mapWindow(window(hours: 745))), contains('744'));
    _accepted(mapWindow(window(hours: 744)));
    expect(
      _refusal(mapWindow(window(buckets: [bucket(_base + 3 * _hour)]))),
      contains('inside'),
    );
    expect(
      _refusal(mapWindow(window(buckets: [bucket(_base), bucket(_base)]))),
      contains('distinct'),
    );
    expect(
      _refusal(mapWindow(window(buckets: [bucket(_base, value: -1)]))),
      contains('range'),
    );
  });

  test('deletions need a UUID', () {
    expect(_json(_accepted(mapDeletion(uuid(3), 99))), {
      'hc_id': uuid(3),
      'observed_at_ms': 99,
    });
    expect(_refusal(mapDeletion('nope', 99)), contains('UUID'));
  });
}
