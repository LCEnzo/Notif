import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/json_contracts.dart';
import 'package:notif/services/persistence.dart';

void main() {
  DioException dioError(DioExceptionType type, {int? statusCode}) {
    return DioException(
      requestOptions: RequestOptions(path: '/test'),
      type: type,
      response: statusCode == null
          ? null
          : Response<dynamic>(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: statusCode,
              data: {'detail': 'server detail'},
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
}
