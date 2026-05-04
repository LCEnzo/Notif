import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:notif/services/app_settings.dart';

const String builtinApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);

const Duration connectTimeout = Duration(seconds: 10);
const Duration receiveTimeout = Duration(seconds: 15);

/// Shared Dio instance — connection pooling happens here.
final Dio _dio =
    Dio(
        BaseOptions(
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
        ),
      )
      ..interceptors.addAll([
        if (kDebugMode)
          LogInterceptor(
            requestBody: true,
            responseBody: true,
            logPrint: (o) => debugPrint(o.toString()),
          ),
      ]);

typedef AccessTokenReader = String? Function();
typedef RefreshTokenReader = String? Function();
typedef RefreshAccessToken = Future<String?> Function(String refreshToken);
typedef AuthExpiredHandler = Future<void> Function();

AccessTokenReader? _accessTokenReader;
RefreshTokenReader? _refreshTokenReader;
RefreshAccessToken? _refreshAccessToken;
AuthExpiredHandler? _authExpiredHandler;
Future<String?>? _refreshInFlight;

void configureApiAuth({
  required AccessTokenReader accessTokenReader,
  required RefreshTokenReader refreshTokenReader,
  required RefreshAccessToken refreshAccessToken,
  required AuthExpiredHandler authExpiredHandler,
}) {
  _accessTokenReader = accessTokenReader;
  _refreshTokenReader = refreshTokenReader;
  _refreshAccessToken = refreshAccessToken;
  _authExpiredHandler = authExpiredHandler;
}

/// Sends a POST request to [path], respecting [BackendUrlMode] from [settings].
///
/// In [BackendUrlMode.builtin] mode the built-in compile-time URL is used.
/// In [BackendUrlMode.customWithFallback] mode the custom URL is tried first;
/// on any network error the request is retried against the built-in URL.
/// In [BackendUrlMode.customOnly] mode only the custom URL is tried.
Future<Response<dynamic>> apiPost(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
  required dynamic body,
}) => _requestWithFallback(
  'POST',
  path,
  settings: settings,
  headers: headers,
  body: body,
);

Future<Response<dynamic>> apiGet(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
}) => _requestWithFallback('GET', path, settings: settings, headers: headers);

Future<Response<dynamic>> apiPatch(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
  required dynamic body,
}) => _requestWithFallback(
  'PATCH',
  path,
  settings: settings,
  headers: headers,
  body: body,
);

Future<Response<dynamic>> apiDelete(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
}) =>
    _requestWithFallback('DELETE', path, settings: settings, headers: headers);

List<String> resolveUrls(String path, AppSettingsController? settings) {
  final mode = settings?.backendUrlMode ?? BackendUrlMode.builtin;
  final custom = settings?.customBackendUrl.trim() ?? '';

  switch (mode) {
    case BackendUrlMode.builtin:
      return [builtinApiUrl];
    case BackendUrlMode.customWithFallback:
      if (custom.isEmpty) return [builtinApiUrl];
      return [custom, builtinApiUrl];
    case BackendUrlMode.customOnly:
      if (custom.isEmpty) return [];
      return [custom];
  }
}

Uri _buildRequestUri(String baseUrl, String path) {
  final normalizedBaseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
  return Uri.parse('$normalizedBaseUrl/$normalizedPath');
}

Future<Response<dynamic>> _requestWithFallback(
  String method,
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
  dynamic body,
}) async {
  final urls = resolveUrls(path, settings);
  if (urls.isEmpty) {
    throw StateError('$method $path failed: no backend URL configured');
  }

  Object? lastError;

  for (final url in urls) {
    try {
      return await _performRequest(
        method,
        url,
        path,
        headers: headers,
        body: body,
      );
    } on DioException catch (error) {
      lastError = error;
      final shouldTryFallback =
          !identical(url, urls.last) && _isFallbackableNetworkError(error);
      if (!shouldTryFallback) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint(
          '$method ${_buildRequestUri(url, path)} failed (${error.type}), '
          'trying fallback',
        );
      }
    } on FormatException catch (error) {
      lastError = error;
      if (identical(url, urls.last)) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint('$method $url invalid ($error), trying fallback');
      }
    }
  }

  throw StateError(
    '$method $path failed: ${lastError ?? 'all URLs exhausted'}',
  );
}

Future<Response<dynamic>> _performRequest(
  String method,
  String baseUrl,
  String path, {
  required Map<String, String> headers,
  dynamic body,
  bool allowAuthRetry = true,
}) async {
  final requestUri = _buildRequestUri(baseUrl, path);
  final requestHeaders = _headersWithLatestAccessToken(headers);

  try {
    return await _dio.requestUri<dynamic>(
      requestUri,
      data: body,
      options: Options(method: method, headers: requestHeaders),
    );
  } on DioException catch (error) {
    if (allowAuthRetry && await _shouldRetryAfterUnauthorized(error, headers)) {
      return _performRequest(
        method,
        baseUrl,
        path,
        headers: headers,
        body: body,
        allowAuthRetry: false,
      );
    }
    rethrow;
  }
}

Map<String, String> _headersWithLatestAccessToken(Map<String, String> headers) {
  final currentAuthorization = headers['Authorization'];
  if (currentAuthorization == null ||
      !currentAuthorization.startsWith('Bearer ')) {
    return headers;
  }

  final latestAccessToken = _accessTokenReader?.call();
  if (latestAccessToken == null || latestAccessToken.isEmpty) {
    return headers;
  }

  return <String, String>{
    ...headers,
    'Authorization': 'Bearer $latestAccessToken',
  };
}

Future<bool> _shouldRetryAfterUnauthorized(
  DioException error,
  Map<String, String> headers,
) async {
  final hasBearerToken =
      headers['Authorization']?.startsWith('Bearer ') == true;
  if (!hasBearerToken ||
      error.type != DioExceptionType.badResponse ||
      error.response?.statusCode != 401) {
    return false;
  }

  final refreshedToken = await _refreshAccessTokenIfNeeded();
  return refreshedToken != null && refreshedToken.isNotEmpty;
}

Future<String?> _refreshAccessTokenIfNeeded() async {
  final inFlight = _refreshInFlight;
  if (inFlight != null) {
    return inFlight;
  }

  final refreshToken = _refreshTokenReader?.call();
  if (refreshToken == null || refreshToken.isEmpty) {
    await _authExpiredHandler?.call();
    return null;
  }

  final refresh = () async {
    try {
      return await _refreshAccessToken?.call(refreshToken);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('api_client._refreshAccessTokenIfNeeded: $error');
      }
      return null;
    } finally {
      _refreshInFlight = null;
    }
  }();

  _refreshInFlight = refresh;
  final refreshedToken = await refresh;
  if (refreshedToken == null || refreshedToken.isEmpty) {
    await _authExpiredHandler?.call();
    return null;
  }

  return refreshedToken;
}

bool _isFallbackableNetworkError(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.badCertificate:
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      return true;
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return false;
  }
}

/// Validates [response] is 200 and returns decoded JSON as `Map<String, dynamic>`.
/// Throws a descriptive [Exception] on any non-200 status.
Map<String, dynamic> expectSuccessJson(
  Response<dynamic> response,
  String context,
) {
  expectSuccessStatus(response, context, successCodes: const {200});
  if (response.data is Map) {
    return Map<String, dynamic>.from(response.data as Map);
  }

  throw Exception(
    "$context failed: expected a JSON object but got "
    "${_describeResponseShape(response.data)}.",
  );
}

List<dynamic> expectSuccessList(Response<dynamic> response, String context) {
  expectSuccessStatus(response, context, successCodes: const {200});
  if (response.data is List) {
    return List<dynamic>.from(response.data as List);
  }

  throw Exception(
    "$context failed: expected a JSON array but got "
    "${_describeResponseShape(response.data)}.",
  );
}

void expectSuccessStatus(
  Response<dynamic> response,
  String context, {
  Set<int>? successCodes,
}) {
  final statusCode = response.statusCode;
  final isSuccess = successCodes != null
      ? successCodes.contains(statusCode)
      : statusCode != null && statusCode >= 200 && statusCode < 300;
  if (isSuccess) {
    return;
  }

  throw Exception(
    "$context failed: (${response.statusCode}) "
    "${response.data}",
  );
}

String _describeResponseShape(dynamic value) {
  if (value == null) {
    return "no body";
  }
  if (value is Map) {
    return "a JSON object";
  }
  if (value is List) {
    return "a JSON array";
  }
  return value.runtimeType.toString();
}
