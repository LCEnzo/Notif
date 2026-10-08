import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:notif/generated/openapi.enums.swagger.dart' as enums;
import 'package:notif/generated/openapi.swagger.dart' as api;
import 'package:notif/services/health/batching.dart';
import 'package:notif/services/health/ingest_items.dart';

import 'support/fake_hc_bridge.dart';

const int _hour = 3600000;
const int _baseMs = 1790000000000 - 1790000000000 % _hour;

IngestItem _steps(int n, {String? title}) => IngestItem.steps(
  api.StepsRecordRequest(
    hcId: uuid(n),
    // Varying the origin varies the encoded size, multibyte included.
    dataOrigin: title ?? 'com.example.fit',
    lastModifiedMs: 1000 + n,
    recordingMethod: enums.RecordingMethodEnum.automaticallyRecorded,
    startMs: _baseMs + n * 60000,
    startOffsetS: 3600,
    endMs: _baseMs + n * 60000 + 60000,
    endOffsetS: 3600,
    count: n,
  ),
);

IngestItem _sleep(int n, String notes, int stages) => IngestItem.sleepSession(
  api.SleepSessionRecordRequest(
    hcId: uuid(n),
    dataOrigin: 'com.example.sleep',
    lastModifiedMs: 1000,
    recordingMethod: enums.RecordingMethodEnum.unknown,
    startMs: _baseMs,
    startOffsetS: null,
    endMs: _baseMs + stages * 60000 + 60000,
    endOffsetS: null,
    title: 'Nacht',
    notes: notes,
    stages: [
      for (var i = 0; i < stages; i++)
        api.SleepStageRequest(
          startMs: _baseMs + i * 60000,
          endMs: _baseMs + i * 60000 + 60000,
          stage: enums.SleepStageEnum.light,
        ),
    ],
  ),
);

IngestItem _window(int hours, {int buckets = 0}) => IngestItem.window(
  api.HealthAggregateWindowRequest(
    metric: enums.HealthAggregateMetricEnum.stepsCountTotal,
    startMs: _baseMs,
    endMs: _baseMs + hours * _hour,
    computedAtMs: _baseMs + hours * _hour,
    buckets: [
      for (var i = 0; i < buckets; i++)
        api.HealthAggregateBucketRequest(
          startMs: _baseMs + i * _hour,
          value: i,
          dataOrigins: const ['com.example.fit'],
        ),
    ],
  ),
);

IngestItem _deletion(int n) => IngestItem.deletion(
  api.HealthDeletionRequest(hcId: uuid(n), observedAtMs: 5000),
);

/// Every invariant a packing must hold, checked without the packer's own
/// arithmetic: sizes by encoding the bodies, content by parsing them.
void _expectValidPacking(
  List<IngestItem> input,
  PackedBatches packed, {
  required int? coverageStartMs,
  required int maxItems,
  required int maxBytes,
}) {
  final seen = <String>[];
  for (final batch in packed.batches) {
    final bytes = utf8.encode(batch.body).length;
    expect(bytes, batch.byteLength);
    expect(bytes, lessThanOrEqualTo(maxBytes));
    final cost = batch.items.fold<int>(0, (sum, item) => sum + item.cost);
    expect(cost, batch.itemCost);
    expect(cost, lessThanOrEqualTo(maxItems));

    final decoded = jsonDecode(batch.body) as Map<String, dynamic>;
    expect(decoded.containsKey('coverage_start_ms'), isTrue);
    expect(decoded['coverage_start_ms'], coverageStartMs);
    for (final list in IngestList.values) {
      final entries = decoded[list.key] as List<dynamic>?;
      final expected = [
        for (final item in batch.items)
          if (item.list == list) jsonDecode(item.encoded),
      ];
      if (expected.isEmpty) {
        // No empty lists on the wire.
        expect(entries, isNull, reason: list.key);
      } else {
        expect(entries, expected, reason: list.key);
      }
    }
    seen.addAll(batch.items.map((item) => item.encoded));
  }

  // Nothing lost, nothing duplicated, input order kept within each list.
  seen.addAll(packed.oversized.map((item) => item.encoded));
  expect(seen..sort(), [...input.map((item) => item.encoded)]..sort());

  for (final item in packed.oversized) {
    final alone = utf8.encode(
      '{"coverage_start_ms":${jsonEncode(coverageStartMs)},'
      '"${item.list.key}":[${item.encoded}]}',
    );
    expect(
      item.cost > maxItems || alone.length > maxBytes,
      isTrue,
      reason: 'an item that fits alone must not be called oversized',
    );
  }

  // Greedy: a batch closed only because the next item in input order did not
  // fit; otherwise the packer split early and sends more requests than needed.
  // (A batch lists its items by contract list, so that item is the batch's
  // earliest by input position, not its first.)
  final position = Map<IngestItem, int>.identity();
  for (var i = 0; i < input.length; i++) {
    position[input[i]] = i;
  }
  for (var i = 0; i + 1 < packed.batches.length; i++) {
    final current = packed.batches[i];
    final next = packed.batches[i + 1].items.reduce(
      (a, b) => position[a]! <= position[b]! ? a : b,
    );
    final listed = current.items.any((item) => item.list == next.list);
    final added = listed
        ? 1 + next.encodedBytes
        : ',"${next.list.key}":['.length + 1 + next.encodedBytes;
    expect(
      current.itemCost + next.cost > maxItems ||
          current.byteLength + added > maxBytes,
      isTrue,
      reason: 'batch $i closed while the next item still fit',
    );
  }
}

void main() {
  test('one small batch carries every list, in contract order', () {
    final items = [_window(2), _deletion(1), _steps(2), _sleep(3, 'x', 1)];
    final packed = packBatches(items, coverageStartMs: 1234);

    expect(packed.batches, hasLength(1));
    expect(packed.oversized, isEmpty);
    final body = packed.batches.single.body;
    expect(body, startsWith('{"coverage_start_ms":1234,"steps":['));
    expect(
      body.indexOf('"sleep_session"') < body.indexOf('"deletions"') &&
          body.indexOf('"deletions"') < body.indexOf('"aggregate_windows"'),
      isTrue,
    );
    _expectValidPacking(
      items,
      packed,
      coverageStartMs: 1234,
      maxItems: IngestLimits.maxItems,
      maxBytes: IngestLimits.maxBytes,
    );
  });

  test('coverage_start_ms is sent as null, not omitted', () {
    final packed = packBatches([_steps(1)], coverageStartMs: null);
    expect(
      packed.batches.single.body,
      startsWith('{"coverage_start_ms":null,'),
    );
  });

  test('no items, no batches', () {
    expect(packBatches(const [], coverageStartMs: null).batches, isEmpty);
  });

  test('a window costs its hours, with or without buckets', () {
    final empty = _window(168);
    final full = _window(168, buckets: 168);
    expect(empty.cost, 168);
    expect(full.cost, 168);

    // 29 week-long windows are 4,872 items; a 30th would be 5,040.
    final windows = List.generate(30, (_) => _window(168));
    final packed = packBatches(windows, coverageStartMs: null);
    expect(packed.batches.map((batch) => batch.itemCost), [4872, 168]);
  });

  test('exactly 5,000 items fit in one batch; 5,001 do not', () {
    final five = [for (var n = 0; n < 5000; n++) _deletion(n)];
    expect(packBatches(five, coverageStartMs: null).batches, hasLength(1));

    final over = [...five, _deletion(5000)];
    final packed = packBatches(over, coverageStartMs: null);
    expect(packed.batches.map((batch) => batch.itemCost), [5000, 1]);
  });

  test('the byte cap is inclusive: a body of exactly the cap is one batch', () {
    final a = _steps(1);
    final b = _steps(2);
    final together = packBatches([
      a,
      b,
    ], coverageStartMs: null).batches.single.byteLength;

    final atCap = packBatches(
      [a, b],
      coverageStartMs: null,
      maxBytes: together,
    );
    expect(atCap.batches, hasLength(1));

    final belowCap = packBatches(
      [a, b],
      coverageStartMs: null,
      maxBytes: together - 1,
    );
    expect(belowCap.batches, hasLength(2));
    _expectValidPacking(
      [a, b],
      belowCap,
      coverageStartMs: null,
      maxItems: IngestLimits.maxItems,
      maxBytes: together - 1,
    );
  });

  test('bytes, not characters: multibyte text counts at its UTF-8 size', () {
    // 'ž' is 2 bytes, '🜂' is 4 bytes and 2 UTF-16 units.
    final item = _sleep(1, 'ž🜂' * 1000, 3);
    expect(item.encodedBytes, utf8.encode(item.encoded).length);
    expect(item.encodedBytes, greaterThan(item.encoded.length));

    final alone = packBatches([item], coverageStartMs: null).batches.single;
    final tooSmall = packBatches(
      [item],
      coverageStartMs: null,
      maxBytes: alone.byteLength - 1,
    );
    expect(tooSmall.batches, isEmpty);
    expect(tooSmall.oversized, [item]);
  });

  test('an item larger than any batch is set aside, the rest still go', () {
    final huge = _sleep(1, 'n' * 9000, 2000);
    final small = [for (var n = 2; n < 12; n++) _steps(n)];
    final maxBytes = huge.encodedBytes; // The envelope pushes it over.
    final packed = packBatches(
      [small.first, huge, ...small.skip(1)],
      coverageStartMs: 7,
      maxBytes: maxBytes,
    );
    expect(packed.oversized, [huge]);
    _expectValidPacking(
      [small.first, huge, ...small.skip(1)],
      packed,
      coverageStartMs: 7,
      maxItems: IngestLimits.maxItems,
      maxBytes: maxBytes,
    );
  });

  test('12,000 steps records at the real caps', () {
    final items = [for (var n = 0; n < 12000; n++) _steps(n)];
    final packed = packBatches(items, coverageStartMs: null);
    expect(packed.batches.map((batch) => batch.itemCost), [5000, 5000, 2000]);
    _expectValidPacking(
      items,
      packed,
      coverageStartMs: null,
      maxItems: IngestLimits.maxItems,
      maxBytes: IngestLimits.maxBytes,
    );
  });

  test('random items and caps never break a cap or lose an item', () {
    // Structured randomness: mixed lists, multibyte strings, windows up to
    // 744 hours, and caps small enough that most runs split several times.
    const alphabet = ['a', 'ž', 'ш', '🜂', '"', r'\', ' '];
    for (var seed = 0; seed < 300; seed++) {
      final random = Random(seed);
      String text(int length) => [
        for (var i = 0; i < length; i++)
          alphabet[random.nextInt(alphabet.length)],
      ].join();
      final items = <IngestItem>[
        for (var n = 0; n < random.nextInt(120); n++)
          switch (random.nextInt(4)) {
            0 => _steps(n, title: text(1 + random.nextInt(60))),
            1 => _sleep(n, text(random.nextInt(400)), random.nextInt(30)),
            2 => _deletion(n),
            _ => _window(
              1 + random.nextInt(744),
              buckets: random.nextInt(5),
            ),
          },
      ];
      final maxItems = 1 + random.nextInt(seed.isEven ? 2000 : 6000);
      final maxBytes = 200 + random.nextInt(seed.isEven ? 4000 : 60000);
      final coverage = random.nextBool()
          ? null
          : random.nextInt(1 << 30) * 4096;

      final packed = packBatches(
        items,
        coverageStartMs: coverage,
        maxItems: maxItems,
        maxBytes: maxBytes,
      );
      _expectValidPacking(
        items,
        packed,
        coverageStartMs: coverage,
        maxItems: maxItems,
        maxBytes: maxBytes,
      );
    }
  });
}
