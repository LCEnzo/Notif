import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/data.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/json_contracts.dart';

JsonCursor cursor(Object? value) {
  return JsonCursor.root(endpoint: 'test', value: value);
}

void main() {
  group('NotificationStatus.fromWire', () {
    test('parses unread', () {
      expect(NotificationStatus.fromWire('unread'), NotificationStatus.unread);
    });
    test('parses read', () {
      expect(NotificationStatus.fromWire('read'), NotificationStatus.read);
    });
    test('parses dismissed', () {
      expect(
        NotificationStatus.fromWire('dismissed'),
        NotificationStatus.dismissed,
      );
    });
    test('unknown string returns unknown', () {
      expect(NotificationStatus.fromWire('bogus'), NotificationStatus.unknown);
    });
    test('null returns unknown', () {
      expect(NotificationStatus.fromWire(null), NotificationStatus.unknown);
    });
    test('whitespace returns unknown', () {
      expect(NotificationStatus.fromWire('  '), NotificationStatus.unknown);
    });
  });

  group('NotificationItem', () {
    test('fromJson parses unread notification', () {
      final json = <String, dynamic>{
        'id': 1,
        'status': 'unread',
        'update': {
          'title': '  New chapter  ',
          'description': 'Chapter 42 is out',
          'item_url': 'https://example.com/ch42',
          'created_at': '2026-04-01T12:00:00Z',
        },
      };

      final item = NotificationItem.fromJson(cursor(json));

      expect(item.id, 1);
      expect(item.title, 'New chapter');
      expect(item.description, 'Chapter 42 is out');
      expect(item.itemUrl, 'https://example.com/ch42');
      expect(item.status, NotificationStatus.unread);
      expect(item.isUnread, isTrue);
      expect(item.readAt, isNull);
    });

    test('fromJson parses read notification with read_at', () {
      final json = <String, dynamic>{
        'id': 2,
        'status': 'read',
        'read_at': '2026-04-02T08:00:00Z',
        'update': {
          'title': 'Old news',
          'description': '',
          'item_url': '',
          'created_at': '2026-04-01T10:00:00Z',
        },
      };

      final item = NotificationItem.fromJson(cursor(json));

      expect(item.isUnread, isFalse);
      expect(item.readAt, isNotNull);
    });

    test('fromJson reports exact path for malformed payload', () {
      final json = <String, dynamic>{'id': 3, 'status': 'unread'};

      expect(
        () => NotificationItem.fromJson(cursor(json)),
        throwsA(
          isA<ContractViolation>().having(
            (error) => error.path,
            'path',
            r'$',
          ),
        ),
      );
    });

    test('copyWith returns new instance with updated fields', () {
      final original = NotificationItem(
        id: 1,
        title: 'Test',
        description: '',
        itemUrl: '',
        status: NotificationStatus.unread,
        createdAt: DateTime(2026),
      );

      final updated = original.copyWith(status: NotificationStatus.read);
      expect(updated.status, NotificationStatus.read);
      expect(updated.isUnread, isFalse);
      // Original is unchanged
      expect(original.isUnread, isTrue);

      final withReadAt = original.copyWith(readAt: DateTime(2026, 4, 1));
      expect(withReadAt.readAt, DateTime(2026, 4, 1));
      expect(original.readAt, isNull);
    });

    test('copyWith with clearReadAt drops the timestamp', () {
      // Toggling read → unread needs to actively null out read_at, which a
      // plain `?? this.readAt` fallback can't express.
      final read = NotificationItem(
        id: 1,
        title: 'Test',
        description: '',
        itemUrl: '',
        status: NotificationStatus.read,
        createdAt: DateTime(2026),
        readAt: DateTime(2026, 4, 1),
      );

      final unread = read.copyWith(
        status: NotificationStatus.unread,
        clearReadAt: true,
      );
      expect(unread.status, NotificationStatus.unread);
      expect(unread.readAt, isNull);
    });
  });

  group('StrategyRecord', () {
    test('fromJson parses complete strategy', () {
      final json = <String, dynamic>{
        'id': 42,
        'strat_cls': 'GeneralSelectorStrategy',
        'data': {
          'selectors': ['article.post-card', 'div.content'],
        },
      };

      final record = StrategyRecord.fromJson(cursor(json));

      expect(record.id, 42);
      expect(record.className, 'GeneralSelectorStrategy');
      expect(record.selectors, ['article.post-card', 'div.content']);
    });

    test('fromJson defaults missing strat_cls to GeneralSelectorStrategy', () {
      final json = <String, dynamic>{'id': 1, 'data': <String, dynamic>{}};

      final record = StrategyRecord.fromJson(cursor(json));

      expect(record.className, generalSelectorStrategy);
    });

    test('selectors filters empty strings', () {
      const record = StrategyRecord(
        id: 1,
        className: 'Test',
        data: {
          'selectors': ['', '  ', 'div.real', ''],
        },
      );

      expect(record.selectors, ['div.real']);
    });

    test('selectors returns empty list when selectors is not a List', () {
      const record = StrategyRecord(
        id: 1,
        className: 'Test',
        data: {'selectors': 'not-a-list'},
      );

      expect(record.selectors, isEmpty);
    });

    test('selectors returns empty list when data has no selectors key', () {
      const record = StrategyRecord(id: 1, className: 'Test', data: {});

      expect(record.selectors, isEmpty);
    });
  });

  group('Link', () {
    test('fromJson parses link with strategy', () {
      final strategies = <int, StrategyRecord>{
        42: const StrategyRecord(
          id: 42,
          className: 'GeneralSelectorStrategy',
          data: {
            'selectors': ['div.post'],
          },
        ),
      };
      final json = <String, dynamic>{
        'id': 10,
        'name': 'My Blog',
        'url': 'https://example.com',
        'strategy': 42,
        'last_scraped': '2026-04-01T12:00:00Z',
      };

      final link = Link.fromJson(cursor(json), strategies);

      expect(link.id, 10);
      expect(link.name, 'My Blog');
      expect(link.url, 'https://example.com');
      expect(link.strategyId, 42);
      expect(link.strategyClass, 'GeneralSelectorStrategy');
      expect(link.selectors, ['div.post']);
      expect(link.lastScraped, isNotNull);
    });

    test('fromJson handles missing strategy gracefully', () {
      final json = <String, dynamic>{
        'id': 10,
        'name': 'My Blog',
        'url': 'https://example.com',
        'strategy': 999,
      };

      final link = Link.fromJson(cursor(json), const {});

      expect(link.strategyClass, 'UnknownStrategy');
      expect(link.selectors, isEmpty);
    });

    test('fromJson handles null strategy id', () {
      final json = <String, dynamic>{
        'id': 10,
        'name': 'My Blog',
        'url': 'https://example.com',
      };

      final link = Link.fromJson(cursor(json), const {});

      expect(link.strategyId, isNull);
      expect(link.strategyClass, 'UnknownStrategy');
    });
  });

  group('formatStrategyClassName', () {
    test('inserts space before capital letters', () {
      // GeneralSelectorStrategy → General Selector (Strategy suffix stripped)
      expect(
        formatStrategyClassName('GeneralSelectorStrategy'),
        'General Selector',
      );
    });
    test('handles single word (Strategy suffix stripped, no camel case)', () {
      // FeedStrategy → Feed (no inner camel case to space out)
      expect(formatStrategyClassName('FeedStrategy'), 'Feed');
    });
    test('handles acronyms via special-case mapping', () {
      expect(
        formatStrategyClassName('SBSVThreadmarksStrategy'),
        'SB/SV Threadmarks',
      );
    });
  });

  group('describeDataError', () {
    DioException dioError(int statusCode, dynamic data) {
      return DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: statusCode,
          data: data,
        ),
      );
    }

    test('extracts detail from JSON error response', () {
      expect(
        describeDataError(dioError(404, {'detail': 'Not found.'})),
        'Not found.',
      );
    });

    test('extracts message field', () {
      expect(
        describeDataError(dioError(400, {'message': 'Invalid input'})),
        'Invalid input',
      );
    });

    test('returns status code when body has no extractable message', () {
      expect(
        describeDataError(dioError(500, '')),
        'The server failed while handling the request.',
      );
    });

    test('never shows the transport message to the user', () {
      // Dio always populates `message`, and its text is written for library
      // authors, not users. Copy goes to the UI; the technical text stays on
      // AppFailure.detail for logs.
      final error = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionTimeout,
        message: 'The request connection took longer than 0:00:10.000000 '
            'to establish. It was aborted.',
      );

      expect(describeDataError(error), isNot(contains('0:00:10')));
      expect(describeDataError(error), isNot(contains('aborted')));
      expect(
        describeDataError(error),
        'The server took too long to respond. Try again in a moment.',
      );
      expect(AppFailure.from(error).detail, contains('0:00:10'));
    });

    test('returns toString for non-DioException objects', () {
      expect(describeDataError('Connection refused'), 'Connection refused');
    });
  });
}
