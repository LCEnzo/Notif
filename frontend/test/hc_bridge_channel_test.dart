import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_bridge/hc_bridge.dart';

const MethodChannel _channel = MethodChannel(MethodChannelHcBridge.channelName);

void _answer(Object? Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async => handler(call));
}

Matcher _bridgeError(HcErrorCode code) =>
    isA<HcBridgeException>().having((error) => error.code, 'code', code);

Map<String, Object?> _steps() => {
  'type': 'steps',
  'id': 'abc',
  'data_origin': 'com.example',
  'last_modified_ms': 5,
  'recording_method': 'manual_entry',
  'device': {'type': 'watch', 'manufacturer': null, 'model': 'W'},
  'start_ms': 1,
  'start_offset_s': null,
  'end_ms': 2,
  'end_offset_s': 3600,
  'count': 7,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannelHcBridge();

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  test(
    'decodes status, records and arguments as the Kotlin side sends them',
    () async {
      final calls = <MethodCall>[];
      _answer((call) {
        calls.add(call);
        return switch (call.method) {
          'status' => {
            'sdk': 'available',
            'features': {
              'history': 'unavailable',
              'background': 'available',
              'mindfulness': 'available',
              'some_future_feature': 'available',
            },
            'granted': ['android.permission.health.READ_STEPS'],
          },
          'readRecords' => {
            'records': [_steps()],
            'next_page_token': 'p2',
          },
          _ => null,
        };
      });

      final status = await bridge.status();
      expect(status.sdk, HcSdkStatus.available);
      expect(status.features, {HcFeature.background, HcFeature.mindfulness});
      expect(status.readableTypes, [HcRecordType.steps]);
      // READ_STEPS also covers steps cadence.
      expect(status.readableDataTypes, [
        HcDataType.steps,
        HcDataType.stepsCadence,
      ]);

      final page = await bridge.readRecords(
        HcRecordType.steps,
        startMs: 10,
        endMs: 20,
      );
      expect(calls.last.arguments, {
        'type': 'steps',
        'start_ms': 10,
        'end_ms': 20,
        'page_token': null,
        'page_size': 1000,
      });
      expect(page.nextPageToken, 'p2');
      final record = page.records.single as HcStepsRecord;
      expect(record.count, 7);
      expect(record.startOffsetS, isNull);
      expect(record.metadata.device!.manufacturer, isNull);
      expect(record.metadata.device!.type, 'watch');
    },
  );

  test(
    'platform error codes become typed errors, unknown ones unexpected',
    () async {
      _answer(
        (call) =>
            throw PlatformException(code: 'rate_limited', message: 'quota'),
      );
      await expectLater(
        bridge.status(),
        throwsA(_bridgeError(HcErrorCode.rateLimited)),
      );

      _answer((call) => throw PlatformException(code: 'something_new'));
      await expectLater(
        bridge.status(),
        throwsA(_bridgeError(HcErrorCode.unexpected)),
      );
    },
  );

  test('a missing plugin is "unavailable", not a crash', () async {
    // No handler: the channel answers MissingPluginException, as on web or a
    // desktop build.
    await expectLater(
      bridge.status(),
      throwsA(_bridgeError(HcErrorCode.unavailable)),
    );
  });

  test('a malformed answer is an error, never a null or a default', () async {
    final malformed = <String, Object?>{
      'null result': null,
      'missing features': {'sdk': 'available', 'granted': <String>[]},
      'unknown enum': {
        'sdk': 'sideways',
        'features': <String, String>{},
        'granted': <String>[],
      },
      'wrong type': {
        'sdk': 'available',
        'features': <String, String>{},
        'granted': 'all of them',
      },
      'mistyped feature': {
        'sdk': 'available',
        'features': {'history': true},
        'granted': <String>[],
      },
    };
    for (final MapEntry(:key, :value) in malformed.entries) {
      _answer((call) => value);
      await expectLater(
        bridge.status(),
        throwsA(_bridgeError(HcErrorCode.malformedResponse)),
        reason: key,
      );
    }

    _answer(
      (call) => {
        'records': [
          {..._steps(), 'count': '7'},
        ],
        'next_page_token': null,
      },
    );
    await expectLater(
      bridge.readRecords(HcRecordType.steps, startMs: 0, endMs: 1),
      throwsA(_bridgeError(HcErrorCode.malformedResponse)),
    );

    _answer((call) => '');
    await expectLater(
      bridge.changesToken({HcRecordType.steps}),
      throwsA(_bridgeError(HcErrorCode.malformedResponse)),
    );
  });

  test('changes pages decode both kinds and refuse an unknown one', () async {
    _answer(
      (call) => {
        'changes': [
          {'kind': 'deletion', 'id': 'gone'},
          {'kind': 'upsert', 'record': _steps()},
        ],
        'next_token': 'n',
        'has_more': true,
        'token_expired': false,
        'observed_at_ms': 99,
        'skipped_unsupported': 0,
      },
    );
    final page = await bridge.changes('t');
    expect(page.changes.first, isA<HcDeletion>());
    expect(page.changes.last, isA<HcUpsertion>());
    expect(page.observedAtMs, 99);

    _answer(
      (call) => {
        'changes': [
          {'kind': 'teleport'},
        ],
        'next_token': 'n',
        'has_more': false,
        'token_expired': false,
        'observed_at_ms': 99,
        'skipped_unsupported': 0,
      },
    );
    await expectLater(
      bridge.changes('t'),
      throwsA(_bridgeError(HcErrorCode.malformedResponse)),
    );
  });

  test('only permissions this Health Connect can grant are requested', () {
    const bare = HcStatus(
      sdk: HcSdkStatus.available,
      features: {},
      grantedPermissions: {},
    );
    final requested = HcPermissions.requestable(bare);
    expect(requested, isNot(contains(HcPermissions.readHistory)));
    expect(
      requested,
      isNot(contains(HcDataType.skinTemperature.readPermission)),
    );
    expect(requested, contains(HcPermissions.readSteps));
    // Menstruation flow and period share one permission.
    expect(requested, hasLength(HcPermissions.dataReads.length - 3));

    final full = HcPermissions.requestable(
      const HcStatus(
        sdk: HcSdkStatus.available,
        features: {...HcFeature.values},
        grantedPermissions: {},
      ),
    );
    expect(full, {
      ...HcPermissions.dataReads,
      HcPermissions.readHistory,
      HcPermissions.readInBackground,
    });
    expect(HcPermissions.dataReads, hasLength(38));
  });

  test('battery exemption: a bool, or a typed error', () async {
    final calls = <String>[];
    _answer((call) {
      calls.add(call.method);
      return call.method == 'batteryOptimizationExempt' ? true : null;
    });
    expect(await bridge.batteryOptimizationExempt(), isTrue);
    await bridge.requestBatteryOptimizationExemption();
    expect(calls, [
      'batteryOptimizationExempt',
      'requestBatteryOptimizationExemption',
    ]);

    _answer((call) => 'yes');
    await expectLater(
      bridge.batteryOptimizationExempt(),
      throwsA(_bridgeError(HcErrorCode.malformedResponse)),
    );
  });
}
