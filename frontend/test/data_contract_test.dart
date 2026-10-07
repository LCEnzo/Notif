import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/data.dart';

void main() {
  group('schema-contract parsing', () {
    test('missing required field surfaces an Exception, not a TypeError', () {
      // The generated _$LinkFromJson reads `json['name'] as String`, which
      // throws a TypeError (a Dart Error) when the wire omits a required
      // field. Fetch sites catch `on Exception`, so _parseContract must
      // convert it — otherwise the failure would escape as an unhandled zone
      // error and the user would see a silently empty list.
      expect(
        () => Link.fromJson(const <String, dynamic>{'id': 1}, const {}),
        throwsA(isA<FormatException>()),
      );
    });

    test('unknown strategy class passes through instead of coercing', () {
      // The generated enum is a closed set frozen at build time. A strategy
      // class the backend added later must keep its wire name — coercing it
      // to the general default would misidentify it in the UI and feed the
      // edit flow's class-change detection with a lie.
      final record = StrategyRecord.fromJson(const <String, dynamic>{
        'id': 2,
        'strat_cls': 'BrandNewStrategy',
        'data': <String, dynamic>{},
      });

      expect(record.className, 'BrandNewStrategy');
    });

    test('missing strategy class still falls back to the general default', () {
      final record = StrategyRecord.fromJson(const <String, dynamic>{
        'id': 3,
        'data': <String, dynamic>{},
      });

      expect(record.className, generalSelectorStrategy);
    });

    test('complete payload parses and projects', () {
      final link = Link.fromJson(
        const <String, dynamic>{
          'id': 7,
          'name': 'Example',
          'url': 'https://example.com',
          'strategy': 3,
          'last_scraped': '2026-08-02T10:00:00Z',
        },
        const <int, StrategyRecord>{},
      );

      expect(link.id, 7);
      expect(link.name, 'Example');
      expect(link.url, 'https://example.com');
      expect(link.strategyId, 3);
    });
  });
}
