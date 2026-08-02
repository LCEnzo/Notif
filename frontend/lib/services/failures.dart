import 'package:dio/dio.dart';
import 'package:notif/services/json_contracts.dart';
import 'package:notif/services/persistence.dart';

enum FailureCategory {
  networkUnavailable('network_unavailable'),
  timeout('timeout'),
  unauthorized('unauthorized'),
  forbidden('forbidden'),
  validationFailed('validation_failed'),
  contractViolation('contract_violation'),
  corruptLocalState('corrupt_local_state'),
  sourceBlockedDegraded('source_blocked_degraded'),
  serverError('server_error'),
  unexpectedFailure('unexpected_failure')
  ;

  const FailureCategory(this.wireName);

  final String wireName;
}

class AppFailure implements Exception {
  const AppFailure({
    required this.category,
    required this.message,
    this.endpoint,
    this.contractPath,
    this.expected,
    this.actual,
    this.cause,
  });

  factory AppFailure.from(Object error, {String? endpoint}) {
    if (error is ContractViolation) {
      return AppFailure(
        category: FailureCategory.contractViolation,
        message: 'Server response did not match the app contract.',
        endpoint: error.endpoint,
        contractPath: error.path,
        expected: error.expected,
        actual: error.actual,
        cause: error,
      );
    }

    if (error is CorruptLocalStateException) {
      return AppFailure(
        category: FailureCategory.corruptLocalState,
        message: 'Saved app settings are corrupt and were ignored.',
        endpoint: endpoint,
        expected: error.expected,
        actual: error.actual,
        cause: error,
      );
    }

    if (error is PreferenceException) {
      return AppFailure(
        category: FailureCategory.corruptLocalState,
        message: 'The app could not read or write local settings.',
        endpoint: endpoint,
        cause: error,
      );
    }

    if (error is DioException) {
      return _fromDio(error, endpoint: endpoint);
    }

    final text = error.toString();
    return AppFailure(
      category: FailureCategory.unexpectedFailure,
      message: text.startsWith('Exception: ') ? text.substring(11) : text,
      endpoint: endpoint,
      cause: error,
    );
  }

  final FailureCategory category;
  final String message;
  final String? endpoint;
  final String? contractPath;
  final String? expected;
  final String? actual;
  final Object? cause;

  String get userMessage => message;

  @override
  String toString() => message;
}

AppFailure _fromDio(DioException error, {String? endpoint}) {
  final statusCode = error.response?.statusCode;
  final extracted = extractErrorMessage(error.response?.data);
  if (statusCode == 401) {
    return AppFailure(
      category: FailureCategory.unauthorized,
      message: extracted ?? 'Sign in again to continue.',
      endpoint: endpoint,
      cause: error,
    );
  }
  if (statusCode == 403) {
    return AppFailure(
      category: FailureCategory.forbidden,
      message: extracted ?? 'You do not have permission to do that.',
      endpoint: endpoint,
      cause: error,
    );
  }
  if (statusCode == 400 || statusCode == 422) {
    return AppFailure(
      category: FailureCategory.validationFailed,
      message: extracted ?? 'The request was rejected by the server.',
      endpoint: endpoint,
      cause: error,
    );
  }
  if (statusCode == 429 || statusCode == 502 || statusCode == 503) {
    return AppFailure(
      category: FailureCategory.sourceBlockedDegraded,
      message: extracted ?? 'The source or server is temporarily unavailable.',
      endpoint: endpoint,
      cause: error,
    );
  }
  if (statusCode != null && statusCode >= 500) {
    return AppFailure(
      category: FailureCategory.serverError,
      message: extracted ?? 'The server failed while handling the request.',
      endpoint: endpoint,
      cause: error,
    );
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return AppFailure(
        category: FailureCategory.timeout,
        message: error.message ?? 'The request timed out.',
        endpoint: endpoint,
        cause: error,
      );
    case DioExceptionType.badCertificate:
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      return AppFailure(
        category: FailureCategory.networkUnavailable,
        message: error.message ?? 'The network is unavailable.',
        endpoint: endpoint,
        cause: error,
      );
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return AppFailure(
        category: FailureCategory.unexpectedFailure,
        message:
            extracted ?? error.message ?? 'The request could not be completed.',
        endpoint: endpoint,
        cause: error,
      );
  }
}

String? extractErrorMessage(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (value is List<Object?>) {
    final parts = value
        .map(extractErrorMessage)
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return null;
    }
    return parts.join('\n');
  }

  if (value is Map<Object?, Object?>) {
    final detail = value['detail'] ?? value['message'] ?? value['error'];
    final direct = extractErrorMessage(detail);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final parts = <String>[];
    for (final entry in value.entries) {
      final message = extractErrorMessage(entry.value);
      if (message != null && message.isNotEmpty) {
        parts.add('${entry.key}: $message');
      }
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join('\n');
  }

  return null;
}
