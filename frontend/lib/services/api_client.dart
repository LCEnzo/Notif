import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/dio_credentials.dart';
import 'package:notif/services/json_contracts.dart';
import 'package:notif/services/refresh_cookie_store.dart';

const String builtinApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);

const Duration connectTimeout = Duration(seconds: 10);
const Duration receiveTimeout = Duration(seconds: 15);

/// Shared Dio instance — connection pooling happens here.
final Dio _dio = _createDio();

Dio _createDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    ),
  );
  configureDioCredentials(dio);
  dio.interceptors.addAll([
    if (kDebugMode)
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint(o.toString()),
      ),
  ]);
  return dio;
}

/// The app's own Dio instance, exposed so tests can install a fake HTTP
/// adapter and drive the real request pipeline — URL fallback, auth retry —
/// instead of a stubbed-out copy of it.
@visibleForTesting
Dio get apiDio => _dio;

typedef AccessTokenReader = String? Function();
typedef RefreshAccessToken = Future<String?> Function();

class ApiClientException implements Exception {
  const ApiClientException(this.message, {this.statusCode, this.data});

  final String message;

  /// HTTP status that produced this failure, when there was a response.
  /// Preserved so [AppFailure] can classify it instead of degrading every
  /// non-2xx into an unexpected failure.
  final int? statusCode;

  /// Response body that produced this failure, for message extraction.
  final Object? data;

  @override
  String toString() => message;
}

AccessTokenReader? _accessTokenReader;
RefreshAccessToken? _refreshAccessToken;

/// Wires the API client to the auth service. The refresh callback owns every
/// auth state transition, including expiry — the client only retries the
/// original request once when a new token comes back.
void configureApiAuth({
  required AccessTokenReader accessTokenReader,
  required RefreshAccessToken refreshAccessToken,
}) {
  _accessTokenReader = accessTokenReader;
  _refreshAccessToken = refreshAccessToken;
}

@visibleForTesting
void resetApiAuthForTesting() {
  _accessTokenReader = null;
  _refreshAccessToken = null;
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

Future<Response<List<int>>> apiGetBytes(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
}) async {
  final response = await _requestWithFallback(
    'GET',
    path,
    settings: settings,
    headers: headers,
    responseType: ResponseType.bytes,
  );
  return Response<List<int>>(
    data: response.data is List<int> ? response.data as List<int> : null,
    headers: response.headers,
    requestOptions: response.requestOptions,
    statusCode: response.statusCode,
    statusMessage: response.statusMessage,
    redirects: response.redirects,
    extra: response.extra,
    isRedirect: response.isRedirect,
  );
}

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
  ResponseType? responseType,
}) async {
  final urls = resolveUrls(path, settings);
  if (urls.isEmpty) {
    throw ApiClientException(
      '$method $path failed: no backend URL configured',
    );
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
        responseType: responseType,
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

  throw ApiClientException(
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
  ResponseType? responseType,
}) async {
  final requestUri = _buildRequestUri(baseUrl, path);
  final requestHeaders = await _headersWithLatestAccessToken(
    headers,
    requestUri: requestUri,
    path: path,
  );

  try {
    final response = await _dio.requestUri<dynamic>(
      requestUri,
      data: body,
      options: Options(
        method: method,
        headers: requestHeaders,
        responseType: responseType,
      ),
    );
    await _rememberNativeRefreshCookieFromResponse(requestUri, response);
    return response;
  } on DioException catch (error) {
    await _rememberNativeRefreshCookieFromResponse(requestUri, error.response);
    if (allowAuthRetry && await _shouldRetryAfterUnauthorized(error, headers)) {
      return _performRequest(
        method,
        baseUrl,
        path,
        headers: headers,
        body: body,
        allowAuthRetry: false,
        responseType: responseType,
      );
    }
    rethrow;
  }
}

Future<void> _rememberNativeRefreshCookieFromResponse(
  Uri responseUri,
  Response<dynamic>? response,
) async {
  await rememberNativeRefreshCookie(
    responseUri,
    response?.headers.map['set-cookie'] ??
        response?.headers.map['Set-Cookie'] ??
        const [],
  );
}

Future<Map<String, String>> _headersWithLatestAccessToken(
  Map<String, String> headers, {
  required Uri requestUri,
  required String path,
}) async {
  final updated = Map<String, String>.from(headers);
  final currentAuthorization = headers['Authorization'];
  if (currentAuthorization != null &&
      currentAuthorization.startsWith('Bearer ')) {
    final latestAccessToken = _accessTokenReader?.call();
    if (latestAccessToken != null && latestAccessToken.isNotEmpty) {
      updated['Authorization'] = 'Bearer $latestAccessToken';
    }
  }

  final refreshCookie = await nativeRefreshCookieHeader(requestUri, path);
  if (refreshCookie != null && refreshCookie.isNotEmpty) {
    updated['Cookie'] = refreshCookie;
  }
  return updated;
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
  try {
    return await _refreshAccessToken?.call();
  } on Exception catch (error) {
    if (kDebugMode) {
      debugPrint('api_client._refreshAccessTokenIfNeeded: $error');
    }
    return null;
  }
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

/// Validates [response] is 200 and returns its body as a JSON object map.
/// Throws [ApiClientException] on any other status and [ContractViolation]
/// when the body is not a JSON object.
Map<String, Object?> expectSuccessJson(
  Response<dynamic> response,
  String context,
) {
  return expectSuccessObject(response, context).object();
}

JsonCursor expectSuccessObject(
  Response<dynamic> response,
  String context, {
  Set<int> successCodes = const {200},
}) {
  expectSuccessStatus(response, context, successCodes: successCodes);
  final cursor = JsonCursor.root(endpoint: context, value: response.data);
  cursor.object();
  return cursor;
}

List<Object?> expectSuccessList(Response<dynamic> response, String context) {
  return expectSuccessArray(response, context).array();
}

JsonCursor expectSuccessArray(
  Response<dynamic> response,
  String context, {
  Set<int> successCodes = const {200},
}) {
  expectSuccessStatus(response, context, successCodes: successCodes);
  final cursor = JsonCursor.root(endpoint: context, value: response.data);
  cursor.array();
  return cursor;
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

  throw ApiClientException(
    "$context failed: (${response.statusCode}) ${response.data}",
    statusCode: statusCode,
    data: response.data,
  );
}
