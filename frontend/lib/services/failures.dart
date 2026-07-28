import 'package:dio/dio.dart';
import 'package:notif/services/api_client.dart';
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

/// Categories that describe a transport/availability problem: the same call
/// can succeed later without the user doing anything. Never a reason to drop
/// credentials.
const Set<FailureCategory> retryableCategories = {
  FailureCategory.networkUnavailable,
  FailureCategory.timeout,
  FailureCategory.sourceBlockedDegraded,
  FailureCategory.serverError,
};

/// Categories where the server actively rejected the credentials we sent.
/// Only these justify tearing down a session.
const Set<FailureCategory> authRejectionCategories = {
  FailureCategory.unauthorized,
  FailureCategory.forbidden,
};

// User-facing copy. Transport libraries produce text for developers
// ("The connection errored: Connection refused ..."); users get these instead
// and the technical text is kept in [AppFailure.detail] for logs.
const String _offlineCopy =
    'Cannot reach the server. Check your connection and try again.';
const String _timeoutCopy =
    'The server took too long to respond. Try again in a moment.';
const String _degradedCopy =
    'The server is temporarily unavailable. Try again in a moment.';
const String _serverErrorCopy = 'The server failed while handling the request.';
const String _unexpectedCopy = 'The request could not be completed.';

/// Longest server-supplied message we are willing to show a user. Longer
/// bodies are error pages, tracebacks or HTML, not copy.
const int _maxServerMessageLength = 240;

class AppFailure implements Exception {
  const AppFailure({
    required this.category,
    required this.message,
    this.statusCode,
    this.detail,
    this.endpoint,
    this.contractPath,
    this.expected,
    this.actual,
    this.cause,
  });

  factory AppFailure.from(
    Object error, {
    String? endpoint,
  }) {
    if (error is AppFailure) {
      return error;
    }

    if (error is ContractViolation) {
      return AppFailure(
        category: FailureCategory.contractViolation,
        message: 'Server response did not match the app contract.',
        endpoint: error.endpoint,
        contractPath: error.path,
        expected: error.expected,
        actual: error.actual,
        detail: error.toString(),
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
        detail: error.toString(),
        cause: error,
      );
    }

    if (error is PreferenceException) {
      return AppFailure(
        category: FailureCategory.corruptLocalState,
        message: 'The app could not read or write local settings.',
        endpoint: endpoint,
        detail: error.toString(),
        cause: error,
      );
    }

    if (error is DioException) {
      return _fromDio(error, endpoint: endpoint);
    }

    if (error is ApiClientException) {
      return _fromApiClient(error, endpoint: endpoint);
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

  /// HTTP status behind the failure, when there was one.
  final int? statusCode;

  /// Technical description for logs and diagnostics. Never shown to users.
  final String? detail;
  final String? endpoint;
  final String? contractPath;
  final String? expected;
  final String? actual;
  final Object? cause;

  String get userMessage => message;

  /// Message plus the transport detail, for debug logs and client events.
  String get debugMessage {
    final technical = detail;
    if (technical == null || technical.isEmpty || message.contains(technical)) {
      return message;
    }
    return '$message [$technical]';
  }

  /// True when retrying the same request later is the right response.
  bool get isRetryable => retryableCategories.contains(category);

  /// True when the server rejected our credentials — the only case where
  /// dropping the session is correct.
  bool get isAuthRejection => authRejectionCategories.contains(category);

  @override
  String toString() => debugMessage;
}

AppFailure _fromDio(DioException error, {String? endpoint}) {
  final statusCode = error.response?.statusCode;
  final byStatus = _categoryForStatus(statusCode);
  if (byStatus != null) {
    return AppFailure(
      category: byStatus,
      message:
          _serverMessage(error.response?.data) ?? _copyForCategory(byStatus),
      statusCode: statusCode,
      endpoint: endpoint,
      detail: error.message,
      cause: error,
    );
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return AppFailure(
        category: FailureCategory.timeout,
        message: _timeoutCopy,
        endpoint: endpoint,
        detail: error.message,
        cause: error,
      );
    case DioExceptionType.badCertificate:
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      return AppFailure(
        category: FailureCategory.networkUnavailable,
        message: _offlineCopy,
        endpoint: endpoint,
        detail: error.message,
        cause: error,
      );
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return AppFailure(
        category: FailureCategory.unexpectedFailure,
        message: _serverMessage(error.response?.data) ?? _unexpectedCopy,
        statusCode: statusCode,
        endpoint: endpoint,
        detail: error.message,
        cause: error,
      );
  }
}

AppFailure _fromApiClient(ApiClientException error, {String? endpoint}) {
  final statusCode = error.statusCode;
  final byStatus = _categoryForStatus(statusCode);
  if (byStatus == null) {
    return AppFailure(
      category: FailureCategory.unexpectedFailure,
      message: error.message,
      statusCode: statusCode,
      endpoint: endpoint,
      cause: error,
    );
  }

  return AppFailure(
    category: byStatus,
    message: _serverMessage(error.data) ?? _copyForCategory(byStatus),
    statusCode: statusCode,
    endpoint: endpoint,
    detail: error.message,
    cause: error,
  );
}

/// Maps an HTTP status to a category, or null when the status carries no
/// classification (2xx, 3xx, unknown 4xx or absent).
FailureCategory? _categoryForStatus(int? statusCode) {
  if (statusCode == null) {
    return null;
  }
  if (statusCode == 401) {
    return FailureCategory.unauthorized;
  }
  if (statusCode == 403) {
    return FailureCategory.forbidden;
  }
  if (statusCode == 400 || statusCode == 422) {
    return FailureCategory.validationFailed;
  }
  // 429 rate limiting, 502/503/504 gateway/upstream failures and the
  // Cloudflare-specific 520-527 range are outages in front of the app, not
  // app bugs. The deployment sits behind Cloudflare and Caddy, so these are
  // what a restart or upstream hiccup looks like from the client.
  if (statusCode == 429 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504 ||
      (statusCode >= 520 && statusCode <= 527)) {
    return FailureCategory.sourceBlockedDegraded;
  }
  if (statusCode >= 500) {
    return FailureCategory.serverError;
  }
  return null;
}

String _copyForCategory(FailureCategory category) {
  return switch (category) {
    FailureCategory.networkUnavailable => _offlineCopy,
    FailureCategory.timeout => _timeoutCopy,
    FailureCategory.unauthorized => 'Sign in again to continue.',
    FailureCategory.forbidden => 'You do not have permission to do that.',
    FailureCategory.validationFailed =>
      'The request was rejected by the server.',
    FailureCategory.contractViolation =>
      'Server response did not match the app contract.',
    FailureCategory.corruptLocalState =>
      'The app could not read or write local settings.',
    FailureCategory.sourceBlockedDegraded => _degradedCopy,
    FailureCategory.serverError => _serverErrorCopy,
    FailureCategory.unexpectedFailure => _unexpectedCopy,
  };
}

/// Server-supplied text that is safe to show a user, or null when the body is
/// an error page rather than a message (gateway HTML, tracebacks, dumps).
String? _serverMessage(Object? data) {
  final extracted = extractErrorMessage(data);
  if (extracted == null || extracted.isEmpty) {
    return null;
  }
  if (extracted.length > _maxServerMessageLength) {
    return null;
  }
  final lowered = extracted.toLowerCase();
  if (lowered.contains('<!doctype') ||
      lowered.contains('<html') ||
      lowered.contains('</')) {
    return null;
  }
  return extracted;
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
