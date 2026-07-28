import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/json_contracts.dart';
import 'package:notif/services/persistence.dart';

void main() {
  DioException dioError(
    DioExceptionType type, {
    int? statusCode,
    Object? data = const {'detail': 'server detail'},
    String? message,
  }) {
    return DioException(
      requestOptions: RequestOptions(path: '/test'),
      type: type,
      message: message,
      response: statusCode == null
          ? null
          : Response<dynamic>(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: statusCode,
              data: data,
            ),
    );
  }

  test('classifies contract violations', () {
    final failure = AppFailure.from(
      const ContractViolation(
        endpoint: 'GET /x',
        path: r'$.id',
        expected: 'integer',
        actual: 'string',
      ),
    );

    expect(failure.category, FailureCategory.contractViolation);
    expect(failure.contractPath, r'$.id');
    expect(failure.expected, 'integer');
  });

  test('classifies corrupt local state', () {
    final failure = AppFailure.from(
      CorruptLocalStateException(
        key: 'backendUrlMode',
        expected: 'String',
        actual: 'bool',
      ),
    );

    expect(failure.category, FailureCategory.corruptLocalState);
    expect(failure.actual, 'bool');
  });

  test('classifies network and auth failures', () {
    expect(
      AppFailure.from(dioError(DioExceptionType.connectionTimeout)).category,
      FailureCategory.timeout,
    );
    expect(
      AppFailure.from(dioError(DioExceptionType.connectionError)).category,
      FailureCategory.networkUnavailable,
    );
    expect(
      AppFailure.from(
        dioError(DioExceptionType.badResponse, statusCode: 401),
      ).category,
      FailureCategory.unauthorized,
    );
  });

  group('user-facing copy never leaks transport internals', () {
    test('connection errors read as an offline message', () {
      const dioNoise =
          'The connection errored: Connection refused This indicates an '
          'error which most likely cannot be solved by the library.';
      final failure = AppFailure.from(
        dioError(DioExceptionType.connectionError, message: dioNoise),
      );

      expect(failure.category, FailureCategory.networkUnavailable);
      expect(failure.userMessage, isNot(contains('Connection refused')));
      expect(failure.userMessage, isNot(contains('library')));
      expect(failure.isRetryable, isTrue);
      expect(failure.detail, contains('Connection refused'));
      expect(failure.debugMessage, contains('Connection refused'));
    });

    test('web XHR errors read as an offline message', () {
      final failure = AppFailure.from(
        dioError(
          DioExceptionType.unknown,
          message:
              'The XMLHttpRequest onError callback was called. '
              'This typically indicates an error on the network layer.',
        ),
      );

      expect(failure.category, FailureCategory.networkUnavailable);
      expect(failure.userMessage, isNot(contains('XMLHttpRequest')));
      expect(failure.detail, contains('XMLHttpRequest'));
    });

    test('timeouts read as a timeout message', () {
      final failure = AppFailure.from(
        dioError(
          DioExceptionType.receiveTimeout,
          message:
              'The request took longer than 0:00:15.000000 to receive '
              'data. It was aborted.',
        ),
      );

      expect(failure.category, FailureCategory.timeout);
      expect(failure.userMessage, isNot(contains('0:00:15')));
      expect(failure.userMessage, isNot(contains('aborted')));
      expect(failure.isRetryable, isTrue);
      expect(failure.detail, contains('aborted'));
    });

    test('HTML gateway bodies never reach the user message', () {
      final failure = AppFailure.from(
        dioError(
          DioExceptionType.badResponse,
          statusCode: 502,
          data:
              '<!DOCTYPE html><html><head><title>502 Bad Gateway</title> '
              '</head><body><h1>502 Bad Gateway</h1></body></html>',
        ),
      );

      expect(failure.category, FailureCategory.sourceBlockedDegraded);
      expect(failure.userMessage, isNot(contains('<')));
      expect(failure.userMessage, isNot(contains('DOCTYPE')));
    });

    test('server JSON detail still reaches the user', () {
      final failure = AppFailure.from(
        dioError(DioExceptionType.badResponse, statusCode: 400),
      );

      expect(failure.category, FailureCategory.validationFailed);
      expect(failure.userMessage, 'server detail');
    });
  });

  group('gateway status taxonomy', () {
    test('504 and Cloudflare 52x are degraded, not app bugs', () {
      for (final status in [429, 502, 503, 504, 520, 521, 522, 523, 527]) {
        expect(
          AppFailure.from(
            dioError(
              DioExceptionType.badResponse,
              statusCode: status,
              data: null,
            ),
          ).category,
          FailureCategory.sourceBlockedDegraded,
          reason: 'status $status should be treated as a transient outage',
        );
      }
    });

    test('500 stays a server error', () {
      expect(
        AppFailure.from(
          dioError(DioExceptionType.badResponse, statusCode: 500, data: null),
        ).category,
        FailureCategory.serverError,
      );
    });

    test('degraded and server errors are retryable', () {
      expect(
        AppFailure.from(
          dioError(DioExceptionType.badResponse, statusCode: 504, data: null),
        ).isRetryable,
        isTrue,
      );
      expect(
        AppFailure.from(
          dioError(DioExceptionType.badResponse, statusCode: 500, data: null),
        ).isRetryable,
        isTrue,
      );
      expect(
        AppFailure.from(
          dioError(DioExceptionType.badResponse, statusCode: 401, data: null),
        ).isRetryable,
        isFalse,
      );
    });
  });

  group('ApiClientException keeps its status code', () {
    test('503 from expectSuccessStatus classifies as degraded', () {
      late Object thrown;
      try {
        expectSuccessStatus(
          Response<dynamic>(
            requestOptions: RequestOptions(path: '/token/refresh/'),
            statusCode: 503,
            data: 'upstream down',
          ),
          'Token refresh',
        );
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<ApiClientException>());
      expect((thrown as ApiClientException).statusCode, 503);

      final failure = AppFailure.from(thrown);
      expect(failure.category, FailureCategory.sourceBlockedDegraded);
      expect(failure.statusCode, 503);
    });

    test('401 from expectSuccessStatus classifies as unauthorized', () {
      final failure = AppFailure.from(
        const ApiClientException('Token refresh failed', statusCode: 401),
      );

      expect(failure.category, FailureCategory.unauthorized);
      expect(failure.statusCode, 401);
      expect(failure.isRetryable, isFalse);
    });

    test('status-less ApiClientException stays an unexpected failure', () {
      final failure = AppFailure.from(
        const ApiClientException('POST /token/ failed: no backend URL'),
      );

      expect(failure.category, FailureCategory.unexpectedFailure);
      expect(failure.statusCode, isNull);
    });
  });
}
