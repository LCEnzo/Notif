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

/// Liveness probe. Cheap, unauthenticated, and safe to poll while waiting for
/// a backend to come back after a deploy.
const String healthPath = '/monitoring/health/';

/// Requests whose effect the server commits before we see the response, so a
/// transport-level retry is not a retry but a second, different operation.
///
/// `/token/refresh/` rotates the refresh-token family: the backend commits the
/// rotation and only then writes the response. Re-sending after a timeout
/// presents an already-rotated token, which the backend's theft detection
/// treats as a stolen-token replay and answers by revoking the whole family —
/// a hard logout with the credentials deleted. `/token/logout/` revokes, so a
/// replay is pointless but equally destructive to diagnose.
/// `/token/` (login) also commits before responding: the backend revokes the
/// caller's previous session family and issues a new cookie. Replaying it
/// after a lost response can revoke and mint families at two origins.
const Set<String> nonReplayablePaths = {
  '/token/',
  '/token/refresh/',
  '/token/logout/',
};

/// Requests whose credentials belong to one specific origin, so trying them
/// against a different base URL is not a fallback but an unauthenticated call.
///
/// The refresh cookie is scoped to the origin that issued it — the browser jar
/// on web, [refreshCookieName] keyed by `scheme://host:port` on native. Under
/// [BackendUrlMode.customWithFallback] a network failure at the custom origin
/// would otherwise re-send the refresh to the built-in origin, which has no
/// such cookie. The backend answers 401 "refresh token missing", the client
/// cannot tell that from a genuinely rejected session, and an outage at the
/// preferred origin becomes the forced logout this whole path exists to avoid.
/// Better to surface the transport failure and let recovery retry it.
const Set<String> originPinnedPaths = {'/token/refresh/', '/token/logout/'};

/// Shared Dio instance — connection pooling happens here.
final Dio _dio = _createDio();

/// Test seam: lets tests install a fake [HttpClientAdapter] on the same Dio
/// instance the app uses, so transport behaviour (fallback, retry, cookie
/// handling) is exercised for real instead of being mocked out.
@visibleForTesting
Dio get apiDio => _dio;

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

typedef AccessTokenReader = String? Function();
typedef RefreshAccessToken = Future<String?> Function();

/// The base URL of the origin that issued the current session, when one
/// exists. Session credentials — the refresh cookie and the access token it
/// mints — are valid at exactly that origin, so every request carrying them
/// is sent only there, never to a fallback.
typedef SessionBaseUrlReader = String? Function();

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
SessionBaseUrlReader? _sessionBaseUrlReader;

void configureApiAuth({
  required AccessTokenReader accessTokenReader,
  required RefreshAccessToken refreshAccessToken,
  required SessionBaseUrlReader sessionBaseUrlReader,
}) {
  _accessTokenReader = accessTokenReader;
  _refreshAccessToken = refreshAccessToken;
  _sessionBaseUrlReader = sessionBaseUrlReader;
}

@visibleForTesting
void resetApiAuthForTesting() {
  _accessTokenReader = null;
  _refreshAccessToken = null;
  _sessionBaseUrlReader = null;
}

/// Sends a POST request to [path], respecting [BackendUrlMode] from [settings].
///
/// In [BackendUrlMode.builtin] mode the built-in compile-time URL is used.
/// In [BackendUrlMode.customWithFallback] mode the custom URL is tried first;
/// on a network error that provably left the request unanswered the request is
/// retried against the built-in URL.
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
  String? baseUrlOverride,
}) => _requestWithFallback(
  'GET',
  path,
  settings: settings,
  headers: headers,
  baseUrlOverride: baseUrlOverride,
);

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

/// Base URLs to try, in order. Never contains duplicates: a custom URL that
/// spells the same thing as the built-in one is a single destination, not a
/// fallback chain, and sending every request twice to it is a bug.
List<String> resolveUrls(AppSettingsController? settings) {
  final mode = settings?.backendUrlMode ?? BackendUrlMode.builtin;
  final custom = settings?.customBackendUrl.trim() ?? '';

  switch (mode) {
    case BackendUrlMode.builtin:
      return [builtinApiUrl];
    case BackendUrlMode.customWithFallback:
      if (custom.isEmpty || custom == builtinApiUrl) return [builtinApiUrl];
      return [custom, builtinApiUrl];
    case BackendUrlMode.customOnly:
      if (custom.isEmpty) return [];
      return [custom];
  }
}

/// The backend origin when it is not same-site with the page hosting the app.
///
/// Only meaningful on web: browsers attach the `SameSite=Strict` refresh cookie
/// to same-site requests only, so pointing a web build at a cross-site backend
/// silently breaks remember-me — every refresh arrives without the cookie and
/// comes back 401, which looks exactly like an expired session. Returns null
/// when the configuration cannot cause that.
///
/// [isWeb] and [pageUri] exist so this is testable off-browser.
String? crossSiteBackendOrigin(
  AppSettingsController? settings, {
  bool isWeb = kIsWeb,
  Uri? pageUri,
  String? sessionBaseUrl,
}) {
  if (!isWeb) {
    return null;
  }

  final page = pageUri ?? Uri.base;
  // When the session's own origin is known, judge that one alone — a
  // cross-site origin elsewhere in the fallback chain never sees session
  // credentials and would make the diagnostic blame the wrong host.
  final candidates = sessionBaseUrl != null
      ? [sessionBaseUrl]
      : resolveUrls(settings);
  for (final url in candidates) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      // Relative URLs ("/api/v1") are same-origin by construction.
      continue;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      continue;
    }
    if (!_isSameSite(uri, page)) {
      return '${uri.scheme}://${uri.host}'
          '${uri.hasPort ? ':${uri.port}' : ''}';
    }
  }
  return null;
}

/// Approximates the SameSite definition: same scheme and same registrable
/// domain, ports ignored. Without the public-suffix list this is a heuristic,
/// which is why callers phrase the result as a diagnostic rather than a fact.
bool _isSameSite(Uri a, Uri b) {
  if (a.scheme != b.scheme) {
    return false;
  }
  final hostA = a.host.toLowerCase();
  final hostB = b.host.toLowerCase();
  if (hostA == hostB) {
    return true;
  }
  return _registrableDomain(hostA) == _registrableDomain(hostB);
}

/// Two-label public suffixes common enough to matter here. Without the full
/// public-suffix list, a tail like `co.uk` would count as a registrable
/// domain and make `a.example.co.uk` and `b.other.co.uk` look same-site.
const Set<String> _twoLabelPublicSuffixes = {
  'co.uk',
  'org.uk',
  'ac.uk',
  'gov.uk',
  'me.uk',
  'net.uk',
  'com.au',
  'net.au',
  'org.au',
  'edu.au',
  'gov.au',
  'co.jp',
  'ne.jp',
  'or.jp',
  'ac.jp',
  'go.jp',
  'com.br',
  'net.br',
  'org.br',
  'co.nz',
  'net.nz',
  'org.nz',
  'govt.nz',
  'co.in',
  'net.in',
  'org.in',
  'com.cn',
  'net.cn',
  'org.cn',
  'co.za',
  'org.za',
  'net.za',
  'com.mx',
  'com.ar',
  'com.tr',
  'com.sg',
  'com.hk',
  'com.tw',
  'co.kr',
  'or.kr',
};

String _registrableDomain(String host) {
  final labels = host.split('.');
  if (labels.length <= 2) {
    return host;
  }
  final lastTwo = labels.sublist(labels.length - 2).join('.');
  final registrableLabels = _twoLabelPublicSuffixes.contains(lastTwo) ? 3 : 2;
  if (labels.length <= registrableLabels) {
    return host;
  }
  return labels.sublist(labels.length - registrableLabels).join('.');
}

/// The configured base URL that actually served [response] — the origin a
/// just-established session belongs to. Null when no configured base matches
/// (settings changed mid-flight); callers then simply have no origin to pin.
String? servingBaseUrl(
  Response<dynamic> response,
  AppSettingsController? settings,
) {
  final served = response.requestOptions.uri.toString();
  String? best;
  for (final base in resolveUrls(settings)) {
    final normalized = base.replaceFirst(RegExp(r'/+$'), '');
    if (served == normalized || served.startsWith('$normalized/')) {
      if (best == null || normalized.length > best.length) {
        best = normalized;
      }
    }
  }
  return best;
}

Uri _buildRequestUri(String baseUrl, String path) {
  final normalizedBaseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
  return Uri.parse('$normalizedBaseUrl/$normalizedPath');
}

bool _isReplayable(String path) {
  final normalized = path.startsWith('/') ? path : '/$path';
  return !nonReplayablePaths.any(normalized.startsWith);
}

bool _isOriginPinned(String path) {
  final normalized = path.startsWith('/') ? path : '/$path';
  return originPinnedPaths.any(normalized.startsWith);
}

Future<Response<dynamic>> _requestWithFallback(
  String method,
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
  dynamic body,
  ResponseType? responseType,
  String? baseUrlOverride,
}) async {
  final urls = resolveUrls(settings);
  if (baseUrlOverride == null && urls.isEmpty) {
    throw ApiClientException(
      '$method $path failed: no backend URL configured',
    );
  }

  final replayable = _isReplayable(path);

  // Session credentials — the refresh cookie and the bearer token it minted —
  // exist at exactly the origin that served login. Requests carrying either
  // are sent only there: a fallback would at best 401 with an unknown token
  // and at worst hand the token to a different origin or look like a revoked
  // session. Before any session exists (a cold-start refresh probe with no
  // persisted origin), the preferred origin is the only sensible guess.
  final carriesSessionCredentials =
      _isOriginPinned(path) ||
      headers['Authorization']?.startsWith('Bearer ') == true;
  final sessionBaseUrl = _sessionBaseUrlReader?.call();

  final List<String> candidates;
  if (baseUrlOverride != null) {
    candidates = [baseUrlOverride];
  } else if (carriesSessionCredentials) {
    candidates = [sessionBaseUrl ?? urls.first];
  } else {
    candidates = urls;
  }

  // Every URL except the last may fall back; the last one is attempted
  // outside the loop so its failure propagates untouched.
  for (final url in candidates.take(candidates.length - 1)) {
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
      if (!_isFallbackableNetworkError(error, replayable: replayable)) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint(
          '$method ${_buildRequestUri(url, path)} failed (${error.type}), '
          'trying fallback',
        );
      }
    } on FormatException catch (error) {
      if (kDebugMode) {
        debugPrint('$method $url invalid ($error), trying fallback');
      }
    }
  }

  return _performRequest(
    method,
    candidates.last,
    path,
    headers: headers,
    body: body,
    responseType: responseType,
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

/// Asks the auth layer for a fresh access token. Deliberately does *not*
/// decide anything about session state: the refresher owns that transition and
/// is the only place that knows whether the failure was a rejection, an outage,
/// or a stale response from a session that has since been replaced. A caller
/// telling it "the session expired" here used to kill freshly re-logged-in
/// sessions whenever a slow request 401'd after a new login.
Future<String?> _refreshAccessTokenIfNeeded() async {
  String? refreshedToken;
  try {
    refreshedToken = await _refreshAccessToken?.call();
  } on Exception catch (error) {
    if (kDebugMode) {
      debugPrint('api_client._refreshAccessTokenIfNeeded: $error');
    }
  }

  if (refreshedToken == null || refreshedToken.isEmpty) {
    return null;
  }

  return refreshedToken;
}

/// Whether [error] leaves the request provably unanswered, so re-sending it to
/// the next base URL is safe.
///
/// [replayable] is false for requests the server may have already committed
/// (see [nonReplayablePaths]). For those, only failures that happen before the
/// request reaches the server at all can be retried: a connect timeout means
/// no connection was established, a bad certificate means the transport was
/// refused during TLS. Everything else — send/receive timeouts, dropped
/// connections (which is also how the browser reports a failed XHR), unknown
/// transport errors — can happen *after* the server processed the request, and
/// retrying those is what destroys credentials.
bool _isFallbackableNetworkError(
  DioException error, {
  required bool replayable,
}) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.badCertificate:
      return true;
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      return replayable;
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return false;
  }
}

/// Validates [response] is 200 and returns decoded JSON as `Map<String, dynamic>`.
/// Throws a descriptive [Exception] on any non-200 status.
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
