import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/ops.dart';
import 'package:notif/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/auth_test_harness.dart';

const _requiredFields = [
  'id',
  'created_at',
  'level',
  'source',
  'kind',
  'message',
];

Map<String, dynamic> _event({int id = 1, String level = 'warning'}) => {
  'id': id,
  'created_at': '2026-10-01T12:30:00Z',
  'level': level,
  'source': 'scheduler',
  'kind': 'scrape_failed',
  'message': 'Fetch timed out',
  'details': <String, dynamic>{'link_id': 4},
};

/// The hand-written parser the generated-model route replaced, kept as the
/// oracle for "valid payloads parse exactly as before".
SystemEvent _previousParse(Map<String, dynamic> json) => SystemEvent(
  id: json['id'] as int,
  createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  level: json['level'] as String,
  source: json['source'] as String,
  kind: json['kind'] as String,
  message: json['message'] as String,
  details: json['details'] is Map
      ? Map<String, dynamic>.from(json['details'] as Map)
      : const {},
);

void _expectSameEvent(SystemEvent actual, SystemEvent expected) {
  expect(actual.id, expected.id);
  expect(actual.createdAt, expected.createdAt);
  expect(actual.createdAt.isUtc, expected.createdAt.isUtc);
  expect(actual.level, expected.level);
  expect(actual.source, expected.source);
  expect(actual.kind, expected.kind);
  expect(actual.message, expected.message);
  expect(actual.details, expected.details);
}

final Matcher _throwsContractViolation = throwsA(
  isA<FormatException>().having(
    (error) => error.message,
    'message',
    startsWith('contract violation'),
  ),
);

/// Valid per the schema, spread over the shapes the old parser accepted:
/// offsets, fractional seconds, levels outside the generated enum, details
/// that are not objects.
Map<String, dynamic> _randomValidEvent(Random random) {
  T pick<T>(List<T> options) => options[random.nextInt(options.length)];
  final micros = random.nextInt(1000000);
  final instant = DateTime.fromMicrosecondsSinceEpoch(
    random.nextInt(1 << 32) * 1000000 + micros,
    isUtc: true,
  );
  final seconds = instant.toIso8601String().substring(0, 19);
  final fraction = micros.toString().padLeft(6, '0');
  final createdAt = pick([
    instant.toIso8601String(),
    '${seconds}Z',
    '$seconds+02:00',
    '$seconds.$fraction-05:30',
    seconds,
  ]);
  final text = <String>['', ' padded ', 'plain', 'ünïcödé · 字', 'a\nb'];
  final event = <String, dynamic>{
    'id': pick([0, 1, random.nextInt(1 << 31), (1 << 53) - 1]),
    'created_at': createdAt,
    'level': pick([
      'debug',
      'info',
      'warning',
      'error',
      'critical',
      'notice',
      'WARNING',
      '',
    ]),
    'source': pick(text),
    'kind': pick(text),
    'message': pick(text),
  };
  switch (random.nextInt(6)) {
    case 0:
      break;
    case 1:
      event['details'] = null;
    case 2:
      event['details'] = <String, dynamic>{};
    case 3:
      event['details'] = <String, dynamic>{
        'status': random.nextInt(600),
        'nested': <String, dynamic>{
          'list': [1, 'two', null],
        },
      };
    case 4:
      event['details'] = ['not', 'a', 'map'];
    case 5:
      event['details'] = 'free text';
  }
  return event;
}

/// Values of the wrong JSON type for [field]. Numbers are left out for `id`
/// (the generated parser truncates them) and strings for `level` (unknown
/// levels pass through by design).
List<Object?> _wrongTypes(String field) => switch (field) {
  'id' => ['7', true, <Object?>[], <String, dynamic>{}],
  'created_at' => [
    5,
    true,
    <Object?>[],
    <String, dynamic>{},
    '',
    'not-a-date',
  ],
  'level' => [5, 1.5, true, <Object?>[], <String, dynamic>{}],
  _ => [5, 1.5, true, <Object?>[], <String, dynamic>{}],
};

void main() {
  group('SystemEvent.fromJson', () {
    test('valid payloads parse exactly as the previous parser did', () {
      final random = Random(20261007);
      for (var i = 0; i < 400; i++) {
        final json = _randomValidEvent(random);
        _expectSameEvent(SystemEvent.fromJson(json), _previousParse(json));
      }
    });

    test('a level outside the generated enum keeps its wire name', () {
      expect(SystemEvent.fromJson(_event(level: 'notice')).level, 'notice');
    });

    for (final field in _requiredFields) {
      test('missing $field is a contract violation', () {
        expect(
          () => SystemEvent.fromJson(_event()..remove(field)),
          _throwsContractViolation,
        );
      });

      test('null $field is a contract violation', () {
        expect(
          () => SystemEvent.fromJson(_event()..[field] = null),
          _throwsContractViolation,
        );
      });

      for (final wrong in _wrongTypes(field)) {
        test(
          '$field = ${wrong.runtimeType} $wrong is a contract violation',
          () {
            expect(
              () => SystemEvent.fromJson(_event()..[field] = wrong),
              _throwsContractViolation,
            );
          },
        );
      }
    }
  });

  group('OpsService.fetchEvents', () {
    late FakeApiAdapter adapter;
    late HttpClientAdapter originalAdapter;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      originalAdapter = apiHttpClientAdapter;
      adapter = FakeApiAdapter();
      apiHttpClientAdapter = adapter;
    });

    tearDown(() {
      apiHttpClientAdapter = originalAdapter;
      resetApiAuth();
    });

    Future<OpsService> signedInOps() async {
      adapter.enqueue(
        '/get_my_info/',
        const FakeReply(statusCode: 200, body: fakeUserJson),
      );
      final auth = AuthService(
        store: InMemorySessionStore(
          initial: SessionCredential(
            token: 'ops-token',
            origin: Uri.parse(builtinApiUrl).origin,
          ),
        ),
        transport: SessionTransport.bearer,
        maxRecoveryProbes: 0,
      );
      await auth.restore();
      expect(auth.isAuthenticated, isTrue);
      return OpsService(auth);
    }

    void replyEvents(List<Object?> results) => adapter.enqueue(
      '/ops/events/',
      FakeReply(
        statusCode: 200,
        body: {'count': results.length, 'results': results},
      ),
    );

    test('valid events populate the list', () async {
      final ops = await signedInOps();
      replyEvents([_event(), _event(id: 2, level: 'notice')]);

      await ops.fetchEvents();

      expect(ops.error, isNull);
      expect(ops.loading, isFalse);
      expect(ops.events.map((event) => event.id), [1, 2]);
      expect(ops.events.last.level, 'notice');
    });

    test('a mistyped required field is shown, not thrown', () async {
      final ops = await signedInOps();
      replyEvents([_event()..['id'] = 'seven']);

      await ops.fetchEvents();

      expect(ops.error, contains('contract violation'));
      expect(ops.loading, isFalse);
      expect(ops.events, isEmpty);
    });

    test('a non-object event is shown, not silently dropped', () async {
      final ops = await signedInOps();
      replyEvents([_event(), 'not an event']);

      await ops.fetchEvents();

      expect(ops.error, contains('contract violation'));
      expect(ops.events, isEmpty);
    });

    test('a failed refresh keeps the last complete list', () async {
      final ops = await signedInOps();
      replyEvents([_event(), _event(id: 2)]);
      replyEvents([_event(id: 3), _event(id: 4)..remove('message')]);

      await ops.fetchEvents();
      await ops.fetchEvents();

      expect(ops.error, contains('contract violation'));
      expect(ops.events.map((event) => event.id), [1, 2]);
    });
  });
}
