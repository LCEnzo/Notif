import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/generated/openapi.swagger.dart' as api;
import 'package:notif/services/failures.dart';
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
      const ContractViolation(schema: 'Link', detail: 'name missing'),
      endpoint: 'GET /monitoring/links/',
    );

    expect(failure.category, FailureCategory.contractViolation);
    expect(failure.endpoint, 'GET /monitoring/links/');
    expect(failure.contractPath, '#/components/schemas/Link');
    expect(failure.actual, 'name missing');
  });

  test('categories map one-to-one onto the schema enum', () {
    final wires = FailureCategory.values.map((category) => category.wire);

    expect(
      wires.toSet(),
      api.CategoryEnum.values.toSet()
        ..remove(api.CategoryEnum.swaggerGeneratedUnknown),
    );
    expect(wires.toSet(), hasLength(FailureCategory.values.length));
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
